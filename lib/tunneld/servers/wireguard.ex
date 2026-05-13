defmodule Tunneld.Servers.Wireguard do
  @moduledoc """
  Manages the node's WireGuard keypair and wg-mesh interface.
  """

  use GenServer
  require Logger


  @interface "wg-mesh"

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def get_public_key, do: GenServer.call(__MODULE__, :get_public_key)
  def get_state, do: GenServer.call(__MODULE__, :get_state)
  def reset, do: GenServer.call(__MODULE__, :reset)

  def add_mesh_peer(pubkey, endpoint, allowed_ips),
    do: GenServer.call(__MODULE__, {:add_mesh_peer, pubkey, endpoint, allowed_ips}, 15_000)

  def remove_mesh_peer(pubkey),
    do: GenServer.call(__MODULE__, {:remove_mesh_peer, pubkey}, 15_000)

  def list_mesh_peers, do: GenServer.call(__MODULE__, :list_mesh_peers)

  def generate_keypair do
    if mock?() do
      private_key = :crypto.strong_rand_bytes(32) |> Base.encode64()
      public_key = :crypto.strong_rand_bytes(32) |> Base.encode64()
      {:ok, private_key, public_key}
    else
      case exec("wg", ["genkey"]) do
        {private_key, 0} ->
          private_key = String.trim(private_key)
          key_path = write_private_key_temp(private_key)

          result =
            case exec("sh", ["-c", "wg pubkey < #{key_path}"]) do
              {public_key, 0} ->
                {:ok, private_key, String.trim(public_key)}

              {out, code} ->
                {:error, "wg pubkey failed (#{code}): #{out}"}
            end

          File.rm(key_path)
          result

        {out, code} ->
          {:error, "wg genkey failed (#{code}): #{out}"}
      end
    end
  end

  @impl true
  def init(_) do
    state =
      case read_file() do
        {:ok, data} ->
          data
          |> Map.put("mock?", mock?())

        _ ->
          initial_state()
      end

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  @impl true
  def handle_call(:reset, _from, _state) do
    new_state = initial_state()
    persist(new_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_public_key, _from, state) do
    {:reply, state["public_key"], state}
  end

  @impl true
  def handle_call({:add_mesh_peer, pubkey, endpoint, allowed_ips}, _from, state) do
    case do_add_mesh_peer(pubkey, endpoint, allowed_ips) do
      :ok -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:remove_mesh_peer, pubkey}, _from, state) do
    case do_remove_mesh_peer(pubkey) do
      :ok -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:list_mesh_peers, _from, state) do
    peers = do_list_mesh_peers()
    {:reply, peers, state}
  end

  @impl true
  def handle_call({:assign_mesh_ip, mesh_ip}, _from, state) do
    case do_assign_mesh_ip(mesh_ip) do
      :ok -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:set_state, new_state}, _from, _state) do
    persist(new_state)
    {:reply, :ok, new_state}
  end

  def ensure_keypair do
    state = get_state()

    case {state["private_key"], state["public_key"]} do
      {nil, nil} ->
        {:ok, priv, pub} = generate_keypair()
        new_state = Map.merge(state, %{"private_key" => priv, "public_key" => pub})
        GenServer.call(__MODULE__, {:set_state, new_state})
        :ok

      _ ->
        :ok
    end
  end

  def bring_up_mesh do
    state = get_state()
    private_key = state["private_key"]

    if is_nil(private_key) do
      {:error, :no_keypair}
    else
      do_bring_up_mesh(private_key)
    end
  end

  def bring_down_mesh do
    do_bring_down_mesh()
  end

  def assign_mesh_ip(mesh_ip) do
    GenServer.call(__MODULE__, {:assign_mesh_ip, mesh_ip}, 15_000)
  end

  defp do_bring_up_mesh(private_key) do
    if mock?() do
      Logger.debug("[WireGuard MOCK] Bringing up #{@interface}")
      :ok
    else
      exec("ip", ["link", "del", @interface])
      key_path = write_private_key_temp(private_key)

      result =
        with {_, 0} <- exec("ip", ["link", "add", @interface, "type", "wireguard"]),
             {_, 0} <- exec("wg", ["set", @interface, "private-key", key_path]),
             {_, 0} <- exec("ip", ["link", "set", @interface, "mtu", "1280"]),
             {_, 0} <- exec("ip", ["link", "set", @interface, "up"]) do
          :ok
        else
          {out, code} ->
            exec("ip", ["link", "del", @interface])
            {:error, "Command failed (#{code}): #{out}"}
        end

      File.rm(key_path)
      result
    end
  end

  defp do_bring_down_mesh do
    if mock?() do
      Logger.debug("[WireGuard MOCK] Bringing down #{@interface}")
      :ok
    else
      case exec("ip", ["link", "del", @interface]) do
        {_, 0} -> :ok
        {out, code} -> {:error, "Command failed (#{code}): #{out}"}
      end
    end
  end

  defp do_assign_mesh_ip(mesh_ip) do
    if mock?() do
      Logger.debug("[WireGuard MOCK] Assigning IP #{mesh_ip} to #{@interface}")
      :ok
    else
      case exec("ip", ["address", "add", mesh_ip <> "/32", "dev", @interface]) do
        {_, 0} -> :ok
        {out, code} -> {:error, "Command failed (#{code}): #{out}"}
      end
    end
  end

  defp do_add_mesh_peer(pubkey, endpoint, allowed_ips) do
    ips = Enum.join(allowed_ips, ",")

    if mock?() do
      Logger.debug("[WireGuard MOCK] Adding peer #{pubkey} at #{endpoint} allowed-ips #{ips}")
      :ok
    else
      args = ["set", @interface, "peer", pubkey, "allowed-ips", ips]

      args =
        if endpoint do
          args ++ ["endpoint", endpoint, "persistent-keepalive", "25"]
        else
          args
        end

      case exec("wg", args) do
        {_, 0} ->
          # Explicitly install routes for each allowed-ip range
          for ip_range <- allowed_ips do
            System.cmd("ip", ["route", "add", ip_range, "dev", @interface],
              stderr_to_stdout: true
            )
          end

          :ok

        {out, code} ->
          {:error, "Command failed (#{code}): #{out}"}
      end
    end
  end

  defp do_remove_mesh_peer(pubkey) do
    if mock?() do
      Logger.debug("[WireGuard MOCK] Removing peer #{pubkey}")
      :ok
    else
      case exec("wg", ["set", @interface, "peer", pubkey, "remove"]) do
        {_, 0} -> :ok
        {out, code} -> {:error, "Command failed (#{code}): #{out}"}
      end
    end
  end

  defp do_list_mesh_peers do
    if mock?() do
      []
    else
      case exec("wg", ["show", @interface, "peers"]) do
        {out, 0} ->
          out
          |> String.trim()
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        _ ->
          []
      end
    end
  end

  defp write_private_key_temp(private_key) do
    path = Path.join(System.tmp_dir!(), "wg_mesh_pk_#{:erlang.unique_integer([:positive])}")
    File.write!(path, private_key)
    File.chmod!(path, 0o600)
    path
  end

  defp exec(cmd, args) do
    if mock?() do
      Logger.debug("[WireGuard MOCK] #{cmd} #{Enum.join(args, " ")}")
      {"", 0}
    else
      System.cmd(cmd, args, stderr_to_stdout: true)
    end
  end

  defp mock?, do: Application.get_env(:tunneld, :mock_data, false)

  defp path do
    root = Tunneld.Config.fs(:root)
    wireguard = Tunneld.Config.fs(:wireguard)
    if root && wireguard, do: Path.join(root, wireguard), else: nil
  end

  defp read_file do
    case path() do
      p when is_binary(p) -> Tunneld.Persistence.read_json(p)
      _ -> {:error, :no_path_configured}
    end
  end

  defp persist(state) do
    state
    |> Map.drop(["mock?"])
    |> write_file()
  end

  defp write_file(data) do
    case path() do
      p when is_binary(p) -> Tunneld.Persistence.write_json(p, data)
      _ -> {:error, :no_path_configured}
    end
  end

  defp initial_state do
    %{
      "public_key" => nil,
      "private_key" => nil,
      "mock?" => mock?()
    }
  end
end
