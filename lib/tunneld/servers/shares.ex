defmodule Tunneld.Servers.Shares do
  @moduledoc """
  Manage the shares (to a running application hosted on some device on the network)
  """
  use GenServer
  require Logger

  @interval 10_000

  @broadcast_topic_main "component:shares"
  @broadcast_topic "component:details"
  @component_desktop_id "sidebar_details"
  @component_module TunneldWeb.Live.Components.Sidebar.Details

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init share persistence
  """
  def init(_) do
    # We need to make sure we create the file that we willwrite the data to
    if not file_exists?(), do: create_file()

    # The job that will be responsible for updating current share state
    send(self(), :sync)

    {:ok, %{}}
  end

  #
  # Get shares by type
  #
  def handle_call(:get_enabled_artifacts, _from, state) do
    shares = fetch_artifacts()
    data = shares |> Enum.filter(fn a -> a.tunneld["enabled"] end)
    {:reply, {:ok, data}, state}
  end

  #
  # Add share to be persisted
  #
  def handle_call({:add_artifact, share}, _from, state) do
    shares =
      case read_file() do
        {:ok, list} when is_list(list) -> list
        _ -> []
      end

    # We make sure we dont add if there already is - we check ports as this is a running instance
    exists =
      Enum.find(shares, fn item ->
        item["port"] === share["port"] and item["ip"] === share["ip"]
      end)

    updated_state =
      if is_nil(exists) do
        new_artifact =
          share
          |> Map.merge(%{
            "id" => DateTime.utc_now() |> DateTime.to_unix() |> to_string,
            "tunneld" => %{}
          })

        # Add a new list item to be updated
        # TODO: not ideal with many
        u_nodes = shares ++ [new_artifact]

        case File.write(path(), Jason.encode!(u_nodes)) do
          :ok ->
            Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
              type: :info,
              message: "share added successfully"
            })

            # Update the dashboard view shares
            broadcast_artifacts()

            # updated state
            Map.put(state, :shares, u_nodes)

          {:error, err} ->
            Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
              type: :error,
              message: "Failed to add share: #{inspect(err)}"
            })

            state
        end
      else
        Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
          type: :error,
          message: "Only one share instance allowed at a time"
        })

        state
      end

    # Broadcast to component will happen when a sync happens, we dont need to do this
    {:reply, updated_state, updated_state}
  end

  #
  # Get share details
  # We need to merge this with the client side fetch to a helper function
  #
  def handle_call({:get_artifact_details, id}, _from, state) do
    shares = fetch_artifacts()

    # We get the general details of the share
    share =
      if !Enum.empty?(shares) do
        Enum.filter(shares, fn share -> share.id === id or share["id"] === id end)
        |> Enum.at(0)
      else
        %{}
      end

    {:reply, {:ok, share}, state}
  end

  #
  # Get share details - send to the client to render
  #
  def handle_cast({:get_artifact, id}, state) do
    shares = fetch_artifacts()

    if !Enum.empty?(shares) do
      # Why do we need to check the atom vs string map key here??
      share =
        Enum.filter(shares, fn share -> share.id === id or share["id"] === id end)
        |> Enum.at(0)

      # here we need to send off the detail to the sidebar
      # Broadcast the new data structure for the sidebar component - desktop
      Phoenix.PubSub.broadcast(Tunneld.PubSub, @broadcast_topic, %{
        id: @component_desktop_id,
        module: @component_module,
        data: share
      })
    end

    {:noreply, state}
  end

  #
  # Update share settings by key type
  #
  def handle_cast({:update_artifact, type, data}, state) do
    shares = fetch_artifacts()

    if !Enum.empty?(shares) do
      share =
        Enum.filter(shares, fn share ->
          share.id === data["id"] or share["id"] === data["id"]
        end)
        |> Enum.at(0)

      # Assume the settings is not set, always override and replace
      updated_artifacts =
        case type do
          :tunneld ->
            Enum.map(shares, fn a ->
              if a.id === share.id do
                Map.put(a, :tunneld, data)
              else
                # We need to return the others
                a
              end
            end)

          _ ->
            Logger.error("Tried to set settings with an unhandled type")
        end

      case File.write(path(), Jason.encode!(updated_artifacts)) do
        :ok ->
          Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
            type: :info,
            message: "Share updated successfully"
          })

          # Update the dashboard view shares
          broadcast_artifacts()

          # Send the current share back
          # NOTE: Find a better way to structure this data
          Phoenix.PubSub.broadcast(Tunneld.PubSub, "show_details", {
            :show_details,
            # We get this from the input
            %{"id" => data["id"], "type" => "share"}
          })

        {:error, err} ->
          Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
            type: :error,
            message: "Failed to update share: #{inspect(err)}"
          })
      end
    end

    {:noreply, state}
  end

  # Remove a share to be tracked
  def handle_cast({:remove_artifact, id}, state) do
    {_, data} = read_file()

    # we need to reject the specific id
    updated_nodes = Enum.reject(data, fn share -> share["id"] === id end)

    # Remove to the file
    update_state =
      case File.write(path(), Jason.encode!(updated_nodes)) do
        :ok ->
          Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
            type: :info,
            message: "share removed successfully"
          })

          # Update the dashboard view shares
          broadcast_artifacts()

          # here we need to send off the detail to the sidebar
          # Broadcast the new data structure for the sidebar component - desktop
          Phoenix.PubSub.broadcast(Tunneld.PubSub, @broadcast_topic, %{
            id: @component_desktop_id,
            module: @component_module,
            data: %{
              id: id
            }
          })

          # updated state
          Map.put(state, :shares, updated_nodes)

        {:error, err} ->
          Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
            type: :error,
            message: "Failed to remove share: #{inspect(err)}"
          })

          state
      end

    # Update the state

    # Broadcast to component will happen when a sync happens, we dont need to do this
    {:noreply, update_state}
  end

  # Get the data and restart sync
  # NOTE: THIS WOULD BE BETTER OFF WITH DYNAMIC SUPERVISOR FOR EACH SERVICE
  def handle_info(:sync, state) do
    # send out the list of shares
    shares = broadcast_artifacts()

    # restart the checking of shares and their health
    sync_nodes()
    {:noreply, Map.put(state, :shares, shares)}
  end

  # The job that will start interval sync
  defp sync_nodes() do
    :timer.send_after(@interval, :sync)
  end

  #
  # The shares inside the persisted file that was created
  #
  def fetch_artifacts() do
    {_status, data} = read_file()

    shares =
      if data == "",
        do: [],
        else: data

    Enum.map(shares, fn share ->
      %{
        id: share["id"],
        name: share["name"],
        ip: share["ip"],
        description: share["description"],
        port: share["port"],
        status: port_busy?(share["ip"], share["port"]),
        tunneld: share["tunneld"]
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
  # Broadcast the shares to the relevant component
  #
  defp broadcast_artifacts() do
    shares = fetch_artifacts()

    # # Broadcast to the live view (or parent) so it can update the Devices component.
    # # Use an id that matches the one used in your live_component render.
    Phoenix.PubSub.broadcast(Tunneld.PubSub, @broadcast_topic_main, %{
      id: "shares",
      module: TunneldWeb.Live.Components.Shares,
      data: shares
    })

    shares
  end

  @doc """
  Create the share file.
  """
  def create_file() do
    case File.write(path(), Jason.encode!([])) do
      :ok -> {:ok, "Shares file created"}
      {:error, reason} -> {:error, "Failed to create Shares file: #{inspect(reason)}"}
    end
  end

  @doc """
  Read the share file
  """
  def read_file() do
    case path() |> File.read() do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, data} ->
            {:ok, data}

          {:error, err} ->
            {:error, "Failed to decode share file: #{inspect(err)}"}
        end

      {:error, reason} ->
        {:error, "There was a problem reading the file: #{inspect(reason)}"}
    end
  end

  def get_enabled_artifacts(), do: GenServer.call(__MODULE__, :get_enabled_artifacts, 25_000)
  def get_artifact(id), do: GenServer.cast(__MODULE__, {:get_artifact, id})
  def get_artifact_details(id), do: GenServer.call(__MODULE__, {:get_artifact_details, id})
  def add_artifact(share), do: GenServer.call(__MODULE__, {:add_artifact, share}, 25_000)
  def remove_artifact(id), do: GenServer.cast(__MODULE__, {:remove_artifact, id})
  # Update specific settings
  # TODO: This needs to change to be more generic
  def update_artifact(data, :tunneld),
    do: GenServer.cast(__MODULE__, {:update_artifact, :tunneld, data})

  @doc """
  Check if the share file exists.
  """
  def file_exists?(), do: File.exists?(path())

  def path(), do: "./" <> config_fs(:root) <> config_fs(:shares)
  defp config_fs(), do: Application.get_env(:tunneld, :fs)
  defp config_fs(key), do: config_fs()[key]
end
