defmodule Tunneld.Servers.Encryption do
  @moduledoc """
  Init storing encryption keys and generating new ones
  """
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init and check the encryption file
  """
  def init(_) do
    if not file_exists?(), do: create_file()

    {:ok, %{}}
  end

  @doc """
  Read the encryption key from file
  """
  def read_file() do
    with {:ok, base64} <- File.read(path()) do
      {:ok, base64}
    else
      {:error, reason} -> {:error, "Unable to read or decode key: #{inspect(reason)}"}
    end
  end

  @doc """
  Create the encryption file
  """
  def create_file() do
    case path()
         |> File.write(Tunneld.Encryption.generate_key() |> Base.encode64()) do
      :ok ->
        {:ok, "Encryption file created"}

      {:error, reason} ->
        {:error, "Failed to create encryption file: #{inspect(reason)}"}
    end
  end

  @doc """
  Get the relevant settings for encryption
  """
  def fetch_settings() do
    {_, data} = read_file()
    data
  end

  @doc """
  Create the encryption file
  """
  def generate_key() do
    case path()
         |> File.write(Tunneld.Encryption.generate_key() |> Base.encode64()) do
      :ok ->
        {:ok, "Encryption file generated created"}

      {:error, reason} ->
        {:error, "Failed to create encryption file: #{inspect(reason)}"}
    end
  end

  @doc """
  Encrypt a payload - we can then use this for what ever purpose
  """
  def encrypt_payload(plaintext) when is_binary(plaintext) do
    key = Base.decode64!(fetch_settings())
    Tunneld.Encryption.encrypt(key, plaintext)
  end

  @doc """
  Decrypt a payload to read the data
  """
  def decrypt_payload(ciphertext) when is_binary(ciphertext) do
    key = Base.decode64!(fetch_settings())
    Tunneld.Encryption.decrypt(key, ciphertext)
  end

  @doc """
  Check if the encryption file exists
  """
  def file_exists?(), do: path() |> File.exists?()

  @spec path() :: String.t()
  defp path(), do: "./" <> config_fs(:root) <> config_fs(:encryption)

  # Config helper
  @spec config_fs() :: keyword()
  defp config_fs(), do: Application.get_env(:tunneld, :fs)

  @spec config_fs(atom()) :: any()
  defp config_fs(key), do: config_fs()[key]
end
