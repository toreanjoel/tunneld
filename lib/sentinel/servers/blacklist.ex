defmodule Sentinel.Servers.Blacklist do
  @moduledoc """
  Manage blacklist domains
  """
  use GenServer
  alias Iptables

  # Check every 60s if one of the items in the blacklist had a ttl and remove it if it has expired
  @ttl_check_interval 60_000

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init blacklist
  """
  def init(_) do
    # send(self(), :sync)
    if not file_exists?(), do: create_file()

    # Here we need to add data to Iptables
    send(self(), :init_iptables)

    # delayed start of the ttl check
    ttl_cron()

    {:ok, %{}}
  end

  # Here we get the list of domains based off page
  def handle_call({:get_blacklist_page, offset, limit}, _from, state) do
    result = fetch_blacklist(offset, limit)
    check_ahead = fetch_blacklist(offset + limit, limit)

    # We check if there is more data ahead
    result = %{
      data: result,
      has_more_data: !Enum.empty?(check_ahead),
      curr_page: offset
    }

    {:reply, {:ok, result}, state}
  end

  # Here we add the domain to the blacklist
  def handle_call(
        {:add_domain, %{domain: domain, type: type, user: mac_addr, ttl: ttl}},
        _from,
        state
      ) do
    {ip_str, _} = System.cmd("dig", ["+short", domain])

    if ip_str != "" do
      # split the ip string
      ip_list = String.split(ip_str, "\n") |> Enum.filter(fn ip -> ip != "" end)

      # Loop and add the ip to the blacklist
      Enum.each(ip_list, fn ip ->
        # Get current data
        {_, data} = read_file()

        # Converting to seconds
        ttl =
          if is_nil(ttl) or ttl === "",
            do: "NULL",
            else: (System.os_time(:second) + String.to_integer(ttl) * 60) |> Integer.to_string()

        # policy
        policy = %{
          "type" => type,
          "ip" => ip,
          "mac_addr" => if(type == "user", do: mac_addr, else: "-"),
          "domain" => domain,
          "ttl" => ttl
        }

        data = data ++ [policy]

        write_file = File.write(path(), Jason.encode!(data))

        case write_file do
          :ok ->
            # We add the item to iptables
            # TODO: maybe try do this first and then write to file? - could have errors
            add_policy(policy)

          {:error, err} ->
            {:error, "Failed to add domain to blacklist: #{inspect(err)}"}
        end
      end)
    end

    {:reply, {:ok, %{}}, state}
  end

  # Sentinel.Servers.Blacklist.remove_domain("example.com", %{ type: "system", user: "123"})
  # Request to remove the domains from the blacklist and from iptables
  def handle_call({:remove_domain, %{domain: domain, type: type, user: mac_addr}}, _from, state) do
    # Read from the blacklist file
    {_, data} = read_file()

    # Get all items that need to be removed - domains could have multiple servers stored
    items_to_remove =
      Enum.filter(data, fn policy ->
        policy["domain"] === domain and policy["type"] === type
      end)

    # Update the file to new data set
    updated_blocklist =
      Enum.reject(data, fn policy ->
        policy["domain"] === domain and policy["type"] === type
      end)

    write_file = File.write(path(), Jason.encode!(updated_blocklist))

    # Attemtp to remove the items from iptables
    Enum.each(items_to_remove, fn policy ->
      # Check if the entry already exists
      if has_policy?(policy) do
        IO.inspect("Removing policy from iptables: #{inspect(policy)}")

        case write_file do
          :ok ->
            # We remove the item to iptables
            remove_policy(policy)

          {:error, err} ->
            {:error, "Failed to remove domain to blacklist: #{inspect(err)}"}
        end
      else
        IO.inspect("No policy found to remove from iptables: #{inspect(policy)}")
      end
    end)

    {:reply, {:ok, %{}}, state}
  end

  # Process the list of items in the blacklist and check if the ttl is expired
  def handle_info(:ttl_job, state) do
    {_, data} = read_file()

    # Get all items that need to be removed - domains could have multiple servers stored
    items_to_remove =
      Enum.filter(data, fn policy ->
        ttl = String.to_integer(policy["ttl"])
        System.os_time(:second) > ttl
      end)

    # Update the file to new data set
    updated_blocklist =
      Enum.reject(data, fn policy ->
        ttl = String.to_integer(policy["ttl"])
        System.os_time(:second) > ttl
      end)

    write_file = File.write(path(), Jason.encode!(updated_blocklist))

    Enum.each(items_to_remove, fn policy ->
      if policy["ttl"] != "" or policy["ttl"] != "NULL" do
        IO.inspect("TTL Expired for #{policy["domain"]}, removing from blacklist")

        if has_policy?(policy) do
          IO.inspect("Removing policy from iptables: #{inspect(policy)}")

          case write_file do
            :ok ->
              # We remove the item to iptables
              remove_policy(policy)

            {:error, err} ->
              {:error, "Failed to remove domain to blacklist: #{inspect(err)}"}
          end
        else
          IO.inspect("No policy found to remove from iptables: #{inspect(policy)}")
        end
      end
    end)

    # Restart the ttl cron
    ttl_cron()

    {:noreply, state}
  end

  # Add entiries to iptables - async as we have the system starting up at this point
  def handle_info(:init_iptables, state) do
    # Read from the blacklist file
    {_, data} = read_file()

    # Loop over the data
    Enum.each(data, fn policy ->
      # Check if the entry already exists
      if not has_policy?(policy) do
        # Add entry to entry table if it isnt added
        add_policy(policy)
      end
    end)

    {:noreply, state}
  end

  # The job that will start interval sync
  def ttl_cron() do
    :timer.send_after(@ttl_check_interval, :ttl_job)
  end

  # we fetch the user blacklist file data
  def fetch_blacklist(offset, limit) do
    if Application.get_env(:sentinel, :mock_data, false) do
      Sentinel.Servers.FakeData.Blacklist.get_data()
    else
      try do
        {_, data} = read_file()
        Enum.slice(data, offset, limit)
      rescue
        _ ->
          []
      end
    end
  end

  # we count the number of lines in the blacklist file
  def count_blacklist() do
    try do
      if Application.get_env(:sentinel, :mock_data, false) do
        Sentinel.Servers.FakeData.Blacklist.get_data() |> length
      else
        {_, data} = read_file()
        data |> length
      end
    rescue
      _ ->
        0
    end
  end

  # Here we check if the policy exists in the iptables
  def has_policy?(policy) do
    if Application.get_env(:sentinel, :mock_data, false) do
      false
    else
      # sudo iptables -t mangle -I PREROUTING -m mac --mac-source [MAC] -d [DOMAIN] -j DROP
      exit_code =
        if policy["type"] === "user" do
          {_output, exit_code} = Iptables.has_user_entry?(policy["ip"], policy["mac_addr"])
          exit_code
        else
          {_output, exit_code} = Iptables.has_system_entry?(policy["ip"])
          exit_code
        end

      # Check if things already exists
      if exit_code == 0 do
        true
      else
        false
      end
    end
  end

  # Here we add the policy for to iptables - system vs user will have systemwide vs not
  def add_policy(policy) do
    if Application.get_env(:sentinel, :mock_data, false) do
      :ok
    else
      IO.inspect("Adding policy to iptables: #{inspect(policy)}")

      if policy["type"] === "user" do
        Iptables.add_user_entry(policy["ip"], policy["mac_addr"])
        {:ok, "Policy Added"}
      else
        Iptables.add_system_entry(policy["ip"])
        {:ok, "Policy Added"}
      end
    end
  end

  # Remove a policy for to iptables - system vs user will have systemwide vs not
  def remove_policy(policy) do
    if Application.get_env(:sentinel, :mock_data, false) do
      :ok
    else
      if policy["type"] === "user" do
        Iptables.remove_user_entry(policy["ip"], policy["mac_addr"])
        {:ok, "Policy Removed"}
      else
        Iptables.remove_system_entry(policy["ip"])
        {:ok, "Policy Removed"}
      end
    end
  end

  @doc """
  Create the blacklist file
  """
  def create_file() do
    case path()
         |> File.write(Jason.encode!([])) do
      :ok ->
        {:ok, "Blacklist file created"}

      {:error, reason} ->
        {:error, "Failed to create Blacklist file: #{inspect(reason)}"}
    end
  end

  @doc """
  Read the Blacklist file
  """
  def read_file() do
    case path() |> File.read() do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, data} ->
            {:ok, data}

          {:error, err} ->
            {:error, "Failed to decode Blacklist file: #{inspect(err)}"}
        end

      {:error, reason} ->
        {:error, "There was a problem reading the file: #{inspect(reason)}"}
    end
  end

  def get_blacklist_page(offset, limit),
    do: GenServer.call(__MODULE__, {:get_blacklist_page, offset, limit})

  def add_domain(domain, %{type: type, ttl: ttl}) when type === "system",
    do:
      GenServer.call(
        __MODULE__,
        {:add_domain, %{domain: domain, type: type, user: "-", ttl: ttl}}
      )

  def add_domain(domain, %{type: type, user: mac_addr, ttl: ttl}) when type === "user",
    do:
      GenServer.call(
        __MODULE__,
        {:add_domain, %{domain: domain, type: type, user: mac_addr, ttl: ttl}}
      )

  def remove_domain(domain, %{type: type}) when type === "system",
    do: GenServer.call(__MODULE__, {:remove_domain, %{domain: domain, type: type, user: "-"}})

  def remove_domain(domain, %{type: type, user: mac_addr}) when type === "user",
    do:
      GenServer.call(__MODULE__, {:remove_domain, %{domain: domain, type: type, user: mac_addr}})

  @doc """
  Check if the Blacklist file exists
  """
  def file_exists?(), do: path() |> File.exists?()

  # Path helper
  def path(), do: "./" <> config_fs(:root) <> config_fs(:blacklist)

  # Config helper
  defp config_fs(), do: Application.get_env(:sentinel, :fs)
  defp config_fs(key), do: config_fs()[key]
end
