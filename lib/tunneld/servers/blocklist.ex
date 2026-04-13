defmodule Tunneld.Servers.Blocklist do
  @moduledoc """
  Manages the DNS sinkhole blocklist (ad/tracker/malware domain blocking).

  Reads metadata (title, version, entry count, last modified) from the header
  comments of the dnsmasq-format blocklist file. Supports triggering an update
  via an external shell script that re-downloads the blocklist.

  This GenServer holds no persistent state — metadata is loaded on demand
  and broadcast to the sidebar details component.
  """
  use GenServer
  require Logger

  @pubsub Tunneld.PubSub
  @topic_notif "notifications"

  @system_blacklist "/blacklists/dnsmasq-system.blacklist"
  @update_script "/update_blacklist.sh"
  defp mock?, do: Application.get_env(:tunneld, :mock_data, false)

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
    case load_blocklist_meta() do
      {:ok, meta} ->
        broadcast_meta(meta)

      {:error, reason} ->
        Logger.error("There was a problem processing the file: #{inspect(reason)}")
        notify(:error, "There was a problem processing the file")
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast(:update, state) do
    spawn(fn ->
      case update_blocklist() do
        :ok ->
          case load_blocklist_meta(updated: true) do
            {:ok, meta} ->
              broadcast_meta(meta)
              notify(:info, "Blacklist was updated")

            {:error, reason} ->
              Logger.error(
                "There was a problem processing the file after update: #{inspect(reason)}"
              )

              notify(:error, "There was a problem processing the file after update")
          end

        {:error, reason} ->
          Logger.error("There was a problem running the update script: #{inspect(reason)}")
          notify(:error, "There was a problem updating the blacklist")
      end
    end)

    {:noreply, state}
  end

  defp update_blocklist do
    if mock?() do
      :ok
    else
      try do
        case Application.get_env(:tunneld, :build_dir) do
          [path: build_dir] ->
            script = build_dir <> @update_script

            case System.cmd(script, []) do
              {_output, 0} ->
                :ok

              {output, exit_code} ->
                {:error, {:non_zero_exit, exit_code, output}}
            end

          nil ->
            {:error, :missing_build_dir}
        end
      rescue
        e -> {:error, e}
      end
    end
  end

  defp load_blocklist_meta(opts \\ []) do
    mock? = mock?()
    updated? = Keyword.get(opts, :updated, false)

    try do
      meta =
        if mock? do
          data = Tunneld.Servers.FakeData.blocklist()

          if updated? do
            Map.put(data, "title", "UPDATED")
          else
            data
          end
        else
          conf = Application.get_env(:tunneld, :config_dir)[:path] <> @system_blacklist

          conf
          |> File.stream!()
          |> Enum.take(11)
          |> Enum.map(&String.trim/1)
          |> Enum.filter(&String.starts_with?(&1, "#"))
          |> Enum.map(fn "#" <> rest ->
            [key, value] = String.split(rest, ":", parts: 2)

            {
              key |> String.downcase() |> String.trim(),
              value |> String.trim()
            }
          end)
          |> Enum.into(%{})
        end

      {:ok, meta}
    rescue
      e -> {:error, e}
    end
  end

  defp broadcast_meta(meta) do
    Phoenix.PubSub.broadcast(@pubsub, @broadcast_topic, %{
      id: @component_desktop_id,
      module: @component_module,
      data: meta
    })
  end

  defp notify(type, message) do
    Phoenix.PubSub.broadcast(@pubsub, @topic_notif, %{type: type, message: message})
  end

  def get_details(), do: GenServer.cast(__MODULE__, :details)
  def update(), do: GenServer.cast(__MODULE__, :update)
end
