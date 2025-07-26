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
    artifacts = [
      %{id: 1, name: "web-app", exposed: true, domain: "web.gw.tunneld.devsss"},
      %{id: 22222222, name: "api-service", exposed: false, domain: nil}
    ]

    json(conn, %{artifacts: artifacts})
  end

  @doc """
  POST /api/artifacts — Add a new artifact
  Expected params: %{ "name" => name, "port" => port }
  """
  def add_artifact(conn, %{"name" => name, "port" => port}) do
    # TODO: Persist artifact to storage
    json(conn, %{message: "Artifact added", name: name, port: port})
  end

  @doc """
  POST /api/artifacts/:id/expose — Expose an artifact publicly
  Expected params: %{ "domain" => domain }
  """
  def expose_artifact(conn, %{"id" => id, "domain" => domain}) do
    # TODO: Update artifact exposure status
    json(conn, %{message: "Artifact #{id} exposed on #{domain}"})
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
  def remove_artifact(conn, %{"id" => id}) do
    # TODO: Delete artifact
    json(conn, %{message: "Artifact #{id} removed"})
  end

  @doc """
  POST /api/nodes/host — Start hosting this gateway as a node
  """
  def host_node(conn, _params) do
    # TODO: Start hosting logic
    json(conn, %{message: "Hosting node started"})
  end

  @doc """
  POST /api/nodes/connect — Connect to another node
  Expected params: %{ "domain" => domain, "token" => token }
  """
  def connect_node(conn, %{"domain" => domain, "token" => token}) do
    # TODO: Connect to node logic
    json(conn, %{message: "Connected to node #{domain}", token: token})
  end

  @doc """
  POST /api/nodes/disconnect — Disconnect from current node
  """
  def disconnect_node(conn, _params) do
    # TODO: Disconnect node logic
    json(conn, %{message: "Node disconnected"})
  end

  @doc """
  GET /api/nodes — List connected nodes
  """
  def list_nodes(conn, _params) do
    nodes = [
      %{id: 1, domain: "node1.gw.tunneld.dev", status: "connected"},
      %{id: 2, domain: "node2.gw.tunneld.dev", status: "disconnected"}
    ]

    json(conn, %{nodes: nodes})
  end
end
