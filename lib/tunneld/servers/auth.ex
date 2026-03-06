defmodule Tunneld.Servers.Auth do
  @moduledoc """
  Manages the on-disk authentication file (`auth.json`).

  The auth file stores a single admin credential set (username + bcrypt hash)
  and an optional WebAuthn credential for biometric login. All reads and writes
  go through this module to keep the file format consistent.

  This GenServer currently holds no state — it exists as a named process so
  the supervision tree can track it, but all operations read/write directly
  to disk.
  """
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc false
  def init(_) do
    {:ok, %{}}
  end

  @doc """
  Read and decode the auth JSON file. Returns `{:ok, map}` or `{:error, reason}`.
  """
  def read_file() do
    case Tunneld.Persistence.read_json(path()) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, "Failed to read auth file: #{inspect(reason)}"}
    end
  end

  @doc """
  Create the auth file with the given username and plaintext password.
  The password is bcrypt-hashed before writing.
  """
  def create_file(u, p) do
    data = %{"user" => u, "pass" => Bcrypt.hash_pwd_salt(p), "hide_login" => false}

    case Tunneld.Persistence.write_json(path(), data) do
      :ok -> {:ok, "Auth file created"}
      {:error, reason} -> {:error, "Failed to create auth file: #{inspect(reason)}"}
    end
  end

  @doc """
  Merge a WebAuthn credential map into the existing auth file under the `"webauthn"` key.
  """
  def save_webauthn(credential_data) do
    case read_file() do
      {:ok, data} ->
        updated = Map.put(data, "webauthn", credential_data)
        Tunneld.Persistence.write_json(path(), updated)

      error ->
        error
    end
  end

  @doc """
  Remove the `"webauthn"` key from the auth file, disabling biometric login.
  """
  def clear_webauthn() do
    case read_file() do
      {:ok, data} ->
        updated = Map.drop(data, ["webauthn"])
        Tunneld.Persistence.write_json(path(), updated)

      error ->
        error
    end
  end

  @doc """
  Returns `true` if a WebAuthn credential is stored in the auth file.
  """
  def has_webauthn?() do
    case read_file() do
      {:ok, data} ->
        Map.has_key?(data, "webauthn")

      _error ->
        false
    end
  end

  @doc """
  Returns `true` if the auth JSON file exists on disk.
  """
  def file_exists?(), do: path() |> File.exists?()

  # Path helper
  def path(), do: Path.join(Tunneld.Config.fs(:root), Tunneld.Config.fs(:auth))
end
