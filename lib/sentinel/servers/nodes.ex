defmodule Sentinel.Servers.Nodes do
  @moduledoc """
  Manage the nodes (references of devices on the network that are hosting applications)
  """
  use GenServer
  require Logger

  @interval 10_000

  @broadcast_topic_main "component:nodes"
  @broadcast_topic "component:details"
  @component_desktop_id "sidebar_details_desktop"
  @component_mobile_id "sidebar_details_mobile"
  @component_module SentinelWeb.Live.Components.Sidebar.Details

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init node persistence
  """
  def init(_) do
    # We need to make sure we create the file that we willwrite the data to
    if not file_exists?(), do: create_file()

    # The job that will be responsible for updating current node state
    send(self(), :sync)

    {:ok, %{}}
  end

  #
  # Get node details
  #
  def handle_cast({:get_node, id}, state) do
    nodes = fetch_nodes()

    if !Enum.empty?(nodes) do
      # Why do we need to check the atom vs string map key here??
      node = Enum.filter(nodes, fn node -> node.id === id or node["id"] === id end) |> Enum.at(0)

      # here we need to send off the detail to the sidebar
      # Broadcast the new data structure for the sidebar component - desktop
      Phoenix.PubSub.broadcast(Sentinel.PubSub, @broadcast_topic, %{
        id: @component_desktop_id,
        module: @component_module,
        data: node
      })

      # Broadcast the new data structure for the sidebar component - mobile
      Phoenix.PubSub.broadcast(Sentinel.PubSub, @broadcast_topic, %{
        id: @component_mobile_id,
        module: @component_module,
        data: node
      })
    end

    {:noreply, state}
  end

  #
  # Add node to be persisted
  #
  def handle_cast({:add_node, node}, state) do
    nodes =
      case read_file() do
        {:ok, list} when is_list(list) -> list
        _ -> []
      end

    updated_nodes = nodes ++ [Map.put(node, "id", DateTime.utc_now() |> DateTime.to_unix() |> to_string)]

    update_state =
      case File.write(path(), Jason.encode!(updated_nodes)) do
        :ok ->
          Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{
            type: :info,
            message: "Node added successfully"
          })

          # Update the dashboard view nodes
          broadcast_nodes()

          # updated state
          Map.put(state, :nodes, updated_nodes)

        {:error, err} ->
          Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{
            type: :error,
            message: "Failed to add node: #{inspect(err)}"
          })

          {:error, "Failed to add node: #{inspect(err)}"}

          state
      end

    # Broadcast to component will happen when a sync happens, we dont need to do this
    {:noreply, update_state}
  end

  # Remove a node to be tracked
  def handle_cast({:remove_node, id}, state) do
    {_, data} = read_file()

    # we need to reject the specific id
    updated_nodes = Enum.reject(data, fn node -> node["id"] === id end)

    # Remove to the file
    # TODO: delete from cloudflare as well
    update_state =
      case File.write(path(), Jason.encode!(updated_nodes)) do
        :ok ->
          Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{
            type: :info,
            message: "Node removed successfully"
          })

          # Update the dashboard view nodes
          broadcast_nodes()

          # here we need to send off the detail to the sidebar
          # Broadcast the new data structure for the sidebar component - desktop
          Phoenix.PubSub.broadcast(Sentinel.PubSub, @broadcast_topic, %{
            id: @component_desktop_id,
            module: @component_module,
            data: %{},
          })

          # Broadcast the new data structure for the sidebar component - mobile
          Phoenix.PubSub.broadcast(Sentinel.PubSub, @broadcast_topic, %{
            id: @component_mobile_id,
            module: @component_module,
            data: %{},
          })

          # updated state
          Map.put(state, :nodes, updated_nodes)

        {:error, err} ->
          Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{
            type: :error,
            message: "Failed to add node: #{inspect(err)}"
          })

          {:error, "Failed to add node: #{inspect(err)}"}

          state
      end

    # Update the state

    # Broadcast to component will happen when a sync happens, we dont need to do this
    {:noreply, update_state}
  end

  # Get the data and restart sync
  # NOTE: THIS WOULD BE BETTER OFF WITH DYNAMIC SUPERVISOR FOR EACH SERVICE
  def handle_info(:sync, state) do
    # send out the list of nodes
    nodes = broadcast_nodes()

    # restart the checking of nodes and their health
    sync_nodes()
    {:noreply, Map.put(state, :nodes, nodes)}
  end

  # The job that will start interval sync
  defp sync_nodes() do
    :timer.send_after(@interval, :sync)
  end

  #
  # The nodes inside the persisted file that was created
  #
  def fetch_nodes() do
    {_status, data} = read_file()

    nodes =
      if data == "",
        do: [],
        else: data

    Enum.map(nodes, fn node ->
      # we get data
      %{
        id: node["id"],
        name: node["name"],
        ip: node["ip"],
        icon: node["icon"],
        port: node["port"],
        status: port_busy?(node["ip"], node["port"]),
        tunnel: Sentinel.Servers.Cloudflare.get_tunnel_data(node["ip"], node["port"])
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
  # Broadcast the nodes to the relevant component
  #
  defp broadcast_nodes() do
    nodes = fetch_nodes()

    # # Broadcast to the live view (or parent) so it can update the Devices component.
    # # Use an id that matches the one used in your live_component render.
    Phoenix.PubSub.broadcast(Sentinel.PubSub, @broadcast_topic_main, %{
      id: "nodes",
      module: SentinelWeb.Live.Components.Nodes,
      data: nodes
    })

    nodes
  end

  @doc """
  Create the Node file.
  """
  def create_file() do
    case File.write(path(), Jason.encode!([])) do
      :ok -> {:ok, "Nodes file created"}
      {:error, reason} -> {:error, "Failed to create Nodes file: #{inspect(reason)}"}
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

  def get_node(id), do: GenServer.cast(__MODULE__, {:get_node, id})
  def add_node(node), do: GenServer.cast(__MODULE__, {:add_node, node})
  def remove_node(node), do: GenServer.cast(__MODULE__, {:remove_node, node})

  @doc """
  Check if the Node file exists.
  """
  def file_exists?(), do: File.exists?(path())

  def path(), do: "./" <> config_fs(:root) <> config_fs(:nodes)
  defp config_fs(), do: Application.get_env(:sentinel, :fs)
  defp config_fs(key), do: config_fs()[key]
end
