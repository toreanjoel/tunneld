defmodule Sentinel.Servers.Blacklist do
  @moduledoc """
  Manage blacklist domains
  """
  use GenServer
  alias Iptables

  # Check every 60s if one of the items in the blacklist had a ttl and remove it if it has expired
  @ttl_check_interval 60_000

  @broadcast_topic "component:details"
  @component_desktop_id "sidebar_details_desktop"
  @component_mobile_id "sidebar_details_mobile"
  @component_module SentinelWeb.Live.Components.Sidebar.Details

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init blacklist
  """
  def init(_) do
    if not file_exists?(), do: create_file()

    # Here we need to add data to Iptables
    send(self(), :init_iptables)

    # delayed start of the ttl check
    ttl_cron()

    {:ok, %{}}
  end

  # Existing paginated API remains unchanged
  def handle_call({:get_blacklist_page, offset, limit}, _from, state) do
    result = fetch_blacklist(offset, limit)
    check_ahead = fetch_blacklist(offset + limit, limit)

    result = %{
      data: result,
      has_more_data: !Enum.empty?(check_ahead),
      curr_page: offset
    }

    {:reply, {:ok, result}, state}
  end

  # New handler for init_state: read the full file and broadcast it.
  def handle_call(:init_state, _from, state) do
    case read_file() do
      {:ok, data} ->
        broadcast_blacklist(data)
        {:reply, {:ok, data}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Here we add the domain to the blacklist
  def handle_call({:add_domain, %{domain: domain, type: type, mac: mac, ttl: ttl}}, _from, state) do
    {ip_str, _} = System.cmd("dig", ["+short", domain])

    if ip_str != "" do
      ip_list = ip_str |> String.split("\n") |> Enum.filter(fn ip -> ip != "" end)

      Enum.each(ip_list, fn ip ->
        {_, data} = read_file()

        ttl =
          if is_nil(ttl) or ttl === "",
            do: "-",
            else: (System.os_time(:second) + String.to_integer(ttl) * 60)
                  |> Integer.to_string()

        policy = %{
          "type" => type,
          "ip" => ip,
          "mac" => if(type == "user", do: mac, else: "-"),
          "domain" => domain,
          "ttl" => ttl
        }

        data = data ++ [policy]

        write_file = File.write(path(), Jason.encode!(data))

        case write_file do
          :ok ->
            Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{ type: :info, message: "Domain added successfully: #{domain}"})
            add_policy(policy)
          {:error, err} ->
            Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{ type: :error, message: "Failed to add domain to blacklist: #{inspect(err)}"})
            {:error, "Failed to add domain to blacklist: #{inspect(err)}"}
        end
      end)
    end

    {:reply, {:ok, %{}}, state}
  end

  # Request to remove the domains from the blacklist and from iptables
  def handle_call({:remove_domain, %{domain: domain, type: type, mac: _mac}}, _from, state) do
    {_, data} = read_file()

    items_to_remove =
      Enum.filter(data, fn policy -> policy["domain"] === domain and policy["type"] === type end)

    updated_blocklist =
      Enum.reject(data, fn policy -> policy["domain"] === domain and policy["type"] === type end)

    write_file = File.write(path(), Jason.encode!(updated_blocklist))

    Enum.each(items_to_remove, fn policy ->
      if has_policy?(policy) do
        IO.inspect("Removing policy from iptables: #{inspect(policy)}")
        case write_file do
          :ok ->
            Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{ type: :info, message: "Domain removed successfully: #{domain}"})
            remove_policy(policy)
            {:error, err} ->
            Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{ type: :error, message: "Failed to remove domain from blacklist: #{inspect(err)}"})
            {:error, "Failed to remove domain from blacklist: #{inspect(err)}"}
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

    items_to_remove =
      Enum.filter(data, fn policy ->
        policy["ttl"] != "-" and System.os_time(:second) > String.to_integer(policy["ttl"])
      end)

    updated_blocklist =
      Enum.reject(data, fn policy ->
        policy["ttl"] != "-" and System.os_time(:second) > String.to_integer(policy["ttl"])
      end)

    write_file = File.write(path(), Jason.encode!(updated_blocklist))

    Enum.each(items_to_remove, fn policy ->
      if policy["ttl"] != "" do
        IO.inspect("TTL Expired for #{policy["domain"]}, removing from blacklist")
        if has_policy?(policy) do
          IO.inspect("Removing policy from iptables: #{inspect(policy)}")
          case write_file do
            :ok -> remove_policy(policy)
            {:error, err} -> {:error, "Failed to remove domain from blacklist: #{inspect(err)}"}
          end
        else
          IO.inspect("No policy found to remove from iptables: #{inspect(policy)}")
        end
      end
    end)

    ttl_cron()
    {:noreply, state}
  end

  # Add entries to iptables - async as we have the system starting up at this point
  def handle_info(:init_iptables, state) do
    {_, data} = read_file()

    Enum.each(data, fn policy ->
      if not has_policy?(policy) do
        add_policy(policy)
      end
    end)

    {:noreply, state}
  end

  # Schedule the TTL check
  def ttl_cron(), do: :timer.send_after(@ttl_check_interval, :ttl_job)

  # Helper: Broadcast the full blacklist data to the sidebar components.
  defp broadcast_blacklist(data) do
    payload = %{
      id: @component_desktop_id,
      module: @component_module,
      data: %{blacklist: data}
    }
    Phoenix.PubSub.broadcast(Sentinel.PubSub, @broadcast_topic, payload)

    payload_mobile = Map.put(payload, :id, @component_mobile_id)
    Phoenix.PubSub.broadcast(Sentinel.PubSub, @broadcast_topic, payload_mobile)
  end

  # Legacy: we fetch the user blacklist file data with pagination (still available if needed)
  defp fetch_blacklist(offset, limit) do
    if Application.get_env(:sentinel, :mock_data, false) do
      Sentinel.Servers.FakeData.Blacklist.get_data()
    else
      try do
        {_, data} = read_file()
        Enum.slice(data, offset, limit)
      rescue
        _ -> []
      end
    end
  end

  def count_blacklist() do
    try do
      if Application.get_env(:sentinel, :mock_data, false) do
        Sentinel.Servers.FakeData.Blacklist.get_data() |> length
      else
        {_, data} = read_file()
        length(data)
      end
    rescue
      _ -> 0
    end
  end

  # Here we check if the policy exists in the iptables
  def has_policy?(policy) do
    if Application.get_env(:sentinel, :mock_data, false) do
      false
    else
      exit_code =
        if policy["type"] === "user" do
          {_output, exit_code} = Iptables.has_user_entry?(policy["ip"], policy["mac"])
          exit_code
        else
          {_output, exit_code} = Iptables.has_system_entry?(policy["ip"])
          exit_code
        end

      exit_code == 0
    end
  end

  # Here we add the policy for to iptables - system vs user will have systemwide vs not
  def add_policy(policy) do
    if Application.get_env(:sentinel, :mock_data, false) do
      :ok
    else
      IO.inspect("Adding policy to iptables: #{inspect(policy)}")
      if policy["type"] === "user" do
        Iptables.add_user_entry(policy["ip"], policy["mac"])
        {:ok, "Policy Added"}
      else
        Iptables.add_system_entry(policy["ip"])
        {:ok, "Policy Added"}
      end
    end
  end

  # Remove a policy from iptables
  def remove_policy(policy) do
    if Application.get_env(:sentinel, :mock_data, false) do
      :ok
    else
      if policy["type"] === "user" do
        Iptables.remove_user_entry(policy["ip"], policy["mac"])
        {:ok, "Policy Removed"}
      else
        Iptables.remove_system_entry(policy["ip"])
        {:ok, "Policy Removed"}
      end
    end
  end

  @doc """
  Create the blacklist file.
  """
  def create_file() do
    case File.write(path(), Jason.encode!([])) do
      :ok -> {:ok, "Blacklist file created"}
      {:error, reason} -> {:error, "Failed to create Blacklist file: #{inspect(reason)}"}
    end
  end

  @doc """
  Read the Blacklist file.
  """
  def read_file() do
    case File.read(path()) do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, data} -> {:ok, data}
          {:error, err} -> {:error, "Failed to decode Blacklist file: #{inspect(err)}"}
        end
      {:error, reason} -> {:error, "There was a problem reading the file: #{inspect(reason)}"}
    end
  end

  def get_blacklist_page(offset, limit),
    do: GenServer.call(__MODULE__, {:get_blacklist_page, offset, limit})

  def add_domain(domain, %{type: type, ttl: ttl}) when type === "system" do
    GenServer.call(__MODULE__, {:add_domain, %{domain: domain, type: type, mac: "-", ttl: ttl}})
  end

  def add_domain(domain, %{type: type, mac: mac, ttl: ttl}) when type === "user" do
    GenServer.call(__MODULE__, {:add_domain, %{domain: domain, type: type, mac: mac, ttl: ttl}})
  end

  def remove_domain(domain, %{type: type}) when type === "system" do
    GenServer.call(__MODULE__, {:remove_domain, %{domain: domain, type: type, mac: "-"}})
  end

  def remove_domain(domain, %{type: type, mac: mac}) when type === "user" do
    GenServer.call(__MODULE__, {:remove_domain, %{domain: domain, type: type, mac: mac}})
  end

  def init_state(), do: GenServer.call(__MODULE__, :init_state)

  @doc """
  Check if the Blacklist file exists.
  """
  def file_exists?(), do: File.exists?(path())

  def path(), do: "./" <> config_fs(:root) <> config_fs(:blacklist)
  defp config_fs(), do: Application.get_env(:sentinel, :fs)
  defp config_fs(key), do: config_fs()[key]
end
