defmodule TunneldWeb.Controller.CLI do
  @moduledoc """
  Controller to handle CLI interactions for managing artifacts and nodes.
  This provides API endpoints that the `TunneldCLI` tool calls remotely.
  """

  use TunneldWeb, :controller

  @doc """
  Get details of an artifact. This will support the fetching of details, desciptions and schema information
  """
  @spec get_artifact(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def get_artifact(conn, %{ "id" => _id}) do
    conn
    |> put_status(:not_found)
    |> json(%{message: "Option not yet supported"})
  end

  @doc """
  List all artifacts
  """
  @spec list_artifacts(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def list_artifacts(conn, _params) do
    local =
      Tunneld.Servers.Artifacts.fetch_artifacts()
      |> Enum.map(&Map.put(&1, "remote", false))

    remote =
      case Tunneld.Servers.SocketClient.details() do
        %{connected: true} ->
          case Tunneld.Servers.SocketClient.request_event(%{"type" => "init", "data" => %{}}) do
            {:ok, artifacts} -> Enum.map(artifacts, &Map.put(&1, "remote", true))
            _ -> []
          end

        _ ->
          []
      end

    json(conn, %{artifacts: local ++ remote})
  end

  @doc """
  Add a new artifact
  """
  @spec add_artifact(Plug.Conn.t(), map()) :: Plug.Conn.t()
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
  Publish an artifact to make it accessible on a domain
  """
  @spec publish_artifact(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def publish_artifact(conn, %{"id" => id, "domain" => domain}) do
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
          # We need to look at a better way to keep the data structure consistent - we need to use dot and array selection notation?
          Tunneld.Servers.Cloudflare.add_host("#{artifact.ip}:#{artifact.port}", domain)
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
  Unpublish an artifact to remove making it accessible on a domain
  """
  @spec unpublish_artifact(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def unpublish_artifact(conn, %{"id" => id}) do
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
          if not Enum.empty?(artifact.tunnel) do
            # gracefully try and disconnect the tunnel link
            Tunneld.Servers.Cloudflare.remove_host(artifact.tunnel["subdomain"])
          end

          # This is async, we need to make sure message gets this across
          Tunneld.Servers.Artifacts.remove_artifact(id)

          json(conn, %{
            message:
              "Artifact #{id} being unpiblushed from the domain: #{artifact.tunnel["subdomain"]}"
          })
        end

      _ ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          message: "There was a problem exposing unpublishing artifact."
        })
    end
  end

  @doc """
  Call an artifact with payload
  """
  @spec call_artifact(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def call_artifact(conn, %{"id" => id, "data" => data}) do
    artifact = find_artifact_by_id(id)

    cond do
      is_nil(artifact) ->
        conn
        |> put_status(:bad_request)
        |> json(%{message: "Artifact not found"})

      Map.get(artifact, "remote", false) ->
        # Remote artifact call via socket
        case Tunneld.Servers.SocketClient.request_event(%{
               "type" => "trigger",
               "data" => %{"id" => id, "payload" => data}
             }) do
          {:ok, response} ->
            json(conn, %{message: "Triggered remote artifact #{id}", data: response})

          {:error, reason} ->
            conn
            |> put_status(:bad_gateway)
            |> json(%{message: "Failed to trigger remote artifact", error: inspect(reason)})
        end

      true ->
        # Local artifact call via HTTP
        {status, resp} =
          if artifact["tunneld"] && Map.get(artifact["tunneld"], "enabled", false) do
            http_payload = %{
              ip: artifact["ip"],
              port: artifact["port"],
              path: Map.get(artifact["tunneld"], "route"),
              data: data
            }

            {_, %HTTPoison.Response{status_code: code, body: body}} =
              http_request(Map.get(artifact["tunneld"], "request_type"), http_payload)

            {:ok, %{"code" => code, "resp" => body}}
          else
            {:ok, %{"code" => 500, "resp" => "Artifact disabled"}}
          end

        json(conn, %{status: status, payload: resp})
    end
  end

  @doc """
  Remove an artifact
  """
  @spec remove_artifact(Plug.Conn.t(), map()) :: Plug.Conn.t()
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
          if not Enum.empty?(artifact.tunnel) do
            # gracefully try and disconnect the tunnel link
            Tunneld.Servers.Cloudflare.remove_host(artifact.tunnel["subdomain"])
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
  Start hosting this gateway as a node
  """
  @spec host_node(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def host_node(conn, _params) do
    gateway = "https://#{System.get_env("CF_DOMAIN")}"

    payload = %{
      "description" =>
        "CLI: Adding the current device as an artifact to be accesble on its registered domain",
      "ip" => System.get_env("GATEWAY", ""),
      "name" => "GATEWAY",
      "port" => "80"
    }

    # We dont do anything in terms of waiting, so this needs feedback as the response
    %{artifacts: items} = Tunneld.Servers.Artifacts.add_artifact(payload)
    gateway_artifact = items |> Enum.filter(fn item -> item["name"] === "GATEWAY" end)

    if Enum.empty?(gateway_artifact) do
      # Expose the gateway - this is async, so we need to make the message keep this in mind
      Tunneld.Servers.Cloudflare.add_host(
        "#{gateway_artifact.ip}:#{gateway_artifact.port}",
        gateway_artifact
      )
    end

    json(conn, %{
      message:
        "Gateway accessible on #{gateway}, Log into dashboard to get access key to share with client nodes to access your artifacts"
    })
  end

  @doc """
  Connect to another node
  """
  @spec connect_node(Plug.Conn.t(), map()) :: Plug.Conn.t()
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

  @doc """
  Disconnect from current node
  """
  @spec disconnect_node(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def disconnect_node(conn, _params) do
    Tunneld.Servers.SocketClient.disconnect()
    json(conn, %{message: "Disconnected from remote node"})
  end

  @doc """
  List connected nodes
  """
  @spec list_nodes(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def list_nodes(conn, _params) do
    case Tunneld.Servers.SocketClient.details() do
      :not_running ->
        json(conn, %{nodes: [], message: "Socket client not running"})

      %{connected: true, metadata: metadata} ->
        json(conn, %{nodes: [%{id: metadata.device, uri: System.get_env("CF_DOMAIN"), status: "connected"}]})

      %{connected: false, reason: reason} ->
        json(conn, %{nodes: [], message: "Socket client disconnected", reason: inspect(reason)})
    end
  end

  # Get the details around the artifacts remote and local
  @spec find_artifact_by_id(String.t()) :: map() | nil
  defp find_artifact_by_id(id) do
    # Local artifacts
    local =
      Tunneld.Servers.Artifacts.fetch_artifacts()
      |> Enum.map(&Map.put(&1, "remote", false))

    # Remote artifacts (only if connected)
    remote =
      case Tunneld.Servers.SocketClient.details() do
        %{connected: true} ->
          case Tunneld.Servers.SocketClient.request_event(%{"type" => "init", "data" => %{}}) do
            {:ok, artifacts} -> Enum.map(artifacts, &Map.put(&1, "remote", true))
            _ -> []
          end

        _ ->
          []
      end

    # Combine and find matching ID
    Enum.find(local ++ remote, fn artifact -> artifact["id"] == id end)
  end

  # These are for now but allows us to make requests the artifacts that are locally accessible
  @spec http_request(String.t(), map()) :: {:ok, HTTPoison.Response.t()} | {:error, term()}
  defp http_request("post", payload) do
    HTTPoison.post(
      "http://#{payload.ip}:#{payload.port}#{payload.path}",
      Jason.encode!(payload.data || %{}),
      [{"Accept", "Application/json"}, {"Content-Type", "application/json"}],
      recv_timeout: 30_000
    )
  end

  defp http_request("get", payload) do
    HTTPoison.get(
      "http://#{payload.ip}:#{payload.port}#{payload.path}",
      [{"Accept", "Application/json"}, {"Content-Type", "application/json"}],
      recv_timeout: 30_000
    )
  end
end
