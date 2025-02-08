defmodule Sentinel.Servers.Whitelist do
  @moduledoc """
  Manage whitelisted access to the internet for the devices connected to the network
  """
  use GenServer
  alias Iptables

  # Check if the devices still have access
  # @access_ttl_interval 300_000
  @access_ttl_interval 10_000
  # Check the pending request of devices that requested already
  # @pending_ttl_interval 300_000
  @pending_ttl_interval 30_000

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init whitelist
  """
  def init(_) do
    if not file_exists?(), do: create_file()

    # Here we need to add data (user with access) to Iptables
    send(self(), :init_iptables)

    # delayed start of the ttl check
    access_ttl_cron()
    request_ttl_cron()

    {:ok, %{}}
  end

  # Here we get the list of devices and their internet access
  def handle_call({:get_whitelist_page, offset, limit}, _from, state) do
    result = fetch_whitelist(offset, limit)
    check_ahead = fetch_whitelist(offset + limit, limit)

    # We check if there is more data ahead
    result = %{
      data: result,
      has_more_data: !Enum.empty?(check_ahead),
      curr_page: offset
    }

    {:reply, {:ok, result}, state}
  end

  # Here we grant the device access to the internet
  def handle_call(
        {:add_device_access, %{hostname: hostname, ip: ip, mac: mac, ttl: ttl, status_: status}},
        _from,
        state
      ) do

     # Get current data
      {_, data} = read_file()

      # Converting to seconds
      ttl =
        if is_nil(ttl) or ttl === "",
          do: "-",
          else: (System.os_time(:second) + String.to_integer(ttl) * 60) |> Integer.to_string()

      # policy
      policy = %{
        "hostname" => hostname,
        "ip" => ip,
        "mac" => mac,
        "ttl" => ttl,
        "status" => status
      }

      data = data ++ [policy]

      write_file = File.write(path(), Jason.encode!(data))

      case write_file do
        :ok ->
          # We add the item to iptables
          # TODO: maybe try do this first and then write to file? - could have errors
          add_policy(policy)

        {:error, err} ->
          {:error, "Failed to add user internet: #{inspect(err)}"}
      end
    {:reply, {:ok, %{}}, state}
  end

  # Request to remove the domains from the blacklist and from iptables
  def handle_call({:remove_device_access, %{mac: mac }}, _from, state) do
    # Read from the blacklist file
    {_, data} = read_file()

    # Get all items that need to be removed
    policy =
      Enum.filter(data, fn policy -> policy["mac"] === mac end) |> Enum.at(0)

    # Update the file to new data set
    updated_whitelist = Enum.reject(data, fn policy -> policy["mac"] === mac end)
    write_file = File.write(path(), Jason.encode!(updated_whitelist))

    # We check if there was something found and try and remove it
    if not Enum.empty?(policy) do
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
    end

    {:reply, {:ok, %{}}, state}
  end

  # Process and check the devices that need to be removed access based on TTL
  def handle_info(:access_ttl_job, state) do
    {_, data} = read_file()

    # Check which device has a TTL
    # Check if the device is added to the firewall already
    # Here we remove the device from access to internet if they had a ttl
    # remove from the file for access

    IO.inspect("CHECKING USER ACCESS")
    # Restart the ttl cron
    access_ttl_cron()

    {:noreply, state}
  end

  # Remove the pending request - sepearate functon so we can check in different intervals
  def handle_info(:request_ttl_job, state) do
    {_, data} = read_file()

    # Check which device has a TTL - The ttl for the request
    # Here we remove the device from access to internet if they had a ttl
    # remove from the file

    IO.inspect("CHECKING USER PENDING REQUESTS")

    # Restart the ttl cron
    request_ttl_cron()

    {:noreply, state}
  end

  # Add entiries to iptables - async as we have the system starting up at this point
  def handle_info(:init_iptables, state) do
    # Read from the blacklist file
    {_, data} = read_file()

    # Loop over the data
    Enum.each(data, fn _policy ->
      # TODO: add the devices that has access persisted to have access
      IO.inspect("INIT THE DATA IN THE WHITELIST TO THE FIREWALL")
    end)

    {:noreply, state}
  end

  # The job that will start interval sync
  def access_ttl_cron() do
    :timer.send_after(@access_ttl_interval, :access_ttl_job)
  end

  def request_ttl_cron() do
    :timer.send_after(@pending_ttl_interval, :request_ttl_job)
  end

  # we fetch the user blacklist file data
  def fetch_whitelist(offset, limit) do
    if Application.get_env(:sentinel, :mock_data, false) do
      Sentinel.Servers.FakeData.Whitelist.get_data()
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
        Sentinel.Servers.FakeData.Whitelist.get_data() |> length
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
          {_output, exit_code} = Iptables.has_user_entry?(policy["ip"], policy["mac"])
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
        Iptables.add_user_entry(policy["ip"], policy["mac"])
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
        Iptables.remove_user_entry(policy["ip"], policy["mac"])
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

  def get_whitelist_page(offset, limit),
    do: GenServer.call(__MODULE__, {:get_whitelist_page, offset, limit})

  def add_device_access(%{hostname: _hostname, ip: _ip, mac: _mac, ttl: _ttl_, status: _status} = data),
    do:
      GenServer.call(
        __MODULE__,
        {:add_device_access, data}
      )

  def remove_device_access(mac),
    do: GenServer.call(__MODULE__, {:remove_device_access, %{ mac: mac }})


  @doc """
  Check if the Blacklist file exists
  """
  def file_exists?(), do: path() |> File.exists?()

  # Path helper
  def path(), do: "./" <> config_fs(:root) <> config_fs(:whitelist)

  # Config helper
  defp config_fs(), do: Application.get_env(:sentinel, :fs)
  defp config_fs(key), do: config_fs()[key]
end
