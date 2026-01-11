defmodule Tunneld.Servers.Zrok do
  @moduledoc false
  use GenServer
  require Logger

  @pubsub Tunneld.PubSub
  @topic_notif "notifications"

  @broadcast_topic "component:details"
  @component_desktop_id "sidebar_details"
  @component_module TunneldWeb.Live.Components.Sidebar.Details

  # this is hardcoded but we need to get from the installed path
  @linux_systemd_dir "/etc/systemd/system"
  @unit_prefix "zrok-"
  @unit_suffix ".service"
  @access_prefix "zrok-access-"

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    mock? = Application.get_env(:tunneld, :mock_data, false)

    sdir =
      if mock? do
        Path.join([fs_root(), "zrok", "units"])
      else
        @linux_systemd_dir
      end

    if not mock? do
      :ok = ensure_dir(sdir)
    end

    units = discover_units(sdir, mock?)

    state = %{
      api_endpoint: nil,
      enabled?: false,
      units: units,
      systemd_dir: sdir,
      mock?: mock?
    }

    {:ok, state}
  end

  @impl true
  def handle_cast(:details, state) do
    send(self(), :broadcast_details)
    {:noreply, state}
  end

  @impl true
  def handle_call({:set_api_endpoint, endpoint}, _from, state) do
    case zrok_config_set(endpoint) do
      :ok ->
        send(self(), :broadcast_details)
        notify(:info, "Endpoint to network set")
        {:reply, :ok, %{state | api_endpoint: endpoint}}

      {:error, r} ->
        notify(:error, "Failed to set endpoint")
        {:reply, {:error, r}, state}
    end
  end

  @impl true
  def handle_call(:get_api_endpoint, _from, state) do
    ep =
      case state.api_endpoint do
        nil ->
          case zrok_config_get() do
            {:ok, v} -> v |> String.split(" = ") |> List.last()
            _ -> nil
          end

        v ->
          v
      end

    {:reply, ep, %{state | api_endpoint: ep}}
  end

  # We disable before removing from the network
  def handle_call(:unset_api_endpoint, _from, state) do
    # This might fail but we need to try and do this first - need better checks
    run(zrok_bin(), ["disable"])

    case zrok_config_unset() do
      :ok ->
        send(self(), :broadcast_details)
        notify(:info, "Unset the network endpoint successfully")
        {:reply, :ok, %{state | api_endpoint: nil}}

      {:error, r} ->
        notify(:error, "Failed to unset network endpoint")
        {:reply, {:error, r}, state}
    end
  end

  def handle_call({:enable_env, token}, _from, state) do
    case run(zrok_bin(), ["enable", token]) do
      {_, 0} ->
        send(self(), :broadcast_details)
        notify(:info, "Device enabled successfully to network account")
        {:reply, :ok, %{state | enabled?: true}}

      err ->
        notify(:error, "Failed to enable device on network account")
        {:reply, {:error, err}, state}
    end
  end

  def handle_call(:disable_env, _from, state) do
    case run(zrok_bin(), ["disable"]) do
      {_, 0} ->
        send(self(), :broadcast_details)
        notify(:info, "Environment disabled")
        {:reply, :ok, %{state | enabled?: false}}

      err ->
        notify(:error, "Failed to disable environment")
        {:reply, {:error, err}, state}
    end
  end

  def handle_call({:reserve_public, %{name: name, ip: ip, port: port} = params}, _from, state) do
    basic = params[:auth] || params["auth"] || %{}

    auth_args =
      if (basic["enabled"] == true or basic[:enabled] == true) &&
           (basic["username"] || basic[:username]) && (basic["password"] || basic[:password]) do
        username = basic["username"] || basic[:username]
        password = basic["password"] || basic[:password]
        ["--basic-auth", "#{username}:#{password}"]
      else
        []
      end

    cmd =
      [
           "reserve",
           "public",
           "#{ip}:#{port}",
           "--unique-name",
           name,
           "--open",
           "--backend-mode",
           "proxy"
         ] ++ auth_args

    case run(zrok_bin(), cmd) do
      {_, 0} -> {:reply, :ok, state}
      err -> {:reply, {:error, err}, state}
    end
  end

  def handle_call({:reserve_private, %{name: name, ip: _ip, port: _port}}, _from, state) do
    # --- FIX: Match the Nginx Hashing Logic ---
    # We ignore the passed port and calculate the unique private port based on the Name.
    # This ensures Zrok points to the exact port Nginx is listening on for this specific private share.
    target_port = Tunneld.Servers.Nginx.get_private_port(name)
    target = "127.0.0.1:#{target_port}"

    case run(zrok_bin(), [
           "reserve",
           "private",
           "--unique-name",
           name,
           "--backend-mode",
           "proxy",
           target
         ]) do
      {_, 0} -> {:reply, :ok, state}
      err -> {:reply, {:error, err}, state}
    end
  end

  def handle_call({:release_reserved, name}, _from, state) do
    case run(zrok_bin(), ["release", name]) do
      {_, 0} -> {:reply, :ok, state}
      err -> {:reply, {:error, err}, state}
    end
  end

  def handle_call({:create_share_unit, share_map}, _from, state) do
    with {:ok, {id, unit_name, content}} <- build_unit(share_map, state),
         :ok <- write_unit(state.systemd_dir, unit_name, content),
         :ok <- daemon_reload(state) do
      units = Map.put(state.units, id, %{unit: unit_name, id: id})
      notify(:info, "Unit created: #{unit_name}")
      {:reply, {:ok, %{id: id, unit: unit_name}}, %{state | units: units}}
    else
      {:error, reason} ->
        notify(:error, "Failed to create unit")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:enable_share, id}, _from, state) do
    case Map.fetch(state.units, id) do
      {:ok, %{unit: unit}} ->
        case do_enable(unit, state) do
          :ok ->
            notify(:info, "Resource enabled: #{id}")
            {:reply, :ok, state}

          {:error, r} ->
            notify(:error, "Failed to enable resource: #{id}")
            {:reply, {:error, r}, state}
        end

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:disable_share, id}, _from, state) do
    case Map.fetch(state.units, id) do
      {:ok, %{unit: unit}} ->
        case do_disable(unit, state) do
          :ok ->
            notify(:info, "Resource disabled: #{id}")
            {:reply, :ok, state}

          {:error, r} ->
            notify(:error, "Failed to disable resource: #{id}")
            {:reply, {:error, r}, state}
        end

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:remove_share, id}, _from, state) do
    case Map.fetch(state.units, id) do
      {:ok, %{unit: unit}} ->
        _ = do_disable(unit, state)

        case File.rm(unit_path(state.systemd_dir, unit)) do
          :ok ->
            _ = daemon_reload(state)
            notify(:info, "Resource removed: #{id}")
            {:reply, :ok, %{state | units: Map.delete(state.units, id)}}

          {:error, r} ->
            notify(:error, "Failed to remove service file: #{unit}")
            {:reply, {:error, r}, state}
        end

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:status, id}, _from, state) do
    case Map.fetch(state.units, id) do
      {:ok, %{unit: unit}} -> {:reply, {:ok, unit_status(unit, state)}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:list, _from, state) do
    items =
      Enum.map(state.units, fn {id, %{unit: unit}} ->
        %{id: id, unit: unit, active: unit_active?(unit, state)}
      end)

    {:reply, {:ok, items}, state}
  end

  def handle_call({:create_access_unit, access_map}, _from, state) do
    with {:ok, {id, unit_name, content}} <- build_access_unit(access_map, state),
         :ok <- write_unit(state.systemd_dir, unit_name, content),
         :ok <- daemon_reload(state) do
      units = Map.put(state.units, id, %{unit: unit_name, id: id})
      notify(:info, "Unit created: #{unit_name}")
      {:reply, {:ok, %{id: id, unit: unit_name}}, %{state | units: units}}
    else
      {:error, reason} ->
        notify(:error, "Failed to create access unit")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:enable_access, id}, _from, state) do
    case Map.fetch(state.units, id) do
      {:ok, %{unit: unit}} ->
        case do_enable(unit, state) do
          :ok ->
            notify(:info, "Access enabled: #{id}")
            {:reply, :ok, state}

          {:error, r} ->
            notify(:error, "Failed to enable access: #{id}")
            {:reply, {:error, r}, state}
        end

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:disable_access, id}, _from, state) do
    case Map.fetch(state.units, id) do
      {:ok, %{unit: unit}} ->
        case do_disable(unit, state) do
          :ok ->
            notify(:info, "Access disabled: #{id}")
            {:reply, :ok, state}

          {:error, r} ->
            notify(:error, "Failed to disable access: #{id}")
            {:reply, {:error, r}, state}
        end

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:remove_access, id}, _from, state) do
    case Map.fetch(state.units, id) do
      {:ok, %{unit: unit}} ->
        _ = do_disable(unit, state)

        case File.rm(unit_path(state.systemd_dir, unit)) do
          :ok ->
            _ = daemon_reload(state)
            notify(:info, "Access removed: #{id}")
            {:reply, :ok, %{state | units: Map.delete(state.units, id)}}

          {:error, r} ->
            notify(:error, "Failed to remove access service file: #{unit}")
            {:reply, {:error, r}, state}
        end

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_info(:broadcast_details, state) do
    enabled = zrok_enabled?()

    endpoint =
      case zrok_config_get() do
        {:ok, ep} -> ep |> String.split(" = ") |> Enum.at(1)
        _ -> nil
      end

    Phoenix.PubSub.broadcast(Tunneld.PubSub, @broadcast_topic, %{
      id: @component_desktop_id,
      module: @component_module,
      data: %{
        enabled?: enabled,
        api_endpoint: endpoint || false
      }
    })

    {:noreply, state}
  end

  defp zrok_enabled?() do
    case run(zrok_bin(), ["status"]) do
      {out, 0} ->
        # look for definitive keywords in the output
        String.contains?(out, "enabled") or String.contains?(out, "logged in") or
          String.contains?(out, "Environment")

      _ ->
        false
    end
  end

  defp zrok_config_set(endpoint) do
    case run(zrok_bin(), ["config", "set", "apiEndpoint", endpoint]) do
      {_, 0} -> :ok
      err -> {:error, err}
    end
  end

  defp zrok_config_get() do
    case run(zrok_bin(), ["config", "get", "apiEndpoint"]) do
      {out, 0} ->
        {:ok,
         out
         |> String.trim()
         |> case do
           "" -> nil
           v -> v
         end}

      err ->
        {:error, err}
    end
  end

  defp zrok_config_unset() do
    case run(zrok_bin(), ["config", "unset", "apiEndpoint"]) do
      {_, 0} -> :ok
      err -> {:error, err}
    end
  end

  defp zrok_bin() do
    System.find_executable("zrok") || "zrok"
  end

  defp build_access_unit(access, _state) do
    id = normalize_id(access["id"] || access[:id])
    name = access["name"] || access[:name] || id

    reserved = to_string(access["reserved_name"] || access[:reserved_name] || name)
    bind = to_string(access["bind"] || access[:bind])

    cpu_q =
      access["cpu_quota"] || access[:cpu_quota] || 40

    cpu_quota =
      cpu_q
      |> then(&max(5, min(&1, 90)))
      |> Integer.to_string()
      |> Kernel.<>("%")

    exec =
      [zrok_bin(), "access", "private", reserved, "-b", bind, "--headless", "--template-path", Path.join(fs_root(), "error.gohtml")]
      |> Enum.map(&to_string/1)
      |> Enum.join(" ")

    unit_name = @access_prefix <> id <> @unit_suffix

    unit =
      [
        "[Unit]",
        "Description=Zrok Access (#{name})",
        "Wants=network-online.target tunneld.service",
        "After=network-online.target tunneld.service",
        "",
        "[Service]",
        "Type=simple",
        "User=root",
        "ExecStart=/bin/sh -lc \"#{exec}\"",
        "Restart=always",
        "RestartSec=3s",
        "CPUQuota=#{cpu_quota}",
        "KillMode=control-group",
        "TimeoutStopSec=15s",
        "",
        "[Install]",
        "WantedBy=multi-user.target"
      ]
      |> Enum.join("\n")

    {:ok, {id, unit_name, unit}}
  end

  defp build_unit(resource, _state) do
    id = normalize_id(resource["id"] || resource[:id])
    name = resource["name"] || resource[:name] || id
    tun = resource["tunneld"] || resource[:tunneld] || %{}
    reserved_token = to_string(tun["reserved_token"] || tun[:reserved_token] || name)

    exec =
      [zrok_bin(), "share", "reserved", reserved_token, "--headless"]
      |> Enum.map(&to_string/1)
      |> Enum.join(" ")

    unit_name = @unit_prefix <> id <> @unit_suffix

    unit =
      [
        "[Unit]",
        "Description=Zrok Resource (#{name})",
        "Wants=network-online.target tunneld.service",
        "After=network-online.target tunneld.service",
        "StartLimitIntervalSec=60",
        "StartLimitBurst=5",
        "",
        "[Service]",
        "Type=simple",
        "User=root",
        "Environment=GOMEMLIMIT=80MiB",
        "Environment=GOGC=70",
        "Environment=GOMAXPROCS=1",
        "ExecStart=/bin/sh -c \"#{exec}\"",
        "Restart=always",
        "RestartSec=3s",
        "MemoryHigh=80M",
        "MemoryMax=96M",
        "MemorySwapMax=0",
        "CPUQuota=35%",
        "TasksMax=128",
        "LimitNOFILE=65535",
        "KillMode=mixed",
        "KillSignal=SIGTERM",
        "TimeoutStopSec=15s",
        "StandardOutput=journal",
        "StandardError=journal",
        "",
        "[Install]",
        "WantedBy=multi-user.target"
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    {:ok, {id, unit_name, unit}}
  end

  defp write_unit(dir, unit_name, content) do
    ensure_dir(dir)

    case File.write(unit_path(dir, unit_name), content, [:write]) do
      :ok -> :ok
      {:error, r} -> {:error, r}
    end
  end

  defp daemon_reload(%{mock?: true}), do: :ok
  defp daemon_reload(_), do: systemctl(["daemon-reload"])
  defp unit_path(dir, unit), do: Path.join(dir, unit)

  defp unit_active?(unit, %{mock?: true, systemd_dir: dir} = _state) do
    marker = Path.join(dir, unit <> ".enabled")

    case File.exists?(marker) do
      true ->
        case parse_ip_port_from_unit(Path.join(dir, unit)) do
          {ip, port} -> port_open?(ip, port)
          :unknown -> true
        end

      false ->
        false
    end
  end

  defp unit_active?(unit, _state) do
    case run("systemctl", ["is-active", unit]) do
      {"active\n", 0} -> true
      _ -> false
    end
  end

  defp unit_status(unit, %{mock?: true} = state) do
    active = unit_active?(unit, state)

    %{
      unit: unit,
      active: active,
      status: if(active, do: "active (mock)", else: "inactive (mock)")
    }
  end

  defp unit_status(unit, state) do
    active = unit_active?(unit, state)
    {out, _} = run("systemctl", ["status", unit, "--no-pager"])
    %{unit: unit, active: active, status: out}
  end

  defp do_enable(unit, %{mock?: true, systemd_dir: dir}) do
    marker = Path.join(dir, unit <> ".enabled")

    case File.write(marker, "1") do
      :ok -> :ok
      {:error, r} -> {:error, r}
    end
  end

  defp do_enable(unit, _state) do
    with :ok <- systemctl(["enable", unit]),
         :ok <- systemctl(["start", unit]) do
      :ok
    else
      {:error, r} -> {:error, r}
    end
  end

  defp do_disable(unit, %{mock?: true, systemd_dir: dir}) do
    marker = Path.join(dir, unit <> ".enabled")
    _ = File.rm(marker)
    :ok
  end

  defp do_disable(unit, _state) do
    with :ok <- systemctl(["stop", unit]),
         :ok <- systemctl(["disable", unit]) do
      :ok
    else
      {:error, r} -> {:error, r}
    end
  end

  defp systemctl(args) when is_list(args) do
    case run("systemctl", args) do
      {_, 0} -> :ok
      err -> {:error, err}
    end
  end

  defp run(cmd, args) do
    try do
      System.cmd(cmd, args, stderr_to_stdout: true, into: "")
    rescue
      e -> {:error, e}
    end
  end

  defp normalize_id(nil), do: to_string(System.system_time(:second))

  defp normalize_id(id) when is_binary(id) do
    id
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\-]/, "-")
    |> String.trim("-")
    |> case do
      "" -> to_string(System.system_time(:second))
      v -> v
    end
  end

  defp discover_units(dir, mock?) do
    list = discover_units_list(%{systemd_dir: dir, mock?: mock?})
    Map.new(list, fn %{id: id, unit: unit} -> {id, %{unit: unit, id: id}} end)
  end

  defp discover_units_list(%{systemd_dir: dir} = state) do
    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.starts_with?(&1, @unit_prefix))
        |> Enum.filter(&String.ends_with?(&1, @unit_suffix))
        |> Enum.map(fn unit ->
          id = discover_unit_id(dir, unit)

          %{id: id, unit: unit, active: unit_active?(unit, state)}
        end)

      _ ->
        []
    end
  end

  defp discover_unit_id(dir, unit) do
    base =
      unit
      |> String.replace_suffix(@unit_suffix, "")

    if String.starts_with?(base, @access_prefix) do
      # If a *share* is ever created with an id like "access-foo", its unit name
      # becomes "zrok-access-foo.service" and would be ambiguous. Disambiguate
      # by reading the unit content when possible.
      case File.read(Path.join(dir, unit)) do
        {:ok, content} ->
          if String.contains?(content, "Description=Zrok Access") or
               String.contains?(content, "zrok access private") do
            String.replace_prefix(base, @access_prefix, "")
          else
            String.replace_prefix(base, @unit_prefix, "")
          end

        _ ->
          String.replace_prefix(base, @access_prefix, "")
      end
    else
      String.replace_prefix(base, @unit_prefix, "")
    end
  end

  defp parse_ip_port_from_unit(path) do
    with {:ok, content} <- File.read(path),
         [exec_line] <-
           Regex.run(~r/^ExecStart=.*?zrok.*?(?<host>\d+\.\d+\.\d+\.\d+):(?<port>\d+)/m, content,
             capture: :all_but_first
           ),
         [host, port] <-
           Regex.run(~r/(\d+\.\d+\.\d+\.\d+):(\d+)/, exec_line, capture: :all_but_first) do
      {host, String.to_integer(port)}
    else
      _ -> :unknown
    end
  end

  defp port_open?(ip, port) do
    case :gen_tcp.connect(String.to_charlist(ip), port, [:binary, active: false], 1500) do
      {:ok, sock} ->
        :gen_tcp.close(sock)
        true

      _ ->
        false
    end
  end

  defp ensure_dir(dir) do
    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, :eexist} -> :ok
      {:error, r} -> {:error, r}
    end
  end

  defp fs_root() do
    case Application.get_env(:tunneld, :fs) do
      nil -> "/var/lib/tunneld"
      kw when is_list(kw) -> Keyword.get(kw, :root, "/var/lib/tunneld")
      map when is_map(map) -> Map.get(map, :root) || Map.get(map, "root") || "/var/lib/tunneld"
      bin when is_binary(bin) -> bin
    end
  end

  defp notify(type, message) do
    Phoenix.PubSub.broadcast(@pubsub, @topic_notif, %{type: type, message: message})
  end

  def set_api_endpoint(endpoint),
    do: GenServer.call(__MODULE__, {:set_api_endpoint, endpoint}, 30_000)

  def get_api_endpoint(), do: GenServer.call(__MODULE__, :get_api_endpoint, 15_000)
  def unset_api_endpoint(), do: GenServer.call(__MODULE__, :unset_api_endpoint, 30_000)

  def enable_env(account_token),
    do: GenServer.call(__MODULE__, {:enable_env, account_token}, 60_000)

  def disable_env(), do: GenServer.call(__MODULE__, :disable_env, 60_000)

  def reserve_public(name, ip, port, auth \\ %{}),
    do: GenServer.call(__MODULE__, {:reserve_public, %{name: name, ip: ip, port: port, auth: auth}}, 30_000)

  def reserve_private(name, ip, port),
    do: GenServer.call(__MODULE__, {:reserve_private, %{name: name, ip: ip, port: port}}, 30_000)

  def release_reserved(name), do: GenServer.call(__MODULE__, {:release_reserved, name}, 30_000)

  def create_share_unit(share_map),
    do: GenServer.call(__MODULE__, {:create_share_unit, share_map}, 30_000)

  def enable_share(id), do: GenServer.call(__MODULE__, {:enable_share, id}, 30_000)
  def disable_share(id), do: GenServer.call(__MODULE__, {:disable_share, id}, 30_000)
  def remove_share(id), do: GenServer.call(__MODULE__, {:remove_share, id}, 30_000)
  def list(), do: GenServer.call(__MODULE__, :list, 15_000)
  def get_details(), do: GenServer.cast(__MODULE__, :details)

  def create_access_unit(access_map),
    do: GenServer.call(__MODULE__, {:create_access_unit, access_map}, 30_000)

  def enable_access(id), do: GenServer.call(__MODULE__, {:enable_access, id}, 30_000)
  def disable_access(id), do: GenServer.call(__MODULE__, {:disable_access, id}, 30_000)
  def remove_access(id), do: GenServer.call(__MODULE__, {:remove_access, id}, 30_000)
end
