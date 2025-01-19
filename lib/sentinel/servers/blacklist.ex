defmodule Sentinel.Servers.Blacklist do
  @moduledoc """
  Manage blacklist domains
  """
  use GenServer

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
  def handle_call({:add_domain, %{domain: domain, type: type, user: mac_addr}}, _from, state) do
    {ip_str, _} = System.cmd("dig", ["+short", domain])

    if ip_str != "" do
      # split the ip string
      ip_list = String.split(ip_str, "\n") |> Enum.filter(fn ip -> ip != "" end)

      # Loop and add the ip to the blacklist
      Enum.each(ip_list, fn ip ->
        # Get current data
        {_, data} = read_file()

        # policy
        policy = %{
          "type" => type,
          "ip" => ip,
          "mac_addr" => mac_addr,
          "domain" => domain,
          "ttl" => "NULL"
        }

        case File.write(path(), Jason.encode!(data ++ [policy])) do
          :ok ->
            # We add the item to iptables
            add_policy(policy)

          {:error, err} ->
            {:error, "Failed to add domain to blacklist: #{inspect(err)}"}
        end
      end)
    end

    {:reply, {:ok, %{}}, state}
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
        IO.inspect("Adding policy to iptables: #{inspect(policy)}")
        add_policy(policy)
      end
    end)

    {:noreply, state}
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
  def has_policy?(policy)do
    if Application.get_env(:sentinel, :mock_data, false) do
      false
    else
      # sudo iptables -t mangle -I PREROUTING -m mac --mac-source [MAC] -d [DOMAIN] -j DROP
      exit_code =
        if policy["type"] === "user" do
          {_output, exit_code} =
            System.cmd("sudo", [
              "iptables",
              "-t",
              "mangle",
              "-C",
              "PREROUTING",
              "-m",
              "mac",
              "--mac-source",
              policy["mac_addr"],
              "-d",
              policy["ip"],
              "-j",
              "DROP"
            ])

          exit_code
        else
          {_output, exit_code} =
            System.cmd("sudo", [
              "iptables",
              "-t",
              "mangle",
              "-C",
              "PREROUTING",
              "-d",
              policy["ip"],
              "-j",
              "DROP"
            ])

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
  def add_policy(policy)do
    if Application.get_env(:sentinel, :mock_data, false) do
      :ok
    else
      if policy["type"] === "user" do
        # sudo iptables -t mangle -I PREROUTING -m mac --mac-source [MAC] -d [DOMAIN] -j DROP
        System.cmd("iptables", [
          "-t",
          "mangle",
          "-I",
          "PREROUTING",
          "-m",
          "mac",
          "--mac-source",
          policy["mac_addr"],
          "-d",
          policy["ip"],
          "-j",
          "DROP"
        ])

        {:ok, "Policy Added"}
      else
        # sudo iptables -t mangle -I PREROUTING -d [DOMAIN] -j DROP
        System.cmd("iptables", [
          "-t",
          "mangle",
          "-I",
          "PREROUTING",
          "-d",
          policy["ip"],
          "-j",
          "DROP"
        ])
      end

      {:ok, "Policy Added"}
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

  def add_domain(domain, %{type: type, user: mac_addr}),
    do: GenServer.call(__MODULE__, {:add_domain, %{domain: domain, type: type, user: mac_addr}})

  @doc """
  Check if the Blacklist file exists
  """
  def file_exists?(), do: path() |> File.exists?()

  # Path helper
  defp path(), do: "./" <> config_fs(:root) <> config_fs(:blacklist)

  # Config helper
  defp config_fs(), do: Application.get_env(:sentinel, :fs)
  defp config_fs(key), do: config_fs()[key]
end
