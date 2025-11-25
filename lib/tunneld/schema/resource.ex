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
      "ui:order" => ["name", "description", "ip", "port"],
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
        "ip" => %{
          "type" => "string",
          "description" => "IP address of the LAN device running the application.",
          "ui:help" =>
            "Example: 192.168.1.50. This is the local IP address of a device on the network running the resource",
          "minLength" => 1
        },
        "port" => %{
          "type" => "string",
          "description" => "Port on that device where the application is listening.",
          "ui:help" => "Examples: 8000. The port you have the running application instance on"
        }
      },
      "required" => ["ip", "port", "name"]
    }
  end

  @spec data(atom()) :: map()
  def data(:add_private) do
    %{
      "title" => "Private Access",
      "description" =>
        "Connect this gateway to a private reserved resource (you were given its name).",
      "type" => "object",
      "ui:order" => ["name", "description", "ip", "port"],
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
        "ip" => %{
          "type" => "string",
          "default" => "0.0.0.0",
          "format" => "ipv4",
          "ui:widget" => "hidden",
          "readOnly" => true
        },
        "port" => %{
          "type" => "string",
          "description" =>
            "Gateway port that devices on the subnet will use to reach this private resource.",
          "ui:help" => "Devices will connect via gateway_ip:PORT. Choose a free port (1–65535).",
          "pattern" => "^[0-9]{1,5}$"
        }
      },
      "required" => ["name", "ip", "port"]
    }
  end
end
