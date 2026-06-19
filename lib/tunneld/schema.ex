defmodule Tunneld.Schema do
  @moduledoc """
  JSON Schema definitions for dynamic form rendering.

  Each clause returns a JSON Schema map consumed by `JsonSchemaRenderer`.

  ## Arity-1: `data(:login)`, `data(:signup)`, `data(:dns_server)`
  ## Arity-2: `data(:device_tag, %{hostname: h})`
  """

  @doc "Returns a JSON Schema map for the given form type."
  def data(:login) do
    %{
      "title" => "Login ",
      "description" => "The login form rendered to access the system",
      "type" => "object",
      "properties" => %{
        "name" => %{
          "type" => "string",
          "description" => "The device user account",
        },
        "password" => %{
          "type" => "string",
          "format" => "password",
          "description" => "Password associated with the user account",
        }
      },
      "required" => ["name", "password"]
    }
  end

  def data(:signup) do
    %{
      "title" => "Signup",
      "description" => "The signup form rendered to access the system",
      "type" => "object",
      "ui:order" => ["name", "password", "confirm_password"],
      "properties" => %{
        "name" => %{
          "type" => "string",
          "description" => "The device user account",
        },
        "password" => %{
          "type" => "string",
          "format" => "password",
          "description" => "Password associated with the user account",
        },
        "confirm_password" => %{
          "type" => "string",
          "format" => "password",
        }
      },
      "required" => ["name", "password", "confirm_password"]
    }
  end

  def data(:dns_server) do
    %{
      "title" => "DNS Server",
      "description" => "Set the upstream DNS server that all subnet DNS queries are forwarded to.",
      "type" => "object",
      "properties" => %{
        "server" => %{
          "type" => "string",
          "format" => "ipv4",
          "minLength" => 7,
          "maxLength" => 15,
          "description" => "DNS server IP address (e.g. 1.1.1.1, 8.8.8.8, or a subnet Pi-hole IP)"
        }
      },
      "required" => ["server"]
    }
  end

  # --- Arity-2 schemas ---

  def data(:device_tag, %{hostname: hostname} = opts) do
    current_tags = Map.get(opts, :current_tags, [])
    tags_note = if current_tags != [], do: "Current tags: #{Enum.join(current_tags, ", ")}. Enter new tags to append.", else: "Enter a label or category for this device. Use commas to add multiple tags at once."

    %{
      "title" => "Add tag to #{hostname}",
      "description" => tags_note,
      "type" => "object",
      "properties" => %{
        "tag" => %{
          "type" => "string",
          "minLength" => 1,
          "maxLength" => 30,
          "description" => "Tag name (e.g. living-room, work-laptop, IoT)"
        },
        "mac" => %{
          "type" => "string",
          "ui:widget" => "hidden"
        }
      },
      "required" => ["tag", "mac"]
    }
  end

end