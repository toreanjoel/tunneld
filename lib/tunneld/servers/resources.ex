defmodule Tunneld.Servers.Resources do
  @moduledoc """
  Central resource registry — manages "resources" (references to applications
  hosted on devices within the Tunneld network).

  A resource represents a service that Tunneld can proxy and optionally expose
  via Zrok tunnels. Each resource has:
  - A **pool** of backend `IP:port` entries (load-balanced by nginx)
  - A **public** Zrok share (internet-accessible via the Zrok network)
  - A **private** Zrok share (accessible only to other Zrok-enabled devices)
  - Optional **basic auth** on the public share

  Resources are persisted to `resources.json` and synced to nginx configs,
  dnsmasq DNS entries, and Zrok reservations/systemd units.

  This module also manages "access" entries — connections to remote Zrok shares
  that bind to a local port for consumption.

  State is periodically broadcast to the dashboard via PubSub.
  """
  use GenServer
  require Logger
  alias Tunneld.Servers.{Nginx, Zrok}

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
  Init resource persistence
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
             :ok <- Tunneld.Persistence.write_json(path(), u_nodes) do
          Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{type: :info, message: "resource added successfully"})

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
    resources = read_file()

    new_id = DateTime.utc_now() |> DateTime.to_unix() |> to_string()
    id = new_id <> "acc"

    name = access["name"] || access[:name] || "access-" <> new_id
    ip = "0.0.0.0"
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
              "share_names" => %{"private" => name},
              "units" => %{"access" => %{"id" => acc_id, "unit" => acc_unit}},
              "enabled" => %{"access" => false}
            }
          }

          updated0 = resources ++ [access_entry]
          :ok = Tunneld.Persistence.write_json(path(), updated0)

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

  def handle_call({:get_private_token, resource_id}, _from, state) do
    resources = read_file()
    resource = Enum.find(resources, fn r -> r["id"] == resource_id end)

    priv_unit = get_in(resource || %{}, ["tunneld", "units", "private", "unit"])

    token =
      if priv_unit do
        case Zrok.get_share_token(priv_unit) do
          {:ok, t} when is_binary(t) -> t
          _ -> nil
        end
      end

    if token do
      updated =
        Enum.map(resources, fn r ->
          if r["id"] == resource_id do
            put_in(r, ["tunneld", "share_names", "private"], token)
          else
            r
          end
        end)

      _ = Tunneld.Persistence.write_json(path(), updated)
      broadcast_shares()

      Phoenix.PubSub.broadcast(Tunneld.PubSub, @broadcast_topic, %{
        id: @component_desktop_id,
        module: @component_module,
        data:
          updated
          |> Enum.find(&(&1["id"] == resource_id))
          |> then(fn s ->
            pool = Map.get(s, "pool", [])

            %{
              id: s["id"],
              name: s["name"],
              ip: s["ip"],
              description: s["description"],
              port: s["port"],
              status: Map.get(s, "status", false),
              pool: pool,
              pool_details: pool_health_details(pool, mock?()),
              health: pool_health(pool, mock?()),
              tunneld: s["tunneld"],
              kind: s["kind"]
            }
          end)
      })

      {:reply, {:ok, token}, Map.put(state, :resources, updated)}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  def handle_cast(:init_local_shares, state) do
    resources = read_file()

    # Re-register all host resources: public names and nginx configs
    try do
      if not Enum.empty?(resources) do
        hosts = Enum.filter(resources, fn s -> s["kind"] === "host" end)

        Enum.each(hosts, fn s ->
          name = s["name"]

          base = sanitize_base(name)
          pub_name = make_token(base, "pub")
          priv_name = make_token(base, "priv")

          # Delete and recreate the name to rebind it to the current environment.
          # After disconnect/reconnect the zrok environment ID changes, so names
          # from the old environment need to be released and re-registered.
          Zrok.delete_name(pub_name)
          Zrok.create_public_name(pub_name)
          Zrok.create_private_name(priv_name)

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
    resources = read_file()

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

    case persist_and_broadcast(updated_shares, "Shares hibernated", "Failed to hibernate shares") do
      {:ok, _} -> {:noreply, Map.put(state, :resources, updated_shares)}
      {:error, _} -> {:noreply, state}
    end
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

  def handle_cast({:toggle_access, unit_id, enable}, state) do
    enable? =
      case enable do
        true -> true
        "true" -> true
        "on" -> true
        _ -> false
      end

    resources = read_file()

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
        result =
          try do
            if enable?, do: Zrok.enable_access(unit_id), else: Zrok.disable_access(unit_id)
          catch
            :exit, {:timeout, _} -> {:error, :timeout}
          end

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

            case persist_and_broadcast(updated_shares, "Access #{if enable?, do: "enabled", else: "disabled"}", "Failed to persist access state") do
              {:ok, _} -> {:noreply, Map.put(state, :resources, updated_shares)}
              {:error, _} -> {:noreply, state}
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
    resources = read_file()
    resource = Enum.find(resources, fn s -> s["id"] === id and s["kind"] == "access" end)

    _ =
      if resource do
        units = get_in(resource, ["tunneld", "units"]) || %{}

        case units["access"] do
          %{"id" => aid} -> Zrok.remove_access(aid)
          _ -> :ok
        end
      end

    updated_nodes = Enum.reject(resources, fn s -> s["id"] === id and s["kind"] == "access" end)

    update_state =
      case persist_and_broadcast(updated_nodes, "access removed successfully", "Failed to remove access") do
        {:ok, _} -> Map.put(state, :resources, updated_nodes)
        {:error, _} -> state
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

    resources = read_file()

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
          try do
            if enable? do
              Tunneld.Servers.Zrok.enable_share(unit_id)
            else
              Tunneld.Servers.Zrok.disable_share(unit_id)
            end
          catch
            :exit, {:timeout, _} -> {:error, :timeout}
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

            case Tunneld.Persistence.write_json(path(), updated_shares) do
              :ok ->
                broadcast_shares()

                updated_atom_share =
                  updated_shares
                  |> Enum.find(&(&1["id"] == resource["id"]))
                  |> then(fn s ->
                    pool = Map.get(s, "pool", [])
                    kind = s["kind"] || "host"

                    health =
                      if kind == "host",
                        do: pool_health(pool, mock?()),
                        else: %{status: :not_applicable}

                    %{
                      id: s["id"],
                      name: s["name"],
                      ip: s["ip"],
                      description: s["description"],
                      port: s["port"],
                      status: Map.get(s, "status", false),
                      pool: pool,
                      pool_details: pool_health_details(pool, mock?()),
                      health: health,
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

  def handle_cast({:update_share, type, data}, state) do
    resources = read_file()

    cond do
      Enum.empty?(resources) ->
        {:noreply, state}

      true ->
        resource = Enum.find(resources, fn r -> r["id"] == data["id"] end)

        updated_shares =
          case type do
            :tunneld ->
              Enum.map(resources, fn r ->
                if r["id"] == resource["id"] do
                  Map.put(r, "tunneld", data)
                else
                  r
                end
              end)

            _ ->
              Logger.error("Tried to set settings with an unhandled type")
              resources
          end

        case persist_and_broadcast(updated_shares, "Resource updated successfully", "Failed to update resource") do
          {:ok, _} ->
            Phoenix.PubSub.broadcast(
              Tunneld.PubSub,
              "show_details",
              {:show_details, %{"id" => data["id"], "type" => "resource"}}
            )

          {:error, _} ->
            :ok
        end
    end

    {:noreply, state}
  end

  def handle_cast({:configure_basic_auth, params}, state) do
    resource_id = params["resource_id"]
    resources = read_file()

    resource = Enum.find(resources, fn r -> r["id"] == resource_id end)

    if resource do
      # Prepare auth config
      auth_config = %{
        "enabled" => true,
        "username" => params["username"],
        "password" => params["password"]
      }

      reconfigure_share(resource, auth_config, resources, state)
    else
      {:noreply, state}
    end
  end

  def handle_cast({:disable_basic_auth, resource_id}, state) do
    resources = read_file()

    resource = Enum.find(resources, fn r -> r["id"] == resource_id end)

    if resource do
      auth_config = %{"enabled" => false}
      reconfigure_share(resource, auth_config, resources, state)
    else
      {:noreply, state}
    end
  end

  def handle_cast({:remove_share, id}, state) do
    resources = read_file()
    resource = Enum.find(resources, fn s -> s["id"] === id end)

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
          case tunneld["share_names"] do
            %{"public" => pub, "private" => priv} ->
              # Clean up both public and private shares from the controller
              _ = Zrok.delete_name(pub)
              # Delete private share session if we have the token
              if is_binary(priv) and priv != "" do
                Zrok.cleanup_share_by_name(priv)
              end

            _ ->
              :ok
          end

        _ = Nginx.remove_resource_config(id)
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

  defp reconfigure_share(resource, auth_config, resources, state) do
    updated_resource =
      update_in(resource, ["tunneld", "auth"], fn auth ->
        Map.put(auth || %{}, "basic", auth_config)
      end)

    # Regenerate the systemd files for the public share
    tunneld = updated_resource["tunneld"] || %{}
    units = tunneld["units"] || %{}

    if public_unit = units["public"] do
      Zrok.remove_share(public_unit["id"])
    end

    # In zrok v2, the name persists — we just recreate the unit with new auth args.
    # No need to delete and recreate the name itself.
    share_names = tunneld["share_names"] || %{}
    pub_name = share_names["public"]

    ip = updated_resource["ip"] || @nginx_ip
    port = updated_resource["port"] || @nginx_port
    target = "#{ip}:#{port}"

    create_payload = %{
      "id" => "#{updated_resource["id"]}pub",
      "name" => updated_resource["name"],
      "tunneld" => %{
        "share_type" => "public",
        "share_name" => pub_name,
        "target" => target,
        "auth" => %{"basic" => auth_config}
      }
    }

    case Zrok.create_share_unit(create_payload) do
      {:ok, %{id: new_pub_id, unit: new_pub_unit}} ->
        updated_resource =
          put_in(updated_resource, ["tunneld", "units", "public"], %{
            "id" => new_pub_id,
            "unit" => new_pub_unit
          })

        if get_in(resource, ["tunneld", "enabled", "public"]) do
          Zrok.enable_share(new_pub_id)
        end

        updated_shares =
          Enum.map(resources, fn r ->
            if r["id"] == resource["id"], do: updated_resource, else: r
          end)

        case Tunneld.Persistence.write_json(path(), updated_shares) do
          :ok ->
            Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
              type: :info,
              message: "Resource configuration updated"
            })

            broadcast_shares()
            {:noreply, Map.put(state, :resources, updated_shares)}

          {:error, err} ->
            Logger.error("Failed to persist resource config: #{inspect(err)}")
            {:noreply, state}
        end

      {:error, err} ->
        Logger.error("Failed to recreate share unit: #{inspect(err)}")
        Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
          type: :error,
          message: "Failed to update resource configuration"
        })
        {:noreply, state}
    end
  end

  defp create_reserved_and_units(new_share) do
    name = new_share["name"]
    ip = Map.get(new_share, "ip", @nginx_ip)
    port = Map.get(new_share, "port", @nginx_port)
    target = "#{ip}:#{port}"

    base = sanitize_base(name)
    pub_name = make_token(base, "pub")
    priv_name = make_token(base, "priv")

    tunneld = new_share["tunneld"] || %{}
    auth = tunneld["auth"] || %{}
    basic_auth = auth["basic"] || %{}

    with :ok <- Zrok.create_public_name(pub_name),
         :ok <- Zrok.create_private_name(priv_name),
         {:ok, %{id: pub_id, unit: pub_unit}} <-
           Zrok.create_share_unit(%{
             "id" => "#{new_share["id"]}pub",
             "name" => name,
             "tunneld" => %{
               "share_type" => "public",
               "share_name" => pub_name,
               "target" => target,
               "auth" => %{"basic" => basic_auth}
             }
           }),
         {:ok, %{id: priv_id, unit: priv_unit}} <-
           Zrok.create_share_unit(%{
             "id" => "#{new_share["id"]}priv",
             "name" => name,
             "tunneld" => %{
               "share_type" => "private",
               "share_name" => priv_name,
               "target" => target
             }
           }) do
      {:ok,
       Map.merge(tunneld, %{
         "share_names" => %{"public" => pub_name, "private" => priv_name},
         "units" => %{
           "public" => %{"id" => pub_id, "unit" => pub_unit},
           "private" => %{"id" => priv_id, "unit" => priv_unit}
         },
         "enabled" => %{"public" => false, "private" => false},
         "auth" => %{"basic" => basic_auth}
       })}
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
    resources = read_file()

    Enum.map(resources, fn s ->
      kind = s["kind"] || "host"
      pool = Map.get(s, "pool", [])

      {ip, port} =
        case kind do
          "access" -> parse_bind(s["bind"])
          _ -> {s["ip"] || @nginx_ip, s["port"] || @nginx_port}
        end

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
        tunneld: s["tunneld"],
        kind: kind,
        expose_source: s["expose_source"],
        expose_device_mac: s["expose_device_mac"],
        expose_device_ip: s["expose_device_ip"]
      }
    end)
  end

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

  @doc "Enable or disable a Zrok share unit by its systemd unit ID."
  def toggle_share(unit_id, enable),
    do: GenServer.cast(__MODULE__, {:toggle_share, unit_id, enable})

  @doc "Add a new host resource with Zrok reservations, nginx config, and DNS entry."
  def add_share(resource), do: GenServer.call(__MODULE__, {:add_share, resource}, 25_000)

  @doc "Re-register all existing host resources with Zrok on startup."
  def try_init_local_shares(), do: GenServer.cast(__MODULE__, :init_local_shares)

  @doc "Disable all active Zrok shares (used before shutdown/restart)."
  def try_hibernate_shares(), do: GenServer.cast(__MODULE__, :hibernate_shares)

  @doc "Remove a host resource and clean up its Zrok reservations, nginx config, and DNS entry."
  def remove_share(id), do: GenServer.cast(__MODULE__, {:remove_share, id})

  @doc "Add a new access entry (bind a remote Zrok share to a local port)."
  def add_access(access), do: GenServer.call(__MODULE__, {:add_access, access}, 25_000)

  @doc "Enable or disable a Zrok access unit by its systemd unit ID."
  def toggle_access(unit_id, enable),
    do: GenServer.cast(__MODULE__, {:toggle_access, unit_id, enable})

  @doc "Remove an access entry and its Zrok access unit."
  def remove_access(id), do: GenServer.cast(__MODULE__, {:remove_access, id})

  @doc "Fetch the private share token from the journal and persist it."
  def get_private_token(resource_id),
    do: GenServer.call(__MODULE__, {:get_private_token, resource_id}, 15_000)

  @doc """
  Update a resource. The second argument determines what is updated:
  - `:tunneld` — update the Zrok tunnel metadata
  - `:resource` — update resource fields (description, pool) and regenerate nginx config
  """
  def update_share(data, :tunneld),
    do: GenServer.cast(__MODULE__, {:update_share, :tunneld, data})

  def update_share(data, :resource),
    do: GenServer.cast(__MODULE__, {:update_share, :resource, data})

  @doc "Configure HTTP basic auth on a resource's public Zrok share."
  def configure_basic_auth(params),
    do: GenServer.cast(__MODULE__, {:configure_basic_auth, params})

  @doc "Disable HTTP basic auth on a resource's public Zrok share."
  def disable_basic_auth(resource_id),
    do: GenServer.cast(__MODULE__, {:disable_basic_auth, resource_id})

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
