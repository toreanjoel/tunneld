defmodule TunneldWeb.Controller.CLI do
  @moduledoc """
  Controller to handle CLI interactions for managing artifacts and nodes.
  This provides API endpoints that the `TunneldCLI` tool calls remotely.
  """

  use TunneldWeb, :controller

  @doc """
  GET /api/artifacts — List all artifacts
  """
  def list_artifacts(conn, _params) do
    artifacts = Tunneld.Servers.Artifacts.fetch_artifacts()

    json(conn, %{artifacts: artifacts})
  end

  @doc """
  POST /api/artifacts — Add a new artifact
  Expected params: %{ "name" => name, "ip" => ip, "port" => port, "description" => description }
  """
  def add_artifact(conn, %{
        "name" => name,
        "ip" => ip,
        "port" => port,
        "description" => description
      }) do
    payload = %{
      "description" => description || "TODO: CLI added Artifact. Update description",
      "ip" => ip,
      "name" => name,
      "port" => port
    }

    # We dont do anything in terms of waiting, so this needs feedback as the response
    Tunneld.Servers.Artifacts.add_artifact(payload)

    json(conn, %{
      message: 'Artifact #{name} added and expected to be running on http://#{ip}:#{port}'
    })
  end

  @doc """
  POST /api/artifacts/:id/expose — Expose an artifact publicly
  Expected params: %{ "name" => name, "name" => name }
  """
  def expose_artifact(conn, %{"id" => id, "domain" => domain}) do
    # We will need to get the artifact and then pass it through the cloudflare function
    case Tunneld.Servers.Artifacts.get_artifact_details(id) do
      {_, artifact} ->
        if is_nil(artifact) do
          conn
          |> put_status(:bad_request)
          |> json(%{
            message: "There was a problem fetching artifact."
          })
        else
          # TODO: we may need to make a call here so we can know if this succeeded
          Tunneld.Servers.Cloudflare.add_host("#{artifact["ip"]}:#{artifact["port"]}", domain)
          # Connect to cloudflare here - needs to be the user domain setup on the gateway
          json(conn, %{
            message:
              "Artifact #{id} being exposed on https://#{domain}. Visit link in a few seconds"
          })
        end

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          message: "There was a problem exposing artifact publicly on the domain #{domain}"
        })
    end
  end

  @doc """
  POST /api/artifacts/:id/call — Call an artifact with payload
  Expected params: %{ "data" => map }
  """
  def call_artifact(conn, %{"id" => id, "data" => data}) do
    # TODO: Forward data to artifact process
    json(conn, %{message: "Called artifact #{id}", data: data})
  end

  @doc """
  DELETE /api/artifacts/:id — Remove an artifact
  """
  # TODO: add a separate function to make it easy to quickly expose
  def remove_artifact(conn, %{"id" => id}) do
    case Tunneld.Servers.Artifacts.get_artifact_details(id) do
      {_, artifact} ->
        if is_nil(artifact) do
          conn
          |> put_status(:bad_request)
          |> json(%{
            message: "There was a problem fetching artifact."
          })
        else
          # we check if we have tunnel data
          if Enum.empty?(
               tunnel =
                 Tunneld.Servers.Cloudflare.get_tunnel_data(artifact["ip"], artifact["port"])
             ) do
            # gracefully try and disconnect the tunnel link
            Tunneld.Servers.Cloudflare.remove_host(tunnel["subdomain"])
          end

          # This is async, we need to make sure message gets this across
          Tunneld.Servers.Artifacts.remove_artifact(id)

          # Message back to the client
          json(conn, %{message: "Artifact #{id} being removed."})
        end

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          message: "There was a problem removing artifact."
        })
    end
  end

  @doc """
  POST /api/nodes/host — Start hosting this gateway as a node
  """
  def host_node(conn, _params) do
    gateway = "https://#{System.get_env("CF_DOMAIN")}"

    json(conn, %{
      message:
        "Gateway accessible on #{gateway}, Log into dashboard to get access key to share with client nodes to access your artifacts"
    })
  end

  @doc """
  POST /api/nodes/connect — Connect to another node
  Expected params: %{ "domain" => domain, "token" => token }
  """
  def connect_node(conn, %{"domain" => domain} = params) do
    token = Map.get(params, "token")

    # Start the socket connection asynchronously
    task =
      Task.async(fn ->
        Tunneld.Servers.SocketClient.start_link(
          uri: "wss://#{domain}/socket/websocket",
          token: token
        )
      end)

    case Task.await(task, 5_000) do
      {:ok, _pid} ->
        # Ensure connection is established before responding
        case Tunneld.Servers.SocketClient.wait_for_connection(5_000) do
          :ok ->
            json(conn, %{message: "Connected to node #{domain}", token: token || "generated"})

          {:error, reason} ->
            conn
            |> put_status(:bad_gateway)
            |> json(%{error: "Failed to connect: #{inspect(reason)}"})
        end

      {:error, reason} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{error: "Failed to start connection: #{inspect(reason)}"})
    end
  end

  @spec disconnect_node(Plug.Conn.t(), any()) :: Plug.Conn.t()
  @doc """
  POST /api/nodes/disconnect — Disconnect from current node
  """
  def disconnect_node(conn, _params) do
    Tunneld.Servers.SocketClient.disconnect()
    json(conn, %{message: "Disconnected from remote node"})
  end

  @doc """
  GET /api/nodes — List connected nodes
  """
  def list_nodes(conn, _params) do
    case Tunneld.Servers.SocketClient.details() do
      :not_running ->
        json(conn, %{nodes: [], message: "Socket client not running"})

      %{connected: true, metadata: metadata} ->
        json(conn, %{nodes: [%{id: metadata.device, status: "connected"}]})

      %{connected: false, reason: reason} ->
        json(conn, %{nodes: [], message: "Socket client disconnected", reason: inspect(reason)})
    end
  end
end
