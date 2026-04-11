defmodule Tunneld.Servers.Dns do
  @moduledoc """
  Manages DNS provider selection for dnscrypt-proxy.

  Reads and writes the `server_names` field in the dnscrypt-proxy TOML
  configuration. When the provider is changed, the service is restarted
  and verified. If verification fails, the change is rolled back
  automatically.

  Available providers come from the `public-resolvers` source list that
  the installer configures in the TOML file.
  """

  use GenServer
  require Logger

  @default_provider "mullvad-doh"

  @providers [
    {"mullvad-doh", "Mullvad DoH"},
    {"cloudflare", "Cloudflare"},
    {"quad9-dnscrypt-ip4-filter-pri", "Quad9 (Security)"},
    {"quad9-dnscrypt-ip4-nofilter-pri", "Quad9 (Unfiltered)"},
    {"adguard-dns", "AdGuard DNS"},
    {"cleanbrowsing-family", "CleanBrowsing (Family)"}
  ]

  @service "dnscrypt-proxy"
  @poll_interval 2_000
  @max_poll_attempts 15

  # --- Client API ---

  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc "Returns the current DNS state (provider, label, status)."
  def get_state, do: GenServer.call(__MODULE__, :get_state)

  @doc "Returns the list of available providers as `{id, label}` tuples."
  def providers, do: @providers

  @doc "Returns the TOML config file path from application config."
  def toml_path do
    Tunneld.Config.fs(:dnscrypt_toml) || "/etc/tunneld/dnscrypt/dnscrypt-proxy.toml"
  end

  @doc """
  Change the DNS provider.

  Validates the provider, updates the TOML config, restarts dnscrypt-proxy,
  and verifies the service comes back up. If verification fails, rolls back
  to the previous config and returns an error.

  This is a synchronous call that may take up to 30 seconds during
  verification. It is intended to be called from an async Task (via
  `Dashboard.Actions`), not directly from a LiveView process.
  """
  def set_provider(provider) do
    GenServer.call(__MODULE__, {:set_provider, provider}, 60_000)
  end

  @doc "Returns the human-readable label for a provider ID."
  def label_for(provider_id) do
    case Enum.find(@providers, fn {id, _} -> id == provider_id end) do
      {_, label} -> label
      nil -> provider_id
    end
  end

  # --- Server Callbacks ---

  @impl true
  def init(_) do
    provider = if mock?(), do: @default_provider, else: read_provider_from_toml()
    {:ok, %{"provider" => provider, "status" => :active}}
  end

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  @impl true
  def handle_call({:set_provider, provider}, _from, state) do
    current = state["provider"]

    cond do
      provider == current ->
        {:reply, {:ok, current}, state}

      not valid_provider?(provider) ->
        {:reply, {:error, :invalid_provider}, state}

      true ->
        result =
          if mock?() do
            Process.sleep(1_000)
            {:ok, provider}
          else
            apply_provider_change(provider, current)
          end

        case result do
          {:ok, new_provider} ->
            new_state = %{"provider" => new_provider, "status" => :active}
            broadcast(new_state)
            {:reply, {:ok, new_provider}, new_state}

          {:error, reason} ->
            new_state = %{"provider" => current, "status" => :failed}
            broadcast(new_state)
            broadcast_error("DNS provider change failed: #{reason}")
            {:reply, {:error, reason}, new_state}
        end
    end
  end

  # --- Private: Provider Change ---

  defp apply_provider_change(new_provider, _old_provider) do
    path = toml_path()

    with {:ok, original_content} <- File.read(path),
         :ok <- write_toml(path, update_server_names(original_content, new_provider)),
         :ok <- restart_and_verify() do
      Logger.info("DNS provider changed to #{new_provider}")
      {:ok, new_provider}
    else
      {:error, reason} ->
        Logger.error("DNS provider change failed: #{inspect(reason)}, rolling back")
        rollback_provider_change()
        {:error, reason}
    end
  end

  defp rollback_provider_change do
    path = toml_path()
    bak_path = path <> ".bak"

    if File.exists?(bak_path) do
      File.cp!(bak_path, path)
      restart_service()
      Logger.info("DNS provider rolled back to previous config")
    else
      Logger.error("DNS rollback failed: no backup file found")
    end
  end

  defp restart_and_verify do
    restart_service()

    if mock?() or verify_service_active?() do
      :ok
    else
      {:error, "dnscrypt-proxy failed to start with new provider"}
    end
  end

  defp restart_service do
    unless mock?() do
      System.cmd("systemctl", ["restart", @service], stderr_to_stdout: true)
    end
  end

  defp verify_service_active? do
    Enum.reduce_while(1..@max_poll_attempts, false, fn _, _ ->
      Process.sleep(@poll_interval)

      case System.cmd("systemctl", ["is-active", @service], stderr_to_stdout: true) do
        {"active\n", 0} -> {:halt, true}
        {"active", 0} -> {:halt, true}
        _ -> {:cont, false}
      end
    end)
  end

  # --- Private: TOML Manipulation ---

  defp read_provider_from_toml do
    path = toml_path()

    case File.read(path) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.find(fn line ->
          trimmed = String.trim_leading(line)
          String.starts_with?(trimmed, "server_names =")
        end)
        |> then(fn
          nil -> @default_provider
          line ->
            case Regex.run(~r/server_names\s*=\s*\['([^']+)'\]/, line) do
              [_, provider] -> provider
              _ -> @default_provider
            end
        end)

      {:error, _} ->
        @default_provider
    end
  end

  defp update_server_names(content, provider) do
    # Replace only the active (non-commented) server_names line.
    # Line-by-line approach avoids regex matching across lines or
    # hitting commented-out server_names entries that would create
    # duplicate keys in TOML.
    content
    |> String.split("\n")
    |> Enum.map(fn line ->
      trimmed = String.trim_leading(line)

      if String.starts_with?(trimmed, "server_names =") do
        "server_names = ['#{provider}']"
      else
        line
      end
    end)
    |> Enum.join("\n")
  end

  defp write_toml(path, content) do
    # Back up current config before writing
    bak_path = path <> ".bak"
    File.cp!(path, bak_path)

    # Atomic write: write to tmp then rename
    tmp_path = path <> ".tmp"

    with :ok <- File.write(tmp_path, content),
         :ok <- File.rename(tmp_path, path) do
      :ok
    else
      {:error, _reason} = error ->
        File.rm(tmp_path)
        error
    end
  end

  # --- Private: Helpers ---

  defp valid_provider?(provider) do
    Enum.any?(@providers, fn {id, _} -> id == provider end)
  end

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(Tunneld.PubSub, "component:dns", %{status: :updated, state: state})
  end

  defp broadcast_error(message) do
    Phoenix.PubSub.broadcast(Tunneld.PubSub, "notifications", %{
      type: :error,
      message: message
    })
  end

  defp mock?, do: Application.get_env(:tunneld, :mock_data, false)
end