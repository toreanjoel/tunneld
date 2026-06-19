defmodule Tunneld.Servers.Resources do
  @moduledoc """
  Central resource registry - manages "resources" (references to applications
  hosted on devices within the Tunneld subnet).

  A resource represents a service that Tunneld can proxy for LAN devices. Each
  resource has:

  - A **pool** of backend `IP:port` entries (load-balanced by nginx)
  - A local DNS name (`<name>.tunneld.lan`) served by dnsmasq on the gateway
  - An nginx reverse-proxy config that listens on `0.0.0.0:18000` and forwards
    to the backend pool

  Resources are persisted to `resources.json` and synced to nginx configs.
  There is no public-internet exposure and no per-resource auth - access is
  limited to the local subnet (and, later, the relay/mesh).

  State is periodically broadcast to the dashboard via PubSub.
  """

  use GenServer
  require Logger
  alias Tunneld.Servers.Nginx

  @interval 10_000
  @nginx_ip "127.0.0.1"
  @nginx_port "18000"
  defp mock?, do: Application.get_env(:tunneld, :mock_data, false)

  @broadcast_topic_main "component:resources"
  @broadcast_topic "component:details"
  @component_desktop_id "sidebar_details"
  @component_module TunneldWeb.Live.Components.Sidebar.Details

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init resource persistence.
  """
  def init(_) do
    if not file_exists?(), do: create_file()
    send(self(), :sync)
    {:ok, %{}}
  end

  def handle_call({:add_share, resource}, _from, state) do
    resources = read_file()

    exists = Enum.find(resources, fn item -> item["name"] === resource["name"] end)

    state =
      if is_nil(exists) do
        pool = normalize_pool(resource)

        new_resource =
          resource
          |> Map.put("ip", @nginx_ip)
          |> Map.put("port", @nginx_port)
          |> Map.put("pool", pool)
          |> Map.merge(%{
            "id" => DateTime.utc_now() |> DateTime.to_unix() |> to_string,
            "kind" => "host"
          })
          |> Map.drop(["tunneld"])

        with :ok <- Nginx.upsert_resource_config(new_resource),
             u_nodes <- resources ++ [new_resource],
             :ok <- Tunneld.Persistence.write_json(path(), u_nodes) do
          Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
            type: :info,
            message: "resource added successfully"
          })

          broadcast_shares()
          Map.put(state, :resources, u_nodes)
        else
          {:error, err} ->
            Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
              type: :error,
              message: "Failed to add resource: #{inspect(err)}"
            })

            state
        end
      else
        Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
          type: :error,
          message: "Resource name already exists"
        })

        state
      end

    {:reply, state, state}
  end

  def handle_cast({:get_resource, id}, state) do
    resources = fetch_shares()

    if !Enum.empty?(resources) do
      resource =
        Enum.filter(resources, fn r -> r.id === id or r["id"] === id end)
        |> Enum.at(0)

      Phoenix.PubSub.broadcast(Tunneld.PubSub, @broadcast_topic, %{
        id: @component_desktop_id,
        module: @component_module,
        data: resource
      })
    end

    {:noreply, state}
  end

  def handle_cast({:update_share, :resource, data}, state) do
    resources = read_file()

    resource = Enum.find(resources, fn r -> r["id"] == data["id"] end)

    cond do
      is_nil(resource) ->
        Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
          type: :error,
          message: "Resource not found"
        })

        {:noreply, state}

      resource["kind"] != "host" ->
        Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
          type: :error,
          message: "Only host resources can be edited"
        })

        {:noreply, state}

      true ->
        pool = normalize_pool(data)

        updated_resource =
          resource
          |> Map.put("description", data["description"] || resource["description"] || "")
          |> Map.put("pool", pool)
          |> Map.put("ip", @nginx_ip)
          |> Map.put("port", @nginx_port)

        updated_shares =
          Enum.map(resources, fn r ->
            if r["id"] == resource["id"] do
              updated_resource
            else
              r
            end
          end)

        case persist_and_broadcast(updated_shares, "Resource updated successfully", "Failed to update resource") do
          {:ok, _} ->
            _ = ensure_nginx_config(updated_resource)

            Phoenix.PubSub.broadcast(
              Tunneld.PubSub,
              "show_details",
              {:show_details, %{"id" => data["id"], "type" => "resource"}}
            )

            {:noreply, Map.put(state, :resources, updated_shares)}

          {:error, _} ->
            {:noreply, state}
        end
    end

    {:noreply, state}
  end

  def handle_cast({:remove_share, id}, state) do
    resources = read_file()
    resource = Enum.find(resources, fn s -> s["id"] === id end)

    _ =
      if resource do
        Nginx.remove_resource_config(id)
      end

    updated_nodes = Enum.reject(resources, fn resource -> resource["id"] === id end)

    update_state =
      case persist_and_broadcast(updated_nodes, "resource removed successfully", "Failed to remove resource") do
        {:ok, _} ->
          Phoenix.PubSub.broadcast(Tunneld.PubSub, @broadcast_topic, %{
            id: @component_desktop_id,
            module: @component_module,
            data: %{id: id}
          })

          Map.put(state, :resources, updated_nodes)

        {:error, _} ->
          state
      end

    {:noreply, update_state}
  end

  def handle_info(:sync, state) do
    resources = broadcast_shares()
    :timer.send_after(@interval, :sync)
    {:noreply, Map.put(state, :resources, resources)}
  end

  defp broadcast_shares() do
    resources = fetch_shares()

    Phoenix.PubSub.broadcast(Tunneld.PubSub, @broadcast_topic_main, %{
      id: "resources",
      module: TunneldWeb.Live.Components.Resources,
      data: resources
    })

    resources
  end

  # Persists updated resources, broadcasts, and returns {:ok, updated} or {:error, reason}.
  # Broadcasts a notification on error.
  defp persist_and_broadcast(updated_resources, success_msg, error_msg) do
    case Tunneld.Persistence.write_json(path(), updated_resources) do
      :ok ->
        Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
          type: :info,
          message: success_msg
        })

        broadcast_shares()
        {:ok, updated_resources}

      {:error, err} ->
        Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
          type: :error,
          message: "#{error_msg}: #{inspect(err)}"
        })

        {:error, err}
    end
  end

  def fetch_shares() do
    resources = read_file()

    Enum.map(resources, fn s ->
      kind = s["kind"] || "host"
      pool = Map.get(s, "pool", [])
      ip = s["ip"] || @nginx_ip
      port = s["port"] || @nginx_port

      health =
        case kind do
          "host" -> pool_health(pool, mock?())
          _ -> %{status: :not_applicable}
        end

      status_bool =
        case health[:status] do
          :all_up -> true
          _ -> false
        end

      %{
        id: s["id"],
        name: s["name"],
        ip: ip,
        description: s["description"],
        port: port,
        pool: pool,
        pool_details: pool_health_details(pool, mock?()),
        status: status_bool,
        health: health,
        kind: kind,
        lan_url: lan_url(s["name"]),
        expose_source: s["expose_source"],
        expose_device_mac: s["expose_device_mac"],
        expose_device_ip: s["expose_device_ip"]
      }
    end)
  end

  defp lan_url(name) when is_binary(name) do
    "http://#{Nginx.lan_hostname(name)}:#{Nginx.public_port()}"
  end

  defp lan_url(_), do: nil

  def create_file() do
    case Tunneld.Persistence.write_json(path(), []) do
      :ok -> {:ok, "Resources file created"}
      {:error, reason} -> {:error, "Failed to create Resources file: #{inspect(reason)}"}
    end
  end

  defp normalize_pool(resource) when is_map(resource) do
    pool =
      cond do
        is_list(resource["pool"]) -> resource["pool"]
        is_binary(resource["pool"]) -> [String.trim(resource["pool"])]
        is_list(resource[:pool]) -> resource[:pool]
        is_binary(resource[:pool]) -> [String.trim(resource[:pool])]
        true -> []
      end

    pool
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.filter(&valid_pool_entry?/1)
  end

  # Validates that a pool entry matches IP:port format to prevent
  # injection into nginx upstream configs.
  defp valid_pool_entry?(entry) do
    case String.split(entry, ":", parts: 2) do
      [ip, port] ->
        valid_ip?(ip) and valid_port?(port)

      _ ->
        false
    end
  end

  defp valid_ip?(ip) do
    case :inet.parse_address(String.to_charlist(ip)) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp valid_port?(port_str) do
    case Integer.parse(port_str) do
      {port, ""} -> port > 0 and port <= 65535
      _ -> false
    end
  end

  @doc "Read resources from disk. Returns a list (empty on missing/corrupt file)."
  def read_file() do
    case Tunneld.Persistence.read_json(path()) do
      {:ok, data} when is_list(data) -> data
      {:ok, _} -> []
      {:error, _reason} -> []
    end
  end

  defp ensure_nginx_config(resource) do
    case Map.get(resource, "pool") do
      pool when is_list(pool) and length(pool) > 0 ->
        Nginx.upsert_resource_config(resource)

      _ ->
        :ok
    end
  end

  @doc "Broadcast a single resource's details to the sidebar component."
  def get_resource(id), do: GenServer.cast(__MODULE__, {:get_resource, id})

  @doc "Add a new host resource with nginx config and a local DNS name."
  def add_share(resource), do: GenServer.call(__MODULE__, {:add_share, resource}, 25_000)

  @doc "Remove a host resource and clean up its nginx config."
  def remove_share(id), do: GenServer.cast(__MODULE__, {:remove_share, id})

  @doc """
  Update a resource's editable fields (description, pool) and regenerate nginx config.
  """
  def update_share(data, :resource),
    do: GenServer.cast(__MODULE__, {:update_share, :resource, data})

  @doc "Returns `true` if the resources JSON file exists on disk."
  def file_exists?(), do: File.exists?(path())

  @doc "Returns the full path to the resources JSON file."
  def path(), do: Path.join(Tunneld.Config.fs(:root), Tunneld.Config.fs(:resources))

  # --- Pool health checking ---

  @doc "Check the health of a pool of backend servers."
  def pool_health(pool, true) when is_list(pool) do
    total = length(pool)
    up = max(total - 1, 0)
    status = if up == total, do: :all_up, else: :partial
    %{status: status, total: total, up: up}
  end

  def pool_health(pool, false) when is_list(pool) do
    totals =
      pool
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.reduce(%{total: 0, up: 0}, fn entry, acc ->
        case String.split(entry, ":", parts: 2) do
          [ip, port_str] ->
            total = acc.total + 1

            up =
              case Integer.parse(port_str) do
                {port, _} ->
                  if backend_up?(ip, port), do: acc.up + 1, else: acc.up

                _ ->
                  acc.up
              end

            %{acc | total: total, up: up}

          _ ->
            acc
        end
      end)

    status =
      cond do
        totals.total == 0 -> :empty
        totals.up == 0 -> :none
        totals.up == totals.total -> :all_up
        true -> :partial
      end

    Map.put(totals, :status, status)
  end

  def pool_health(_, _), do: %{status: :empty, total: 0, up: 0}

  @doc "Returns per-entry health for each pool backend. Each entry is {address, up?}."
  def pool_health_details(pool, true) when is_list(pool) do
    pool
    |> Enum.with_index()
    |> Enum.map(fn {entry, i} -> {entry, i != 0} end)
  end

  def pool_health_details(pool, false) when is_list(pool) do
    pool
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn entry ->
      case String.split(entry, ":", parts: 2) do
        [ip, port_str] ->
          up = case Integer.parse(port_str) do
            {port, _} -> backend_up?(ip, port)
            _ -> false
          end
          {entry, up}

        _ ->
          {entry, false}
      end
    end)
  end

  def pool_health_details(_, _), do: []

  defp backend_up?(ip, port) do
    case :gen_tcp.connect(String.to_charlist(ip), port, [:binary, active: false], 1500) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      _ ->
        false
    end
  end
end