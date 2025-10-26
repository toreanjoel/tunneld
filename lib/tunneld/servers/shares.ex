defmodule Tunneld.Servers.Shares do
  @moduledoc """
  Manage the shares (to a running application hosted on some device on the network)
  """
  use GenServer
  require Logger
  alias Tunneld.Servers.Zrok

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
    if not file_exists?(), do: create_file()
    send(self(), :sync)
    {:ok, %{}}
  end

  def handle_call(:get_enabled_shares, _from, state) do
    shares = fetch_shares()
    data = shares |> Enum.filter(fn a -> a.tunneld["enabled"] end)
    {:reply, {:ok, data}, state}
  end

  def handle_call({:add_share, share}, _from, state) do
    shares =
      case read_file() do
        {:ok, list} when is_list(list) -> list
        _ -> []
      end

    exists =
      Enum.find(shares, fn item ->
        item["port"] === share["port"] and item["ip"] === share["ip"]
      end)

    state =
      if is_nil(exists) do
        new_share =
          share
          |> Map.merge(%{
            "id" => DateTime.utc_now() |> DateTime.to_unix() |> to_string,
            "kind" => "host",
            "tunneld" => %{}
          })

        with {:ok, reserve_meta} <- create_reserved_and_units(new_share),
             u_nodes <- shares ++ [Map.merge(new_share, %{"tunneld" => reserve_meta})],
             :ok <- File.write(path(), Jason.encode!(u_nodes)) do
          Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
            type: :info,
            message: "share added successfully"
          })

          broadcast_shares()
          Map.put(state, :shares, u_nodes)
        else
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

    {:reply, state, state}
  end

  def handle_call({:get_share_details, id}, _from, state) do
    shares = fetch_shares()

    share =
      if !Enum.empty?(shares) do
        Enum.filter(shares, fn share -> share.id === id or share["id"] === id end)
        |> Enum.at(0)
      else
        %{}
      end

    IO.inspect(share, label: "SHARE DETAILS")
    {:reply, {:ok, share}, state}
  end

  def handle_call({:add_access, access}, _from, state) do
    shares =
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
          # NOTE: later this needs to be separate
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
              # "reserved" => %{"private" => reserved_name},
              "reserved" => %{"private" => name},
              "units" => %{"access" => %{"id" => acc_id, "unit" => acc_unit}},
              "enabled" => %{"access" => false}
            }
          }

          updated0 = shares ++ [access_entry]
          :ok = File.write(path(), Jason.encode!(updated0))

          broadcast_shares()

          Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
            type: :info,
            message: "access added successfully"
          })

          new_state = Map.put(state, :shares, updated0)
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
    shares =
      case read_file() do
        {:ok, list} when is_list(list) -> list
        _ -> []
      end

    # We try and add all the shares we had locally
    try do
      if not Enum.empty?(shares) do
        shares
        |> Enum.each(fn s ->
          name = s["name"]
          ip = s["ip"]
          port = s["port"]

          base = sanitize_base(name)
          pub_token = make_token(base, "pub")
          priv_token = make_token(base, "priv")

          Zrok.reserve_public(pub_token, ip, port)
          Zrok.reserve_private(priv_token, ip, port)
        end)
      end
    rescue
      _e ->
        Logger.error("There was a problem setting the shares on the cloud env")
        :error
    end

    {:noreply, state}
  end

  def handle_cast(:hibernate_shares, state) do
    shares =
      case read_file() do
        {:ok, list} when is_list(list) -> list
        _ -> []
      end

    updated_shares =
      Enum.map(shares, fn s ->
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
        {:noreply, Map.put(state, :shares, updated_shares)}

      {:error, _err} ->
        {:noreply, state}
    end
  end

  def handle_cast({:get_share, id}, state) do
    shares = fetch_shares()

    if !Enum.empty?(shares) do
      share =
        Enum.filter(shares, fn share -> share.id === id or share["id"] === id end)
        |> Enum.at(0)

      Phoenix.PubSub.broadcast(Tunneld.PubSub, @broadcast_topic, %{
        id: @component_desktop_id,
        module: @component_module,
        data: share
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
    shares = if data == "", do: [], else: data

    {entry, _kind} =
      Enum.reduce_while(shares, {nil, nil}, fn s, _acc ->
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
              Enum.map(shares, fn s ->
                if s["id"] == entry["id"] do
                  put_in(s, ["tunneld", "enabled", "access"], enable?)
                else
                  s
                end
              end)

            case File.write(path(), Jason.encode!(updated_shares)) do
              :ok ->
                broadcast_shares()
                {:noreply, Map.put(state, :shares, updated_shares)}

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
          Map.put(state, :shares, updated_nodes)

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
    shares = if data == "", do: [], else: data

    {share, kind} =
      Enum.reduce_while(shares, {nil, nil}, fn s, _acc ->
        units = get_in(s, ["tunneld", "units"]) || %{}

        cond do
          get_in(units, ["public", "id"]) == unit_id -> {:halt, {s, "public"}}
          get_in(units, ["private", "id"]) == unit_id -> {:halt, {s, "private"}}
          true -> {:cont, {nil, nil}}
        end
      end)

    case {share, kind} do
      {nil, _} ->
        Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
          type: :error,
          message: "Share for unit not found"
        })

        {:noreply, state}

      {share, kind} ->
        result =
          if enable? do
            Tunneld.Servers.Zrok.enable_share(unit_id)
          else
            Tunneld.Servers.Zrok.disable_share(unit_id)
          end

        case result do
          :ok ->
            updated_shares =
              Enum.map(shares, fn s ->
                if s["id"] == share["id"] do
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
                  |> Enum.find(&(&1["id"] == share["id"]))
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

                {:noreply, Map.put(state, :shares, updated_shares)}

              {:error, err} ->
                Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
                  type: :error,
                  message: "Failed to persist share state: #{inspect(err)}"
                })

                {:noreply, state}
            end

          {:error, err} ->
            Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
              type: :error,
              message:
                "Failed to #{if enable?, do: "enable", else: "disable"} share: #{inspect(err)}"
            })

            {:noreply, state}
        end
    end
  end

  def handle_cast({:update_share, type, data}, state) do
    shares = fetch_shares()

    if !Enum.empty?(shares) do
      share =
        Enum.filter(shares, fn share ->
          share.id === data["id"] or share["id"] === data["id"]
        end)
        |> Enum.at(0)

      updated_shares =
        case type do
          :tunneld ->
            Enum.map(shares, fn a ->
              if a.id === share.id do
                Map.put(a, :tunneld, data)
              else
                a
              end
            end)

          _ ->
            Logger.error("Tried to set settings with an unhandled type")
            shares
        end

      case File.write(path(), Jason.encode!(updated_shares)) do
        :ok ->
          Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
            type: :info,
            message: "Share updated successfully"
          })

          broadcast_shares()

          Phoenix.PubSub.broadcast(
            Tunneld.PubSub,
            "show_details",
            {:show_details, %{"id" => data["id"], "type" => "share"}}
          )

        {:error, err} ->
          Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
            type: :error,
            message: "Failed to update share: #{inspect(err)}"
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
      end

    updated_nodes = Enum.reject(data, fn share -> share["id"] === id end)

    update_state =
      case File.write(path(), Jason.encode!(updated_nodes)) do
        :ok ->
          Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
            type: :info,
            message: "share removed successfully"
          })

          broadcast_shares()

          Phoenix.PubSub.broadcast(Tunneld.PubSub, @broadcast_topic, %{
            id: @component_desktop_id,
            module: @component_module,
            data: %{id: id}
          })

          Map.put(state, :shares, updated_nodes)

        {:error, err} ->
          Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
            type: :error,
            message: "Failed to remove share: #{inspect(err)}"
          })

          state
      end

    {:noreply, update_state}
  end

  def handle_info(:sync, state) do
    shares = broadcast_shares()
    :timer.send_after(@interval, :sync)
    {:noreply, Map.put(state, :shares, shares)}
  end

  defp broadcast_shares() do
    shares = fetch_shares()

    Phoenix.PubSub.broadcast(Tunneld.PubSub, @broadcast_topic_main, %{
      id: "shares",
      module: TunneldWeb.Live.Components.Shares,
      data: shares
    })

    shares
  end

  defp create_reserved_and_units(new_share) do
    name = new_share["name"]
    ip = new_share["ip"]
    port = new_share["port"]

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
    shares = if data == "", do: [], else: data

    Enum.map(shares, fn s ->
      kind = s["kind"] || "host"

      {ip, port} =
        case kind do
          "access" -> parse_bind(s["bind"])
          _ -> {s["ip"], s["port"]}
        end

      %{
        id: s["id"],
        name: s["name"],
        ip: ip,
        description: s["description"],
        port: port,
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
      :ok -> {:ok, "Shares file created"}
      {:error, reason} -> {:error, "Failed to create Shares file: #{inspect(reason)}"}
    end
  end

  def read_file() do
    case path() |> File.read() do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, data} -> {:ok, data}
          {:error, err} -> {:error, "Failed to decode share file: #{inspect(err)}"}
        end

      {:error, reason} ->
        {:error, "There was a problem reading the file: #{inspect(reason)}"}
    end
  end

  def get_enabled_shares(), do: GenServer.call(__MODULE__, :get_enabled_shares, 25_000)
  def get_share(id), do: GenServer.cast(__MODULE__, {:get_share, id})

  def toggle_share(unit_id, enable),
    do: GenServer.cast(__MODULE__, {:toggle_share, unit_id, enable})

  def get_share_details(id), do: GenServer.call(__MODULE__, {:get_share_details, id})
  def add_share(share), do: GenServer.call(__MODULE__, {:add_share, share}, 25_000)
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
  def path(), do: "./" <> config_fs(:root) <> config_fs(:shares)
  defp config_fs(), do: Application.get_env(:tunneld, :fs)
  defp config_fs(key), do: config_fs()[key]
end
