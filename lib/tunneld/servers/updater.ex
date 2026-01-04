defmodule Tunneld.Servers.Updater do
  @moduledoc """
  Manage updates for the system
  """
  use GenServer
  require Logger

  @pubsub Tunneld.PubSub
  @topic_notif "notifications"
  @interval 300_000
  @metadata_url "https://raw.githubusercontent.com/toreanjoel/tunneld-installer/refs/heads/main/releases/metadata.json"

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init Updater
  """
  def init(_) do
    send(self(), :check_updates)

    {:ok,
     %{
       init_call: true
     }}
  end

  # get the data and restart sync
  @impl false
  def handle_info(:check_updates, state) do
    # check if the call is the first one
    if not Map.get(state, :init_call) do
      # Get the latest data from remote
      {status, data} = fetch_latest()

      if status == :ok do
        # Do check with local version - fallback if needed
        c_v = Application.get_env(:tunneld, :version)
        r_m = Map.get(data, "version")

        if c_v < r_m do
          notify(true, r_m)
        end
      end
    end

    check_version()
    # We make sure that we set the inital
    {:noreply, Map.put(state, :init_call, false)}
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
  defp notify(notify, new_version) do
    if not is_nil(new_version) do
      Phoenix.PubSub.broadcast(Tunneld.PubSub, "component:welcome", %{
        id: "welcome",
        module: TunneldWeb.Live.Components.Welcome,
        data: %{
          is_latest: notify,
          new_version: new_version
        }
      })
    end
  end
end
