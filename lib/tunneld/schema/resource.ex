defmodule Tunneld.Schema.Resource do
  @moduledoc """
  Resource JSON Schema - This is the schema that will be used to generate a form how we interact with the resource
  """

  @spec data(atom()) :: map()
  @doc """
  The JSON schema data that will be used to render the form structure.
  """
  def data(:add_public) do
    %{
      "title" => "Resource Add",
      "description" =>
        "Register a LAN device and port for this resource. (Internal, shown on the dashboard.)",
      "type" => "object",
      "ui:order" => ["name", "description", "pool", "ip", "port"],
      "properties" => %{
        "name" => %{
          "type" => "string",
          "description" =>
            "Name of the resource. Used as the local DNS hostname (<name>.tunneld.lan).",
          "ui:help" =>
            "This label appears in the dashboard and is the hostname subnet devices use to reach the resource.",
          "minLength" => 1
        },
        "description" => %{
          "type" => "string",
          "description" => "Internal note about what this shared application/service is.",
          "ui:help" =>
            "Only for your own context on the dashboard (e.g., owner, purpose, login URL).",
          "ui:widget" => "textarea"
        },
        "pool" => %{
          "type" => "array",
          "description" =>
            "Backend servers for this resource (IP:PORT per line). All entries share the same upstream pool.",
          "ui:help" =>
            "Example: 10.0.10.44:8001. Add each backend on its own line; leave blank lines out.",
          "items" => %{
            "type" => "string",
            "pattern" => "^[^\\s:]+:[0-9]{1,5}$"
          },
          "minItems" => 1
        },
        "ip" => %{
          "type" => "string",
          "default" => "127.0.0.1",
          "format" => "ipv4",
          "ui:widget" => "hidden",
          "readOnly" => true
        },
        "port" => %{
          "type" => "string",
          "default" => "18000",
          "ui:widget" => "hidden",
          "readOnly" => true
        }
      },
      "required" => ["ip", "port", "name", "pool"]
    }
  end
end
