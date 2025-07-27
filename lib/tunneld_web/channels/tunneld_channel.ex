defmodule TunneldWeb.TunneldChannel do
  @moduledoc """
  The channel and how we handle the connection on joins and custom topics
  """
  use TunneldWeb, :channel

  @impl true
  def join("tunneld:host", payload, socket) do
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
    cypher = Tunneld.Servers.Encryption.fetch_settings() |> Base.decode64!()
    # Original Data
    decrypted_data = Jason.decode!(Tunneld.Encryption.decrypt(cypher, data))
    # We look at the event type that we want to process in some way to the client
    process(%{type: decrypted_data["type"], data: decrypted_data["data"]}, socket)
  end

  # Private functions to process different event types
  # We need to process an init and accept other messages for general data
  defp process(%{type: "init", data: _data}, socket) do
    resp =
      case Tunneld.Servers.Artifacts.get_enabled_artifacts() do
        {:ok, data} -> data
        _ -> []
      end
      |> Jason.encode!()

    # We send a response back to the user for the init data
    {:reply, {:ok, Tunneld.Servers.Encryption.encrypt_payload(resp) |> Base.encode64()}, socket}
  end

  # The trigger against the artifact from the remote tunneld
  # NOTE: This should ideally be setup under a gen server for multi user requests
  defp process(%{type: "trigger", data: %{"id" => id, "payload" => payload}} = _data, socket) do
    {_, artifact} = Tunneld.Servers.Artifacts.get_artifact_details(id)

    {status, resp} =
      if not is_nil(artifact) and Map.get(artifact.tunneld, "enabled", false) do
        # The base HTTP payload
        http_payload = %{
          ip: artifact.ip,
          port: artifact.port,
          path: Map.get(artifact.tunneld, "route"),
          data: payload
        }

        {_, %HTTPoison.Response{status_code: code, body: body}} =
          _resp = http_request(Map.get(artifact.tunneld, "request_type"), http_payload)

        {:ok, %{"code" => code, "resp" => body}}
      else
        {:ok, %{"code" => 500, "resp" => "No artifact to handle"}}
      end

    # Payload built from the calls to the relevant services
    resp = %{
      "status" => status,
      "payload" => resp
    }

    # We send a response back to the user for the init data
    {:reply,
     {:ok,
      Tunneld.Servers.Encryption.encrypt_payload(resp |> Jason.encode!()) |> Base.encode64()},
     socket}
  end

  # Add authorization logic here as required.
  defp authorized?(%{"token" => token, "device" => device}) do
    #  We will get a device key and some string, we need to use that device key and our string to decript
    expected =
      Tunneld.Encryption.generate_auth_token(
        Tunneld.Servers.Encryption.fetch_settings(),
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

  # Handle the HTTP reqeust to the local servers through gateway to machines on the network
  defp http_request("post", payload) do
    HTTPoison.post(
      "http://#{payload.ip}:#{payload.port}#{payload.path}",
      Jason.encode!(payload.data || %{}),
      [{"Accept", "Application/json"}, {"Content-Type", "application/json"}],
      recv_timeout: 120_000
    )
  end

  defp http_request("get", payload) do
    HTTPoison.get(
      "http://#{payload.ip}:#{payload.port}#{payload.path}",
      [{"Accept", "Application/json"}, {"Content-Type", "application/json"}],
      recv_timeout: 120_000
    )
  end
end
