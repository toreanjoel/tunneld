defmodule Tunneld.Servers.Auth do
  @moduledoc """
  Init and manage auth for the clients
  """
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init and check auth files
  """
  def init(_) do
    {:ok, %{}}
  end

  @doc """
  Read the auth file
  """
  def read_file() do
    case path() |> File.read() do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, data} ->
            {:ok, data}

          {:error, err} ->
            {:error, "Failed to decode auth file: #{inspect(err)}"}
        end

      {:error, reason} ->
        {:error, "There was a problem reading the file: #{inspect(reason)}"}
    end
  end

  @doc """
  Create the auth file
  """
  def create_file(u, p) do
    case path()
         |> File.write(Jason.encode!(%{"user" => u, "pass" => Bcrypt.hash_pwd_salt(p), "hide_login" => false})) do
      :ok ->
        {:ok, "Auth file created"}

      {:error, reason} ->
        {:error, "Failed to create auth file: #{inspect(reason)}"}
    end
  end

  @doc """
  Save the WebAuthn credential into the auth file
  """
  def save_webauthn(credential_data) do
    case read_file() do
      {:ok, data} ->
        updated =
          data
          |> Map.put("webauthn", credential_data)

        File.write(path(), Jason.encode!(updated))

      error ->
        error
    end
  end

  @doc """
  Clear the WebAuthn credential from the auth file
  """
  def clear_webauthn() do
    case read_file() do
      {:ok, data} ->
        updated = Map.drop(data, ["webauthn"])
        File.write(path(), Jason.encode!(updated))

      error ->
        error
    end
  end

  @doc """
  Check if the user has setup webauthn
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
  Check if the auth file exists
  """
  def file_exists?(), do: path() |> File.exists?()

  # Path helper
  def path(), do: "./" <> config_fs(:root) <> config_fs(:auth)

  # Config helper
  defp config_fs(key), do: Application.get_env(:tunneld, :fs)[key]

  # TODO: we need this?
  # defp config_auth(key), do: Application.get_env(:tunneld, :auth)[key]
end
