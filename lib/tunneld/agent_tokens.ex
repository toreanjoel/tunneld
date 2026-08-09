defmodule Tunneld.AgentTokens do
  @moduledoc """
  Scoped, revocable, hashed-at-rest bearer tokens for the agent API.

  Tokens are the credential for the HTTP API (the product). Skills/MCP are
  thin adapters over it. A token:

  * is prefixed `tnld_` so it is identifiable at a glance and greppable in logs;
  * is stored **hashed** (SHA-256) — the raw token is returned once at issue and
    never persisted, so a leaked data file cannot be replayed;
  * carries a set of **scopes** (e.g. `machines:read`, `resources:write`,
    `exec`) checked by the auth plug before each call;
  * can be **revoked** (removed) at any time.

  Some scopes are reserved and can never be granted via the API: token
  issuance, machine enrollment, iptables rules outside a token's own
  resources, DNS provider config, and WireGuard key material. See
  `forbidden_scopes/0`.

  Persisted to `tokens.json` under the data root. State is a GenServer so
  concurrent issue/revoke/verify are serialized.
  """

  use GenServer
  require Logger

  alias Tunneld.Persistence

  @prefix "tnld_"

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @doc "The token prefix used to identify tunneld agent tokens."
  def prefix, do: @prefix

  @doc "Scopes that can never be granted to an agent token (privilege escalation)."
  def forbidden_scopes do
    ["tokens:issue", "tokens:revoke", "machines:enroll", "iptables:admin",
     "dns:provider", "wireguard:keys"]
  end

  @doc """
  Issue a new token with the given scopes. Returns `{:ok, token_string}` where
  the token is returned once (it is not stored in plaintext).
  """
  def issue(scopes) when is_list(scopes) do
    GenServer.call(__MODULE__, {:issue, scopes})
  end

  @doc "Revoke a token. Returns `:ok` (idempotent)."
  def revoke(token) do
    GenServer.call(__MODULE__, {:revoke, token})
  end

  @doc """
  Verify a token and check it holds `scope`. Returns `{:ok, token_id, scopes}`
  on success, or `:error`.
  """
  def authorize(token, scope) do
    GenServer.call(__MODULE__, {:authorize, token, scope})
  end

  @doc "List all issued tokens (id, scopes, created_at) — never the raw token."
  def list do
    GenServer.call(__MODULE__, :list)
  end

  # --- GenServer ---

  @impl true
  def handle_call({:issue, scopes}, _from, state) do
    # Strip any forbidden scopes defensively.
    clean = scopes -- forbidden_scopes()
    raw = @prefix <> Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
    id = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)

    record = %{
      "id" => id,
      "hash" => hash(raw),
      "scopes" => clean,
      "created_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    write(path(), read() |> Map.put(id, record))
    {:reply, {:ok, raw, id, clean}, state}
  end

  @impl true
  def handle_call({:revoke, token}, _from, state) do
    case find_by_hash(hash(token)) do
      nil ->
        {:reply, :ok, state}

      {id, _rec} ->
        write(path(), Map.delete(read(), id))
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:authorize, token, scope}, _from, state) do
    case find_by_hash(hash(token)) do
      nil ->
        {:reply, :error, state}

      {id, record} ->
        if scope in record["scopes"] do
          {:reply, {:ok, id, record["scopes"]}, state}
        else
          {:reply, :error, state}
        end
    end
  end

  @impl true
  def handle_call(:list, _from, state) do
    list =
      read()
      |> Enum.map(fn {id, rec} ->
        %{id: id, scopes: rec["scopes"], created_at: rec["created_at"]}
      end)

    {:reply, list, state}
  end

  # --- helpers ---

  defp find_by_hash(h) do
    Enum.find_value(read(), fn {id, rec} ->
      if rec["hash"] == h, do: {id, rec}
    end)
  end

  defp hash(raw), do: :crypto.hash(:sha256, raw) |> Base.encode16(case: :lower)

  defp read do
    case Persistence.read_json(path()) do
      {:ok, %{"tokens" => map}} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp write(file, map) do
    Persistence.write_json(file, %{"tokens" => map})
  end

  defp path do
    Path.join(Tunneld.Config.fs_root(), "tokens.json")
  end
end
