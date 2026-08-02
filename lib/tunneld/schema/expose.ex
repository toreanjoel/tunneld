defmodule Tunneld.Schema.Expose do
  @moduledoc """
  Remote container expose JSON Schema - rendered as a form by `JsonSchemaRenderer`.

  Used to expose a service running inside a container on a remote machine to the
  gateway's local subnet via a reverse SSH port-forward.
  """

  @spec data(map()) :: map()
  @doc """
  The JSON schema data used to render the expose form.

  `opts` may include `:machine_id` and `:container` which are carried through
  as hidden fields so the action knows which container to expose.
  """
  def data(opts \\ %{}) do
    machine_id = Map.get(opts, :machine_id)
    container = Map.get(opts, :container)

    %{
      "title" => "Expose Container",
      "description" =>
        "Open a reverse SSH tunnel to this container's port so it is reachable on the subnet at <name>.tunneld.lan:18000.",
      "type" => "object",
      "ui:order" => ["machine_id", "container", "port"],
      "properties" => %{
        "machine_id" => %{
          "type" => "string",
          "default" => machine_id,
          "ui:widget" => "hidden",
          "readOnly" => true
        },
        "container" => %{
          "type" => "string",
          "default" => container,
          "ui:widget" => "hidden",
          "readOnly" => true
        },
        "port" => %{
          "type" => "integer",
          "description" => "Container port to expose.",
          "ui:help" =>
            "The port the service listens on inside the container (e.g. 80, 3000, 8080).",
          "minimum" => 1,
          "maximum" => 65535
        }
      },
      "required" => ["machine_id", "container", "port"]
    }
  end
end
