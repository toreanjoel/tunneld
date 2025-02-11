defmodule Sentinel.Servers.Services do
  @moduledoc """
  Manage running services
  """
  use GenServer
  require Logger

  @services [:dnsmasq, :dhcpcd, :hostapd, :'dnscrypt-proxy']
  @service_log_limit "80"
  @interval 30_000
  @topic "sentinel:services"

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init services
  """
  def init(_) do
    send(self(), :sync)
    {:ok, %{}}
  end

  @doc """
  Get all of the information around services
  Note: for now the user needs to get everything
  """
  def handle_call(:get_state, _from, state) do
    # TODO: Get the services
    {:reply, {:ok, state}, state}
  end

  @doc """
  Get the system logs for the services that we can render
  """
  def handle_call({:get_logs, service}, _from, state) do
    service_atom = service |> String.to_atom

    if service_atom in @services do
      # TODO: Get the services
      data = case System.cmd("journalctl", ["-u", service |> to_string, "-n", @service_log_limit, "--no-pager"]) do
        {resp, 0} -> resp
        _ -> "There was an error fetching the service logs"
      end

      # Concert to a list
      data = data |> String.split("\n") |> Enum.filter(fn item -> item !== "" end) |> Enum.reverse()

      {:reply, {:ok, data}, state}
    else
      {:reply, {:error, "Make sure the service selected is allowed"}, state}
    end
  end

  # Restart a service
  # Note: that we wont get a response so we need to manage this
  def handle_cast({:restart_service, service}, state) do
    Task.start(fn ->
      System.cmd("systemctl", ["restart", service |> to_string])
    end)
    {:noreply, state}
  end

  # get the data and restart sync
  def handle_info(:sync, state) do
    # TODO: Here we get the logs and also any specific information we want to broadcast i.e state
    result = Enum.reduce(@services, %{}, fn service, acc ->
      Map.put(acc, service, check_service(service))
    end)

    Phoenix.PubSub.broadcast(Sentinel.PubSub, @topic, {:services_info, result})

    # Refetch
    sync_services()

    {:noreply, Map.merge(state, result)}
  end

  # The job that will start interval sync
  defp sync_services() do
    :timer.send_after(@interval, :sync)
  end

  # check if services is running
  defp check_service(service) do
    try do
      {output, _exit_code} = System.cmd("systemctl", ["is-active", service |> to_string])
      is_active = String.trim(output) == "active"

      # Attempt to start the service
      if !is_active do
        Task.start(fn ->
          System.cmd("systemctl", ["start", service |> to_string])
        end)
      end

      is_active
    rescue
      _ ->
        # fallback for when the command fails
        false
    end
  end

  # Get entire state details for the services
  def get_state(), do: GenServer.call(__MODULE__, :get_state)
  def get_logs(service), do: GenServer.call(__MODULE__, {:get_logs, service})
  def restart_service(service), do: GenServer.cast(__MODULE__, {:restart_service, service})

end
