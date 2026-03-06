defmodule Tunneld.Servers.Updater do
  @moduledoc """
  Periodically checks for new Tunneld releases by fetching version metadata
  from the installer repository on GitHub.

  Compares the remote version against `Application.get_env(:tunneld, :version)`
  and broadcasts update availability to the Welcome dashboard component.
  Checks every `@interval` milliseconds (default: 5 minutes).
  """
  use GenServer
  require Logger

  @interval 300_000
  @metadata_url "https://raw.githubusercontent.com/toreanjoel/tunneld-installer/refs/heads/main/releases/metadata.json"

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Get the current update status from the state
  """
  def get_status() do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Init Updater
  """
  @impl true
  def init(_) do
    send(self(), :check_updates)

    {:ok, %{is_latest: false, new_version: nil}}
  end

  # get the data and restart sync
  @impl true
  def handle_info(:check_updates, state) do
    {status, data} = fetch_latest()

    new_state =
      if status == :ok do
        c_v = Application.get_env(:tunneld, :version)
        r_m = Map.get(data, "version")
        update_available = r_m && Version.compare(c_v, r_m) == :lt

        # Only broadcast if the status has changed
        if update_available != state.is_latest or r_m != state.new_version do
          notify(update_available, r_m)
        end

        %{is_latest: update_available, new_version: r_m}
      else
        state
      end

    check_version()
    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    {:reply, state, state}
  end

  # The job that will start interval sync
  defp check_version() do
    :timer.send_after(@interval, :check_updates)
  end

  # Get the latest from the repo
  defp fetch_latest() do
    case HTTPoison.get(@metadata_url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      _ ->
        {:error, %{}}
    end
  end

  # Send notification to the dashboard
  defp notify(update_available, new_version) do
    Phoenix.PubSub.broadcast(Tunneld.PubSub, "component:welcome", %{
      id: "welcome",
      module: TunneldWeb.Live.Components.Welcome,
      data: %{
        is_latest: update_available,
        new_version: new_version
      }
    })
  end
end
