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

    updated_state =
      if is_nil(exists) do
        new_share =
          share
          |> Map.merge(%{
            "id" => DateTime.utc_now() |> DateTime.to_unix() |> to_string,
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

    {:reply, updated_state, updated_state}
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

    {:reply, {:ok, share}, state}
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
    victim = Enum.find(data, fn s -> s["id"] === id end)

    _ =
      if victim do
        tunneld = victim["tunneld"] || %{}
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

  def fetch_shares() do
    {_status, data} = read_file()
    shares = if data == "", do: [], else: data

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
  def get_share_details(id), do: GenServer.call(__MODULE__, {:get_share_details, id})
  def add_share(share), do: GenServer.call(__MODULE__, {:add_share, share}, 25_000)
  def remove_share(id), do: GenServer.cast(__MODULE__, {:remove_share, id})

  def update_share(data, :tunneld),
    do: GenServer.cast(__MODULE__, {:update_share, :tunneld, data})

  def file_exists?(), do: File.exists?(path())
  def path(), do: "./" <> config_fs(:root) <> config_fs(:shares)
  defp config_fs(), do: Application.get_env(:tunneld, :fs)
  defp config_fs(key), do: config_fs()[key]
end
