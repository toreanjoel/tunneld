defmodule Tunneld.Encryption do
  @moduledoc """
  Helper methods to encrypt and decrypt data to. Can be used to generate private/public keys.
  """

  @aes_algo :aes_256_gcm
  @key_size 32 # 32 bytes = 256 bits and required for AES encryption
  @iv_size 12 # Initial vector of 12 bytes recommended for security and performance

  @doc """
  Generate a symetrical key to store and encrypt data with
  """
  def generate_key do
    :crypto.strong_rand_bytes(@key_size)
  end

  @doc """
  Encrypt plaintext with key - we make sure the length of the key matches when being used with the system
  """
  def encrypt(key, plaintext) when byte_size(key) == @key_size do
    iv = :crypto.strong_rand_bytes(@iv_size)
    {ciphertext, tag} = :crypto.crypto_one_time_aead(@aes_algo, key, iv, plaintext, "", true)
    <<iv::binary, tag::binary, ciphertext::binary>>
  end

  @doc """
  Decrypt data using a key
  """
  def decrypt(key, <<iv::binary-size(@iv_size), tag::binary-size(16), ciphertext::binary>>) do
    :crypto.crypto_one_time_aead(@aes_algo, key, iv, ciphertext, "", tag, false)
  end

  @doc """
  Pass shared key and use generated uuid to create a 1 way hash key that we need to send to the server on auth.
  The server will compare the UUID do the same compute with its key to confirm keys are the same
  """
  def generate_auth_token(key, device_id) do
    hmac = :crypto.mac(:hmac, :sha256, key, device_id)
    Base.encode64(hmac)
  end
end
