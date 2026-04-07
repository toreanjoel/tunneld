defmodule Tunneld.Servers.Zrok do
  @moduledoc """
  Manages the Zrok v2 / OpenZiti overlay network integration.

  Handles the full lifecycle of Zrok tunnel shares and access points:

  - **Configuration**: Setting/unsetting the Zrok API endpoint (control plane URL)
  - **Environment**: Enabling/disabling the device on a Zrok account
  - **Names**: Creating and deleting reserved public names (`zrok2 create name`)
  - **Shares**: Creating, enabling, disabling, and removing systemd service units
    that run `zrok2 share public/private` for each resource
  - **Access**: Creating, enabling, disabling, and removing systemd service units
    that run `zrok2 access private` for consuming remote shares

  In production, this module manages real systemd unit files under `/etc/systemd/system/`.
  In mock mode (`MOCK_DATA=true`), unit files are written to the local data directory
  and `.enabled` marker files simulate systemd enable/disable.
  """
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
        Path.join([fs_root(), "zrok2", "units"])
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

  def handle_call({:create_public_name, %{name: name}}, _from, state) do
    # Clean up any stale active share using this name before creating/verifying
    # the name reservation. A crashed share process leaves the session active on
    # the controller, causing subsequent `zrok2 share public -n public:NAME` to
    # fail with 409 shareConflict.
    cleanup_active_share_for_name(name)

    case run(zrok_bin(), ["create", "name", "-n", "public", name]) do
      {_, 0} ->
        {:reply, :ok, state}

      {out, _code} ->
        # Idempotent: zrok2 returns HTTP 409 when the name already exists
        if String.contains?(out, "409") or String.contains?(out, "already exists") do
          {:reply, :ok, state}
        else
          {:reply, {:error, {out, 1}}, state}
        end
    end
  end

  def handle_call({:create_private_name, %{name: _name}}, _from, state) do
    # No-op: private shares are ephemeral — zrok2 assigns a token at startup.
    {:reply, :ok, state}
  end

  def handle_call({:get_share_token, _unit_name}, _from, %{mock?: true} = state) do
    {:reply, {:ok, nil}, state}
  end

  def handle_call({:get_share_token, unit_name}, _from, state) do
    # Read the unit's journal to extract the private share token
    case run("journalctl", ["-u", unit_name, "--no-pager", "-n", "50", "--output", "cat"]) do
      {out, 0} ->
        token =
          case Regex.run(~r/zrok2 access private ([a-z0-9]+)/, out) do
            [_, t] -> t
            _ -> nil
          end

        {:reply, {:ok, token}, state}

      _ ->
        {:reply, {:ok, nil}, state}
    end
  end

  def handle_call({:delete_name, name}, _from, state) do
    # Must clean up any active share first — zrok2 refuses to delete a name
    # that has a live share session attached to it.
    cleanup_active_share_for_name(name)

    case run(zrok_bin(), ["delete", "name", name]) do
      {_, 0} -> {:reply, :ok, state}
      err -> {:reply, {:error, err}, state}
    end
  end

  def handle_call({:cleanup_share_by_name, name}, _from, state) do
    cleanup_active_share_for_name(name)
    {:reply, :ok, state}
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
        # Clean up any stale share session on the controller before starting,
        # otherwise zrok2 returns 409 shareConflict
        unit_path = Path.join(state.systemd_dir, unit)
        cleanup_stale_share_from_unit(unit_path)

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
    System.find_executable("zrok2") || "zrok2"
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
      [zrok_bin(), "access", "private", reserved, "-b", bind, "--headless"]
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

    share_type = to_string(tun["share_type"] || tun[:share_type] || "public")
    share_name = to_string(tun["share_name"] || tun[:share_name] || name)
    target = to_string(tun["target"] || tun[:target] || "127.0.0.1:18000")

    # Build auth args for public shares
    auth = tun["auth"] || tun[:auth] || %{}
    basic = auth["basic"] || auth[:basic] || %{}

    auth_args =
      if share_type == "public" &&
           (basic["enabled"] == true or basic[:enabled] == true) &&
           (basic["username"] || basic[:username]) && (basic["password"] || basic[:password]) do
        username = basic["username"] || basic[:username]
        password = basic["password"] || basic[:password]
        ["--basic-auth", "#{username}:#{password}"]
      else
        []
      end

    # In zrok v2:
    #   Public:  zrok2 share public <target> -n public:<name> --headless --backend-mode proxy
    #   Private: zrok2 share private <target> --share-token <name> --headless --backend-mode proxy
    exec_args =
      case share_type do
        "public" ->
          ["share", "public", target, "-n", "public:#{share_name}", "--headless", "--backend-mode", "proxy"] ++ auth_args

        "private" ->
          ["share", "private", target, "--headless", "--backend-mode", "proxy"]
      end

    # Use the resolved absolute path so systemd (which has no login PATH) can find the binary
    bin = System.find_executable("zrok2") || "/usr/local/bin/zrok2"

    exec =
      ([bin] ++ exec_args)
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
        "Environment=HOME=/root",
        "Environment=GOMEMLIMIT=80MiB",
        "Environment=GOGC=15",
        "Environment=GOMAXPROCS=1",
        "ExecStart=/bin/sh -lc \"#{exec}\"",
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
         :ok <- systemctl(["start", "--no-block", unit]) do
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

  # Queries `zrok2 overview` to find any active share session using the given
  # public name, then deletes it. This handles two cases:
  #   1. A crashed share process that left a stale session on the controller
  #   2. Pre-deletion cleanup (zrok2 refuses to delete a name with an active share)
  # Runs best-effort — failures are logged but not propagated.
  defp cleanup_active_share_for_name(name) do
    case run(zrok_bin(), ["overview", "--json"]) do
      {json, 0} ->
        case Jason.decode(json) do
          {:ok, overview} ->
            # Get share tokens from the names section
            # Names have: "name", "shareToken", "namespaceName", etc.
            name_tokens =
              (overview["names"] || [])
              |> Enum.filter(fn n -> n["name"] == name end)
              |> Enum.map(fn n -> n["shareToken"] end)
              |> Enum.reject(&is_nil/1)

            # Get share tokens from environment shares by checking frontendEndpoints
            # Shares have: "shareToken", "frontendEndpoints" (list), "shareMode", etc.
            env_tokens =
              (overview["environments"] || [])
              |> Enum.flat_map(fn env -> env["shares"] || [] end)
              |> Enum.filter(fn s ->
                endpoints = s["frontendEndpoints"] || []

                Enum.any?(endpoints, fn ep ->
                  String.contains?(ep, name)
                end)
              end)
              |> Enum.map(fn s -> s["shareToken"] end)
              |> Enum.reject(&is_nil/1)

            tokens = Enum.uniq(name_tokens ++ env_tokens)

            Enum.each(tokens, fn token ->
              Logger.info("Cleaning up share for '#{name}' (token: #{token})")
              run(zrok_bin(), ["delete", "share", token])
            end)

          _ ->
            :ok
        end

      _ ->
        :ok
    end
  end

  # Reads a unit file and cleans up any stale share on the controller
  # that would cause a 409 shareConflict on start.
  defp cleanup_stale_share_from_unit(unit_path) do
    with {:ok, content} <- File.read(unit_path) do
      # Public shares: extract name from "-n public:<name>"
      case Regex.run(~r/-n\s+public:(\S+)/, content) do
        [_, name] ->
          cleanup_active_share_for_name(name)

        _ ->
          :ok
      end
    else
      _ -> :ok
    end
  end

  defp ensure_dir(dir) do
    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, :eexist} -> :ok
      {:error, r} -> {:error, r}
    end
  end

  defp fs_root(), do: Tunneld.Config.fs_root()

  defp notify(type, message) do
    Phoenix.PubSub.broadcast(@pubsub, @topic_notif, %{type: type, message: message})
  end

  def set_api_endpoint(endpoint),
    do: GenServer.call(__MODULE__, {:set_api_endpoint, endpoint}, 30_000)

  def get_api_endpoint(), do: GenServer.call(__MODULE__, :get_api_endpoint, 15_000)

  def get_root_domain do
    case get_api_endpoint() do
      url when is_binary(url) and url not in ["<unset>", "", nil] ->
        case URI.parse(url).host do
          nil -> {:error, :no_host}
          host ->
            domain = if String.starts_with?(host, "zrok."),
              do: String.replace_prefix(host, "zrok.", ""),
              else: host
            {:ok, domain}
        end
      _ -> {:error, :unset}
    end
  end

  def unset_api_endpoint(), do: GenServer.call(__MODULE__, :unset_api_endpoint, 30_000)

  def enable_env(account_token),
    do: GenServer.call(__MODULE__, {:enable_env, account_token}, 60_000)

  def disable_env(), do: GenServer.call(__MODULE__, :disable_env, 60_000)

  def create_public_name(name),
    do: GenServer.call(__MODULE__, {:create_public_name, %{name: name}}, 30_000)

  def create_private_name(name),
    do: GenServer.call(__MODULE__, {:create_private_name, %{name: name}}, 30_000)

  def delete_name(name), do: GenServer.call(__MODULE__, {:delete_name, name}, 30_000)

  def get_share_token(unit_name),
    do: GenServer.call(__MODULE__, {:get_share_token, unit_name}, 15_000)

  def cleanup_share_by_name(name),
    do: GenServer.call(__MODULE__, {:cleanup_share_by_name, name}, 30_000)

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
