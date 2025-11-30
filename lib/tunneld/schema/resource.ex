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
            "Name of the resource (bucket) that groups its public and private references.",
          "ui:help" =>
            "This label appears in the dashboard and groups the related access references.",
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
            "Backend servers for this resource (IP:PORT per line). Both public and private use the same pool.",
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

  @spec data(atom()) :: map()
  def data(:add_private) do
    %{
        "title" => "Private Access",
      "description" =>
        "Connect this gateway to a private reserved resource (you were given its name).",
      "type" => "object",
      "ui:order" => ["name", "description", "pool", "ip", "port"],
      "properties" => %{
        "name" => %{
          "type" => "string",
          "description" =>
            "Exact name of the private resource you are accessing (from the resource’s owner).",
          "ui:help" => "Must match the owner’s private resource name exactly.",
          "minLength" => 1
        },
        "description" => %{
          "type" => "string",
          "description" => "Internal note about what this private access is for.",
          "ui:help" =>
            "Helps you distinguish multiple private accesses (e.g., device/user/purpose).",
          "ui:widget" => "textarea"
        },
        "pool" => %{
          "type" => "array",
          "description" =>
            "Backend servers for this resource (IP:PORT per line). Both public and private use the same pool.",
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
      "required" => ["name", "ip", "port", "pool"]
    }
  end
end
