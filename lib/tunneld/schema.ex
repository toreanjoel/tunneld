defmodule Tunneld.Schema do
  @moduledoc """
  JSON Schema definitions for dynamic form rendering.

  Each clause returns a JSON Schema map consumed by `JsonSchemaRenderer`.

  ## Arity-1: `data(:login)`, `data(:signup)`
  ## Arity-2: `data(:wlan, %{title: t})`, `data(:zrok, :endpoint)`, `data(:zrok, :conf_device)`
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

  # --- Arity-2 schemas ---

  def data(:wlan, %{title: title}) do
    %{
      "title" => "Connect to network: " <> title,
      "description" => "Enter the password required to connect to this network.",
      "type" => "object",
      "properties" => %{
        "ssid" => %{
          "type" => "string",
          "description" => "SSID or network name that will be connected to",
          "ui:widget" => "hidden"
        },
        "password" => %{
          "type" => "string",
          "format" => "password",
          "description" => "Password associated with the wireless public network",
        }
      },
      "required" => ["ssid", "password"]
    }
  end

  def data(:zrok, :endpoint) do
    %{
      "title" => "Set the endpoint network to connect to",
      "description" => "The network endpoint (control plane) that you will have this device connected under",
      "type" => "object",
      "properties" => %{
        "url" => %{
          "type" => "string",
          "format" => "uri",
          "minLength" => 1,
          "description" => "The URL endpoint of the control plane"
        }
      },
      "required" => ["url"]
    }
  end

  def data(:device_tag, %{hostname: hostname}) do
    %{
      "title" => "Add tag to #{hostname}",
      "description" => "Enter a label or category for this device. Use commas to add multiple tags at once.",
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

  def data(:zrok, :conf_device) do
    %{
      "title" => "Enable device on an account",
      "description" => "Connect this device as an environment on an account for the control plane you are connected to",
      "type" => "object",
      "properties" => %{
        "account_token" => %{
          "type" => "string",
          "format" => "password",
          "minLength" => 1,
          "description" => "The account token to enable this device against"
        }
      },
      "required" => ["account_token"]
    }
  end

end