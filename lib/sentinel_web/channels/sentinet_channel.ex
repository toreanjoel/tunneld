defmodule SentinelWeb.SentinetChannel do
  @moduledoc """
  The channel and how we handle the connection on joins and custom topics
  """
  use SentinelWeb, :channel

  @impl true
  def join("sentinet:host", payload, socket) do
    if authorized?(payload) do
      {:ok, socket}
    else
      {:error, %{reason: "Unable to connect"}}
    end
  end

  @doc """
  Handle different types of event payloads - payload will be encrypted by default
  """
  @impl true
  def handle_in("event", payload, socket) do
    # Decode the payload, then store that as the binary to decrypt
    data = payload |> Base.decode64!()
    # The key to decrypt with is the local stored key - cypher
    cypher = Sentinel.Servers.Encryption.fetch_settings() |> Base.decode64!()
    # Original Data
    decrypted_data = Jason.decode!(Sentinel.Encryption.decrypt(cypher, data))
    # We look at the event type that we want to process in some way to the client
    process(decrypted_data["type"], socket)
  end

  # Private functions to process different event types
  defp process("init", socket) do
    # TODO: add the custom data here that we need to send to the user
    #
    resp = %{
      "data" => "This is the init data!"
    } |> Jason.encode!()

    # We send a response back to the user for the init data
    {:reply, {:ok, Sentinel.Servers.Encryption.encrypt_payload(resp) |> Base.encode64}, socket}
  end

  # Add authorization logic here as required.
  defp authorized?(%{"token" => token, "device" => device}) do
    #  We will get a device key and some string, we need to use that device key and our string to decript
    expected =
      Sentinel.Encryption.generate_auth_token(
        Sentinel.Servers.Encryption.fetch_settings(),
        device
      )

    if Plug.Crypto.secure_compare(expected, token) do
      true
    else
      false
    end
  end

  defp authorized?(_) do
    false
  end

  # TODO: add other events to handle for the user making the request
end
