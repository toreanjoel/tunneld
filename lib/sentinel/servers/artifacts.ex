defmodule Sentinel.Servers.Artifacts do
  @moduledoc """
  Manage the artifacts (to a running application hosted on some device on the network)
  """
  use GenServer
  require Logger

  @interval 10_000

  @broadcast_topic_main "component:artifacts"
  @broadcast_topic "component:details"
  @component_desktop_id "sidebar_details_desktop"
  @component_mobile_id "sidebar_details_mobile"
  @component_module SentinelWeb.Live.Components.Sidebar.Details

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init artifact persistence
  """
  def init(_) do
    # We need to make sure we create the file that we willwrite the data to
    if not file_exists?(), do: create_file()

    # The job that will be responsible for updating current artifact state
    send(self(), :sync)

    {:ok, %{}}
  end

  #
  # Get artifacts by type
  #
  def handle_call(:get_enabled_artifacts, _from, state) do
    artifacts = fetch_artifacts()
    data = artifacts |> Enum.filter(fn a -> a.sentinet["enabled"] end)
    {:reply, {:ok, data}, state}
  end

  #
  # Add artifact to be persisted
  #
  def handle_call({:add_artifact, artifact}, _from, state) do
    artifacts =
      case read_file() do
        {:ok, list} when is_list(list) -> list
        _ -> []
      end

    # We make sure we dont add if there already is - we check ports as this is a running instance
    exists =
      Enum.find(artifacts, fn item ->
        item["port"] === artifact["port"] and item["ip"] === artifact["ip"]
      end)

    updated_state =
      if is_nil(exists) do
        new_artifact =
          artifact
          |> Map.merge(%{
            "id" => DateTime.utc_now() |> DateTime.to_unix() |> to_string,
            "sentinet" => %{}
          })

        # Add a new list item to be updated
        # TODO: not ideal with many
        u_nodes = artifacts ++ [new_artifact]

        case File.write(path(), Jason.encode!(u_nodes)) do
          :ok ->
            Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{
              type: :info,
              message: "artifact added successfully"
            })

            # Broadcast to notification server
            Sentinel.Servers.Notification.trigger({:info, "artifact added successfully"})

            # Update the dashboard view artifacts
            broadcast_artifacts()

            # updated state
            Map.put(state, :artifacts, u_nodes)

          {:error, err} ->
            Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{
              type: :error,
              message: "Failed to add artifact: #{inspect(err)}"
            })

            # Broadcast to notification server
            Sentinel.Servers.Notification.trigger({:critical, "Failed to add artifact"})

            state
        end
      else
        Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{
          type: :error,
          message: "Only one artifact instance allowed at a time"
        })

        state
      end

    # Broadcast to component will happen when a sync happens, we dont need to do this
    {:reply, updated_state, updated_state}
  end

  #
  # Get artifact details
  # We need to merge this with the client side fetch to a helper function
  #
  def handle_call({:get_artifact_details, id}, _from, state) do
    artifacts = fetch_artifacts()

    # We get the general details of the artifact
    artifact =
      if !Enum.empty?(artifacts) do
        Enum.filter(artifacts, fn artifact -> artifact.id === id or artifact["id"] === id end)
        |> Enum.at(0)
      else
        %{}
      end

    {:reply, {:ok, artifact}, state}
  end

  #
  # Get artifact details - send to the client to render
  #
  def handle_cast({:get_artifact, id}, state) do
    artifacts = fetch_artifacts()

    if !Enum.empty?(artifacts) do
      # Why do we need to check the atom vs string map key here??
      artifact =
        Enum.filter(artifacts, fn artifact -> artifact.id === id or artifact["id"] === id end)
        |> Enum.at(0)

      # here we need to send off the detail to the sidebar
      # Broadcast the new data structure for the sidebar component - desktop
      Phoenix.PubSub.broadcast(Sentinel.PubSub, @broadcast_topic, %{
        id: @component_desktop_id,
        module: @component_module,
        data: artifact
      })

      # Broadcast the new data structure for the sidebar component - mobile
      Phoenix.PubSub.broadcast(Sentinel.PubSub, @broadcast_topic, %{
        id: @component_mobile_id,
        module: @component_module,
        data: artifact
      })
    end

    {:noreply, state}
  end

  #
  # Update artifact settings by key type
  #
  def handle_cast({:update_artifact, type, data}, state) do
    artifacts = fetch_artifacts()

    if !Enum.empty?(artifacts) do
      artifact =
        Enum.filter(artifacts, fn artifact ->
          artifact.id === data["id"] or artifact["id"] === data["id"]
        end)
        |> Enum.at(0)

      # Assume the settings is not set, always override and replace
      updated_artifacts =
        case type do
          :sentinet ->
            Enum.map(artifacts, fn a ->
              if a.id === artifact.id do
                Map.put(a, :sentinet, data)
              else
                # We need to return the others
                a
              end
            end)

          _ ->
            Logger.info("Tried to set settings with an unhandled type")
            Sentinel.Servers.Notification.trigger({:critical, "Update not supported"})
        end

      case File.write(path(), Jason.encode!(updated_artifacts)) do
        :ok ->
          Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{
            type: :info,
            message: "Artifact updated successfully"
          })

          # Broadcast to notification server
          Sentinel.Servers.Notification.trigger({:info, "Artifact updated successfully"})

          # Update the dashboard view artifacts
          broadcast_artifacts()

          # Send the current artifact back
          # NOTE: Find a better way to structure this data
          Phoenix.PubSub.broadcast(Sentinel.PubSub, "show_details", {
            :show_details,
            # We get this from the input
            %{"id" => data["id"], "type" => "artifact"}
          })

        {:error, err} ->
          Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{
            type: :error,
            message: "Failed to update artifact: #{inspect(err)}"
          })

          # Broadcast to notification server
          Sentinel.Servers.Notification.trigger({:critical, "Failed to add artifact"})
      end
    end

    {:noreply, state}
  end

  # Remove a artifact to be tracked
  def handle_cast({:remove_artifact, id}, state) do
    {_, data} = read_file()

    # we need to reject the specific id
    updated_nodes = Enum.reject(data, fn artifact -> artifact["id"] === id end)

    # Remove to the file
    update_state =
      case File.write(path(), Jason.encode!(updated_nodes)) do
        :ok ->
          Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{
            type: :info,
            message: "artifact removed successfully"
          })

          # Update the dashboard view artifacts
          broadcast_artifacts()

          # here we need to send off the detail to the sidebar
          # Broadcast the new data structure for the sidebar component - desktop
          Phoenix.PubSub.broadcast(Sentinel.PubSub, @broadcast_topic, %{
            id: @component_desktop_id,
            module: @component_module,
            data: %{}
          })

          # Broadcast the new data structure for the sidebar component - mobile
          Phoenix.PubSub.broadcast(Sentinel.PubSub, @broadcast_topic, %{
            id: @component_mobile_id,
            module: @component_module,
            data: %{}
          })

          # Broadcast to notification server
          Sentinel.Servers.Notification.trigger({:info, "artifact removed successfully"})

          # updated state
          Map.put(state, :artifacts, updated_nodes)

        {:error, err} ->
          Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{
            type: :error,
            message: "Failed to remove artifact: #{inspect(err)}"
          })

          # Broadcast to notification server
          Sentinel.Servers.Notification.trigger({:info, "Failed to removed artifact"})

          state
      end

    # Update the state

    # Broadcast to component will happen when a sync happens, we dont need to do this
    {:noreply, update_state}
  end

  # Get the data and restart sync
  # NOTE: THIS WOULD BE BETTER OFF WITH DYNAMIC SUPERVISOR FOR EACH SERVICE
  def handle_info(:sync, state) do
    # send out the list of artifacts
    artifacts = broadcast_artifacts()

    # restart the checking of artifacts and their health
    sync_nodes()
    {:noreply, Map.put(state, :artifacts, artifacts)}
  end

  # The job that will start interval sync
  defp sync_nodes() do
    :timer.send_after(@interval, :sync)
  end

  #
  # The artifacts inside the persisted file that was created
  #
  def fetch_artifacts() do
    {_status, data} = read_file()

    artifacts =
      if data == "",
        do: [],
        else: data

    Enum.map(artifacts, fn artifact ->
      # we get data
      %{
        id: artifact["id"],
        name: artifact["name"],
        ip: artifact["ip"],
        description: artifact["description"],
        port: artifact["port"],
        status: port_busy?(artifact["ip"], artifact["port"]),
        tunnel: Sentinel.Servers.Cloudflare.get_tunnel_data(artifact["ip"], artifact["port"]),
        sentinet: artifact["sentinet"]
      }
    end)
  end

  #
  # Ping services and return updated with status
  #
  def port_busy?(ip, port) do
    case :gen_tcp.connect(
           String.to_charlist(ip),
           port |> String.to_integer(),
           [:binary, active: false],
           2000
         ) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _reason} ->
        false
    end
  end

  #
  # Broadcast the artifacts to the relevant component
  #
  defp broadcast_artifacts() do
    artifacts = fetch_artifacts()

    # # Broadcast to the live view (or parent) so it can update the Devices component.
    # # Use an id that matches the one used in your live_component render.
    Phoenix.PubSub.broadcast(Sentinel.PubSub, @broadcast_topic_main, %{
      id: "artifacts",
      module: SentinelWeb.Live.Components.Artifacts,
      data: artifacts
    })

    artifacts
  end

  @doc """
  Create the artifact file.
  """
  def create_file() do
    case File.write(path(), Jason.encode!([])) do
      :ok -> {:ok, "Artifacts file created"}
      {:error, reason} -> {:error, "Failed to create Artifacts file: #{inspect(reason)}"}
    end
  end

  @doc """
  Read the artifact file
  """
  def read_file() do
    case path() |> File.read() do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, data} ->
            {:ok, data}

          {:error, err} ->
            {:error, "Failed to decode artifact file: #{inspect(err)}"}
        end

      {:error, reason} ->
        {:error, "There was a problem reading the file: #{inspect(reason)}"}
    end
  end

  def get_enabled_artifacts(), do: GenServer.call(__MODULE__, :get_enabled_artifacts, 25_000)
  def get_artifact(id), do: GenServer.cast(__MODULE__, {:get_artifact, id})
  def get_artifact_details(id), do: GenServer.call(__MODULE__, {:get_artifact_details, id})
  def add_artifact(artifact), do: GenServer.call(__MODULE__, {:add_artifact, artifact}, 25_000)
  def remove_artifact(artifact), do: GenServer.cast(__MODULE__, {:remove_artifact, artifact})
  # Update specific settings
  # TODO: This needs to change to be more generic
  def update_artifact(data, :sentinet),
    do: GenServer.cast(__MODULE__, {:update_artifact, :sentinet, data})

  @doc """
  Check if the artifact file exists.
  """
  def file_exists?(), do: File.exists?(path())

  def path(), do: "./" <> config_fs(:root) <> config_fs(:artifacts)
  defp config_fs(), do: Application.get_env(:sentinel, :fs)
  defp config_fs(key), do: config_fs()[key]
end
