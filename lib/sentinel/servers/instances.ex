defmodule Sentinel.Servers.Instances do
  @moduledoc """
  Manage the instances (references of devices on the network that are hosting applications)
  """
  use GenServer
  require Logger

  @interval 10_000

  @broadcast_topic_main "component:instances"
  @broadcast_topic "component:details"
  @component_desktop_id "sidebar_details_desktop"
  @component_mobile_id "sidebar_details_mobile"
  @component_module SentinelWeb.Live.Components.Sidebar.Details

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init instance persistence
  """
  def init(_) do
    # We need to make sure we create the file that we willwrite the data to
    if not file_exists?(), do: create_file()

    # The job that will be responsible for updating current instance state
    send(self(), :sync)

    {:ok, %{}}
  end

  #
  # Get instance details
  #
  def handle_cast({:get_instance, id}, state) do
    instances = fetch_nodes()

    if !Enum.empty?(instances) do
      # Why do we need to check the atom vs string map key here??
      instance = Enum.filter(instances, fn instance -> instance.id === id or instance["id"] === id end) |> Enum.at(0)

      # here we need to send off the detail to the sidebar
      # Broadcast the new data structure for the sidebar component - desktop
      Phoenix.PubSub.broadcast(Sentinel.PubSub, @broadcast_topic, %{
        id: @component_desktop_id,
        module: @component_module,
        data: instance
      })

      # Broadcast the new data structure for the sidebar component - mobile
      Phoenix.PubSub.broadcast(Sentinel.PubSub, @broadcast_topic, %{
        id: @component_mobile_id,
        module: @component_module,
        data: instance
      })
    end

    {:noreply, state}
  end

  #
  # Add instance to be persisted
  #
  def handle_cast({:add_instance, instance}, state) do
    instances =
      case read_file() do
        {:ok, list} when is_list(list) -> list
        _ -> []
      end

    # We make sure we dont add if there already is
    exists = Enum.find(instances, fn item -> item["ip"] === "localhost" end)

    u_nodes =
      if is_nil(exists) do
        instances ++ [Map.put(instance, "id", DateTime.utc_now() |> DateTime.to_unix() |> to_string)]
      else
        instances
      end

    update_state =
      case File.write(path(), Jason.encode!(u_nodes)) do
        :ok ->
          Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{
            type: :info,
            message: "Node added successfully"
          })

          # Broadcast to notification server
          Sentinel.Servers.Notification.trigger(
            {:info, "Node added successfully"}
          )

          # Update the dashboard view instances
          broadcast_nodes()

          # updated state
          Map.put(state, :instances, u_nodes)

        {:error, err} ->
          Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{
            type: :error,
            message: "Failed to add instance: #{inspect(err)}"
          })

          # Broadcast to notification server
          Sentinel.Servers.Notification.trigger(
            {:critical, "Failed to add instance"}
          )

          state
      end

    # Broadcast to component will happen when a sync happens, we dont need to do this
    {:noreply, update_state}
  end

  # Remove a instance to be tracked
  def handle_cast({:remove_instance, id}, state) do
    {_, data} = read_file()

    # we need to reject the specific id
    updated_nodes = Enum.reject(data, fn instance -> instance["id"] === id end)

    # Remove to the file
    update_state =
      case File.write(path(), Jason.encode!(updated_nodes)) do
        :ok ->
          Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{
            type: :info,
            message: "Node removed successfully"
          })

          # Update the dashboard view instances
          broadcast_nodes()

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
          Sentinel.Servers.Notification.trigger(
            {:info, "Node removed successfully"}
          )

          # updated state
          Map.put(state, :instances, updated_nodes)

        {:error, err} ->
          Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{
            type: :error,
            message: "Failed to remove instance: #{inspect(err)}"
          })

          # Broadcast to notification server
          Sentinel.Servers.Notification.trigger(
            {:info, "Failed to removed instance"}
          )

          state
      end

    # Update the state

    # Broadcast to component will happen when a sync happens, we dont need to do this
    {:noreply, update_state}
  end

  # Get the data and restart sync
  # NOTE: THIS WOULD BE BETTER OFF WITH DYNAMIC SUPERVISOR FOR EACH SERVICE
  def handle_info(:sync, state) do
    # send out the list of instances
    instances = broadcast_nodes()

    # restart the checking of instances and their health
    sync_nodes()
    {:noreply, Map.put(state, :instances, instances)}
  end

  # The job that will start interval sync
  defp sync_nodes() do
    :timer.send_after(@interval, :sync)
  end

  #
  # The instances inside the persisted file that was created
  #
  def fetch_nodes() do
    {_status, data} = read_file()

    instances =
      if data == "",
        do: [],
        else: data

    Enum.map(instances, fn instance ->
      # we get data
      %{
        id: instance["id"],
        name: instance["name"],
        ip: instance["ip"],
        icon: instance["icon"],
        port: instance["port"],
        status: port_busy?(instance["ip"], instance["port"]),
        tunnel: Sentinel.Servers.Cloudflare.get_tunnel_data(instance["ip"], instance["port"])
        # add tunnel data here
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
  # Broadcast the instances to the relevant component
  #
  defp broadcast_nodes() do
    instances = fetch_nodes()

    # # Broadcast to the live view (or parent) so it can update the Devices component.
    # # Use an id that matches the one used in your live_component render.
    Phoenix.PubSub.broadcast(Sentinel.PubSub, @broadcast_topic_main, %{
      id: "instances",
      module: SentinelWeb.Live.Components.Instances,
      data: instances
    })

    instances
  end

  @doc """
  Create the Node file.
  """
  def create_file() do
    case File.write(path(), Jason.encode!([])) do
      :ok -> {:ok, "Instances file created"}
      {:error, reason} -> {:error, "Failed to create Instances file: #{inspect(reason)}"}
    end
  end

  @doc """
  Read the Node file
  """
  def read_file() do
    case path() |> File.read() do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, data} ->
            {:ok, data}

          {:error, err} ->
            {:error, "Failed to decode Node file: #{inspect(err)}"}
        end

      {:error, reason} ->
        {:error, "There was a problem reading the file: #{inspect(reason)}"}
    end
  end

  def get_instance(id), do: GenServer.cast(__MODULE__, {:get_instance, id})
  def add_instance(instance), do: GenServer.cast(__MODULE__, {:add_instance, instance})
  def remove_instance(instance), do: GenServer.cast(__MODULE__, {:remove_instance, instance})

  @doc """
  Check if the Node file exists.
  """
  def file_exists?(), do: File.exists?(path())

  def path(), do: "./" <> config_fs(:root) <> config_fs(:instances)
  defp config_fs(), do: Application.get_env(:sentinel, :fs)
  defp config_fs(key), do: config_fs()[key]
end
