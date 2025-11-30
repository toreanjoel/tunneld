defmodule Tunneld.Servers.Resources do
  @moduledoc """
  Manage the resources (to a running application hosted on some device on the network)
  """
  use GenServer
  require Logger
  alias Tunneld.Servers.{Nginx, Zrok}

  @interval 10_000
  @nginx_ip "127.0.0.1"
  @nginx_port "18000"

  @broadcast_topic_main "component:resources"
  @broadcast_topic "component:details"
  @component_desktop_id "sidebar_details"
  @component_module TunneldWeb.Live.Components.Sidebar.Details

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init resource persistence
  """
  def init(_) do
    if not file_exists?(), do: create_file()
    send(self(), :sync)
    {:ok, %{}}
  end

  def handle_call({:add_share, resource}, _from, state) do
    resources =
      case read_file() do
        {:ok, list} when is_list(list) -> list
        _ -> []
      end

    exists = Enum.find(resources, fn item -> item["name"] === resource["name"] end)

    state =
      if is_nil(exists) do
        pool = normalize_pool(resource)

        new_share =
          resource
          |> Map.put("ip", @nginx_ip)
          |> Map.put("port", @nginx_port)
          |> Map.put("pool", pool)
          |> Map.merge(%{
            "id" => DateTime.utc_now() |> DateTime.to_unix() |> to_string,
            "kind" => "host",
            "tunneld" => %{}
          })

        new_share =
          if Map.has_key?(resource, "tunneld") do
            # In case a caller already included metadata, we still ensure our defaults
            Map.put(new_share, "tunneld", Map.get(resource, "tunneld"))
          else
            new_share
          end

        with {:ok, reserve_meta} <- create_reserved_and_units(new_share),
             configured_share <- Map.merge(new_share, %{"tunneld" => reserve_meta}),
             :ok <- Nginx.upsert_resource_config(configured_share),
             u_nodes <- resources ++ [configured_share],
             :ok <- File.write(path(), Jason.encode!(u_nodes)) do
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

  def handle_call({:add_access, access}, _from, state) do
    resources =
      case read_file() do
        {:ok, list} when is_list(list) -> list
        _ -> []
      end

    new_id = DateTime.utc_now() |> DateTime.to_unix() |> to_string()
    id = new_id <> "acc"

    name = access["name"] || access[:name] || "access-" <> new_id
    ip = access["ip"] || access[:ip]
    port = access["port"] || access[:port]

    if is_binary(ip) and ip != "" and is_binary(port) and port != "" do
      bind = "#{ip}:#{port}"

      create_payload =
        %{
          "id" => id,
          "name" => name,
          "reserved_name" => name,
          "bind" => bind
        }

      case Zrok.create_access_unit(create_payload) do
        {:ok, %{id: acc_id, unit: acc_unit}} ->
          access_entry = %{
            "id" => new_id,
            "name" => name,
            "kind" => "access",
            "bind" => bind,
            "description" => access["description"] || "",
            "tunneld" => %{
              "reserved" => %{"private" => name},
              "units" => %{"access" => %{"id" => acc_id, "unit" => acc_unit}},
              "enabled" => %{"access" => false}
            }
          }

          updated0 = resources ++ [access_entry]
          :ok = File.write(path(), Jason.encode!(updated0))

          broadcast_shares()

          Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
            type: :info,
            message: "access added successfully"
          })

          new_state = Map.put(state, :resources, updated0)
          {:reply, new_state, new_state}

        {:error, err} ->
          Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
            type: :error,
            message: "Failed to add access: #{inspect(err)}"
          })

          {:reply, state, state}
      end
    else
      Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
        type: :error,
        message: "ip and port are required"
      })

      {:reply, state, state}
    end
  end

  def handle_cast(:init_local_shares, state) do
    resources =
      case read_file() do
        {:ok, list} when is_list(list) -> list
        _ -> []
      end

    # We try and add all the resources we had locally
    try do
      if not Enum.empty?(resources) do
        resources
        |> Enum.each(fn s ->
          name = s["name"]
          ip = Map.get(s, "ip", @nginx_ip)
          port = Map.get(s, "port", @nginx_port)

          base = sanitize_base(name)
          pub_token = make_token(base, "pub")
          priv_token = make_token(base, "priv")

          Zrok.reserve_public(pub_token, ip, port)
          Zrok.reserve_private(priv_token, ip, port)

          # Ensure nginx config is present on boot/resync
          _ = ensure_nginx_config(s)
        end)
      end
    rescue
      _e ->
        Logger.error("There was a problem setting the resources on the cloud env")
        :error
    end

    {:noreply, state}
  end

  def handle_cast(:hibernate_shares, state) do
    resources =
      case read_file() do
        {:ok, list} when is_list(list) -> list
        _ -> []
      end

    updated_shares =
      Enum.map(resources, fn s ->
        units = get_in(s, ["tunneld", "units"]) || %{}

        case get_in(units, ["private", "id"]) do
          id when is_binary(id) and id != "" -> Zrok.disable_share(id)
          _ -> :ok
        end

        case get_in(units, ["public", "id"]) do
          id when is_binary(id) and id != "" -> Zrok.disable_share(id)
          _ -> :ok
        end

        case get_in(units, ["access", "id"]) do
          id when is_binary(id) and id != "" -> Zrok.disable_access(id)
          _ -> :ok
        end

        s
        |> put_in(["tunneld", "enabled", "public"], false)
        |> put_in(["tunneld", "enabled", "private"], false)
        |> put_in(["tunneld", "enabled", "access"], false)
      end)

    case File.write(path(), Jason.encode!(updated_shares)) do
      :ok ->
        broadcast_shares()
        {:noreply, Map.put(state, :resources, updated_shares)}

      {:error, _err} ->
        {:noreply, state}
    end
  end

  def handle_cast({:get_resource, id}, state) do
    resources = fetch_shares()

    if !Enum.empty?(resources) do
      resource =
        Enum.filter(resources, fn resource -> resource.id === id or resource["id"] === id end)
        |> Enum.at(0)

      Phoenix.PubSub.broadcast(Tunneld.PubSub, @broadcast_topic, %{
        id: @component_desktop_id,
        module: @component_module,
        data: resource
      })
    end

    {:noreply, state}
  end

  def handle_cast({:toggle_access, unit_id, enable}, state) do
    enable? =
      case enable do
        true -> true
        "true" -> true
        "on" -> true
        _ -> false
      end

    {_status, data} = read_file()
    resources = if data == "", do: [], else: data

    {entry, _kind} =
      Enum.reduce_while(resources, {nil, nil}, fn s, _acc ->
        units = get_in(s, ["tunneld", "units"]) || %{}

        if get_in(units, ["access", "id"]) == unit_id,
          do: {:halt, {s, "access"}},
          else: {:cont, {nil, nil}}
      end)

    case entry do
      nil ->
        Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
          type: :error,
          message: "Access for unit not found"
        })

        {:noreply, state}

      _ ->
        result = if enable?, do: Zrok.enable_access(unit_id), else: Zrok.disable_access(unit_id)

        case result do
          :ok ->
            updated_shares =
              Enum.map(resources, fn s ->
                if s["id"] == entry["id"] do
                  put_in(s, ["tunneld", "enabled", "access"], enable?)
                else
                  s
                end
              end)

            case File.write(path(), Jason.encode!(updated_shares)) do
              :ok ->
                broadcast_shares()
                {:noreply, Map.put(state, :resources, updated_shares)}

              {:error, err} ->
                Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
                  type: :error,
                  message: "Failed to persist access state: #{inspect(err)}"
                })

                {:noreply, state}
            end

          {:error, err} ->
            Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
              type: :error,
              message:
                "Failed to #{if enable?, do: "enable", else: "disable"} access: #{inspect(err)}"
            })

            {:noreply, state}
        end
    end
  end

  def handle_cast({:remove_access, id}, state) do
    {_, data} = read_file()
    resource = Enum.find(data, fn s -> s["id"] === id and s["kind"] == "access" end)

    _ =
      if resource do
        units = get_in(resource, ["tunneld", "units"]) || %{}

        case units["access"] do
          %{"id" => aid} -> Zrok.remove_access(aid)
          _ -> :ok
        end
      end

    updated_nodes = Enum.reject(data, fn s -> s["id"] === id and s["kind"] == "access" end)

    update_state =
      case File.write(path(), Jason.encode!(updated_nodes)) do
        :ok ->
          Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
            type: :info,
            message: "access removed successfully"
          })

          broadcast_shares()
          Map.put(state, :resources, updated_nodes)

        {:error, err} ->
          Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
            type: :error,
            message: "Failed to remove access: #{inspect(err)}"
          })

          state
      end

    {:noreply, update_state}
  end

  def handle_cast({:toggle_share, unit_id, enable}, state) do
    enable? =
      case enable do
        true -> true
        "true" -> true
        "on" -> true
        _ -> false
      end

    {_status, data} = read_file()
    resources = if data == "", do: [], else: data

    {resource, kind} =
      Enum.reduce_while(resources, {nil, nil}, fn s, _acc ->
        units = get_in(s, ["tunneld", "units"]) || %{}

        cond do
          get_in(units, ["public", "id"]) == unit_id -> {:halt, {s, "public"}}
          get_in(units, ["private", "id"]) == unit_id -> {:halt, {s, "private"}}
          true -> {:cont, {nil, nil}}
        end
      end)

    case {resource, kind} do
      {nil, _} ->
        Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
          type: :error,
          message: "Resource for unit not found"
        })

        {:noreply, state}

      {resource, kind} ->
        result =
          if enable? do
            Tunneld.Servers.Zrok.enable_share(unit_id)
          else
            Tunneld.Servers.Zrok.disable_share(unit_id)
          end

        case result do
          :ok ->
            updated_shares =
              Enum.map(resources, fn s ->
                if s["id"] == resource["id"] do
                  put_in(s, ["tunneld", "enabled", kind], enable?)
                else
                  s
                end
              end)

            case File.write(path(), Jason.encode!(updated_shares)) do
              :ok ->
                broadcast_shares()

                updated_atom_share =
                  updated_shares
                  |> Enum.find(&(&1["id"] == resource["id"]))
                  |> then(fn s ->
                    %{
                      id: s["id"],
                      name: s["name"],
                      ip: s["ip"],
                      description: s["description"],
                      port: s["port"],
                      status: port_busy?(s["ip"], s["port"]),
                      tunneld: s["tunneld"],
                      kind: s["kind"]
                    }
                  end)

                Phoenix.PubSub.broadcast(Tunneld.PubSub, @broadcast_topic, %{
                  id: @component_desktop_id,
                  module: @component_module,
                  data: updated_atom_share
                })

                {:noreply, Map.put(state, :resources, updated_shares)}

              {:error, err} ->
                Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
                  type: :error,
                  message: "Failed to persist resource state: #{inspect(err)}"
                })

                {:noreply, state}
            end

          {:error, err} ->
            Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
              type: :error,
              message:
                "Failed to #{if enable?, do: "enable", else: "disable"} resource: #{inspect(err)}"
            })

            {:noreply, state}
        end
    end
  end

  def handle_cast({:update_share, type, data}, state) do
    resources = fetch_shares()

    if !Enum.empty?(resources) do
      resource =
        Enum.filter(resources, fn resource ->
          resource.id === data["id"] or resource["id"] === data["id"]
        end)
        |> Enum.at(0)

      updated_shares =
        case type do
          :tunneld ->
            Enum.map(resources, fn a ->
              if a.id === resource.id do
                Map.put(a, :tunneld, data)
              else
                a
              end
            end)

          _ ->
            Logger.error("Tried to set settings with an unhandled type")
            resources
        end

      case File.write(path(), Jason.encode!(updated_shares)) do
        :ok ->
          Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
            type: :info,
            message: "Resource updated successfully"
          })

          broadcast_shares()

          Phoenix.PubSub.broadcast(
            Tunneld.PubSub,
            "show_details",
            {:show_details, %{"id" => data["id"], "type" => "resource"}}
          )

        {:error, err} ->
          Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
            type: :error,
            message: "Failed to update resource: #{inspect(err)}"
          })
      end
    end

    {:noreply, state}
  end

  def handle_cast({:remove_share, id}, state) do
    {_, data} = read_file()
    resource = Enum.find(data, fn s -> s["id"] === id end)

    _ =
      if resource do
        tunneld = resource["tunneld"] || %{}
        units = tunneld["units"] || %{}

        _ =
          case units["public"] do
            %{"id" => pid} -> Tunneld.Servers.Zrok.remove_share(pid)
            _ -> :ok
          end

        _ =
          case units["private"] do
            %{"id" => qid} -> Tunneld.Servers.Zrok.remove_share(qid)
            _ -> :ok
          end

        _ =
          case tunneld["reserved"] do
            %{"public" => pub, "private" => priv} ->
              _ = Zrok.release_reserved(pub)
              _ = Zrok.release_reserved(priv)

            _ ->
              :ok
          end

        _ = Nginx.remove_resource_config(id)
      end

    updated_nodes = Enum.reject(data, fn resource -> resource["id"] === id end)

    update_state =
      case File.write(path(), Jason.encode!(updated_nodes)) do
        :ok ->
          Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
            type: :info,
            message: "resource removed successfully"
          })

          broadcast_shares()

          Phoenix.PubSub.broadcast(Tunneld.PubSub, @broadcast_topic, %{
            id: @component_desktop_id,
            module: @component_module,
            data: %{id: id}
          })

          Map.put(state, :resources, updated_nodes)

        {:error, err} ->
          Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
            type: :error,
            message: "Failed to remove resource: #{inspect(err)}"
          })

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

  defp create_reserved_and_units(new_share) do
    name = new_share["name"]
    ip = Map.get(new_share, "ip", @nginx_ip)
    port = Map.get(new_share, "port", @nginx_port)

    base = sanitize_base(name)
    pub_token = make_token(base, "pub")
    priv_token = make_token(base, "priv")

    with :ok <- Zrok.reserve_public(pub_token, ip, port),
         :ok <- Zrok.reserve_private(priv_token, ip, port),
         {:ok, %{id: pub_id, unit: pub_unit}} <-
           Zrok.create_share_unit(%{
             "id" => "#{new_share["id"]}pub",
             "name" => name,
             "tunneld" => %{
               "kind" => "reserved",
               "reserved_token" => pub_token,
               "headless" => true
             }
           }),
         {:ok, %{id: priv_id, unit: priv_unit}} <-
           Zrok.create_share_unit(%{
             "id" => "#{new_share["id"]}priv",
             "name" => name,
             "tunneld" => %{
               "kind" => "reserved",
               "reserved_token" => priv_token,
               "headless" => true
             }
           }) do
      {:ok,
       %{
         "reserved" => %{"public" => pub_token, "private" => priv_token},
         "units" => %{
           "public" => %{"id" => pub_id, "unit" => pub_unit},
           "private" => %{"id" => priv_id, "unit" => priv_unit}
         },
         "enabled" => %{"public" => false, "private" => false}
       }}
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  defp sanitize_base(name) do
    base =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]/, "")

    base =
      if String.length(base) < 4 do
        String.pad_trailing(base, 4, "0")
      else
        base
      end

    String.slice(base, 0, 29)
  end

  defp make_token(base, suffix) do
    token = base <> suffix
    String.slice(token, 0, 32)
  end

  defp parse_bind(<<>>), do: {nil, nil}
  defp parse_bind(nil), do: {nil, nil}

  defp parse_bind(bind) do
    case String.split(bind, ":", parts: 2) do
      [ip, port] -> {ip, port}
      _ -> {nil, nil}
    end
  end

  def fetch_shares() do
    {_status, data} = read_file()
    resources = if data == "", do: [], else: data

    Enum.map(resources, fn s ->
      kind = s["kind"] || "host"

      {ip, port} =
        case kind do
          "access" -> parse_bind(s["bind"])
          _ -> {s["ip"] || @nginx_ip, s["port"] || @nginx_port}
        end

      %{
        id: s["id"],
        name: s["name"],
        ip: ip,
        description: s["description"],
        port: port,
        pool: Map.get(s, "pool", []),
        status: (ip && port && port_busy?(ip, port)) || false,
        tunneld: s["tunneld"],
        kind: kind
      }
    end)
  end

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

  def create_file() do
    case File.write(path(), Jason.encode!([])) do
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
  end

  def read_file() do
    case path() |> File.read() do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, data} -> {:ok, data}
          {:error, err} -> {:error, "Failed to decode resource file: #{inspect(err)}"}
        end

      {:error, reason} ->
        {:error, "There was a problem reading the file: #{inspect(reason)}"}
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

  def get_resource(id), do: GenServer.cast(__MODULE__, {:get_resource, id})

  def toggle_share(unit_id, enable),
    do: GenServer.cast(__MODULE__, {:toggle_share, unit_id, enable})

  def add_share(resource), do: GenServer.call(__MODULE__, {:add_share, resource}, 25_000)
  def try_init_local_shares(), do: GenServer.cast(__MODULE__, :init_local_shares)
  def try_hibernate_shares(), do: GenServer.cast(__MODULE__, :hibernate_shares)
  def remove_share(id), do: GenServer.cast(__MODULE__, {:remove_share, id})

  def add_access(access), do: GenServer.call(__MODULE__, {:add_access, access}, 25_000)

  def toggle_access(unit_id, enable),
    do: GenServer.cast(__MODULE__, {:toggle_access, unit_id, enable})

  def remove_access(id), do: GenServer.cast(__MODULE__, {:remove_access, id})

  def update_share(data, :tunneld),
    do: GenServer.cast(__MODULE__, {:update_share, :tunneld, data})

  def file_exists?(), do: File.exists?(path())

  def path(), do: Path.join(config_fs(:root), config_fs(:resources))
  defp config_fs(key) do
    case Application.get_env(:tunneld, :fs) do
      kw when is_list(kw) -> Keyword.get(kw, key)
      map when is_map(map) -> Map.get(map, key) || Map.get(map, to_string(key))
      _ -> nil
    end
  end
end
