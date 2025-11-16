defmodule Tunneld.Servers.Blocklist do
  @moduledoc false
  use GenServer
  require Logger

  @pubsub Tunneld.PubSub
  @topic_notif "notifications"
  @system_blacklist_path "/blacklists/dnsmasq-system.blacklist"

  @broadcast_topic "component:details"
  @component_desktop_id "sidebar_details"
  @component_module TunneldWeb.Live.Components.Sidebar.Details

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_cast(:details, state) do
    send(self(), :broadcast_details)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:fetch_details, state) do
    try do
      conf =
        Application.get_env(:tunneld, :config_dir)[:path] <> @system_blacklist_path

      File.stream!(conf)
      |> Enum.take(11)
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&String.starts_with?(&1, "#"))
      |> Enum.map(fn "#" <> rest ->
        [key, value] = String.split(rest, ":", parts: 2)
        {String.trim(key), String.trim(value)}
      end)
      |> Enum.into(%{})

      IO.inspect(conf, label: "CONF")
      Phoenix.PubSub.broadcast(Tunneld.PubSub, @broadcast_topic, %{
        id: @component_desktop_id,
        module: @component_module,
        # We send the details of the current file on disk here
        data: conf
      })
    catch
      e ->
        Logger.error("There was a problem processing the file: #{inspect(e)}")
        notify(:critical, "There was a problem processing the file")
    end

    {:noreply, state}
  end

  # funciton to update using the script
  # notify(:info, "Endpoint to network set")

  # function to get the current deatils we have at the moment

  defp notify(type, message) do
    Phoenix.PubSub.broadcast(@pubsub, @topic_notif, %{type: type, message: message})
  end

  # APIs to the server to request and update the deatils
  def details(), do: GenServer.cast(__MODULE__, :fetch_details)
  def remove_access(id), do: GenServer.call(__MODULE__, {:remove_access, id}, 30_000)
end
