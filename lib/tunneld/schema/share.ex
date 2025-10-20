defmodule Tunneld.Schema.Share do
  @moduledoc """
  Share JSON Schema - This is the schema that will be used to generate a form how we interact with the share
  """

  @spec data(atom()) :: map()
  @doc """
  The JSON schema data that will be used to render the form structure.
  """
  # TODO: validation to map to what we are expected on a zrok share
  def data(:add_public) do
    %{
      "title" => "Share Add",
      "description" => "Add a reference to a device running on the tunneld network",
      "type" => "object",
      "ui:order" => ["name", "description", "ip", "port"],
      "properties" => %{
        "name" => %{
          "type" => "string",
          "description" => "Name the share to make it easy to reference",
          "minLength" => 1
        },
        "description" => %{
          "type" => "string",
          "description" =>
            "Describe what this share or application instance is that you is monitored",
          "ui:widget" => "textarea"
        },
        "ip" => %{
          "type" => "string",
          "description" => "IP address of the machine hosting the application",
          "minLength" => 1
        },
        "port" => %{
          "type" => "string",
          "description" => "The port where the application is accessible from"
        }
      },
      "required" => ["ip", "port", "name"]
    }
  end

  @spec data(atom()) :: map()
  def data(:add_private) do
    %{
      "title" => "Private Access",
      "description" => "Connect to a private reserved share on the same control plane",
      "type" => "object",
      "ui:order" => [
        "name",
        "description",
        "ip",
        "port"
      ],
      "properties" => %{
        "name" => %{
          "type" => "string",
          "description" => "The private reserve name will be derived from this.",
          "minLength" => 1
        },
        "description" => %{
          "type" => "string",
          "description" => "Describe what this access connects to.",
          "ui:widget" => "textarea"
        },
        "ip" => %{
          "type" => "string",
          "description" => "Local IP to bind on THIS device (where you'll consume the service).",
          "format" => "ipv4",
          "ui:help" => "Common: 127.0.0.1 (loopback) or 0.0.0.0 (all interfaces)"
        },
        "port" => %{
          "type" => "string",
          "description" => "Local port to bind the access to.",
          "pattern" => "^[0-9]{1,5}$",
          "ui:help" => "1-65535 (ensure it's free)"
        }
      },
      "required" => ["name", "ip", "port"]
    }
  end
end
