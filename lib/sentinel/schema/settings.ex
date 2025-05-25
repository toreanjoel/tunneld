defmodule Sentinel.Schema.Settings do
  @moduledoc """
  The general schema to update the settings and the different settings that would allow for updating
  """

  @spec data(atom()) :: map()
  @doc """
  The JSON schema data that will be used to render the form structure.
  """
  def data(:notifications) do
    %{
      "title" => "Notifications Settings",
      "description" => "Edit the notification settings",
      "type" => "object",
      "properties" => %{
        "endpoint" => %{
          "type" => "string",
          "description" => "The endpoint the system will post events to",
          "minLength" => 1
        },
        "enabled" => %{
          "type" => "boolean",
          "description" => "Enable or disable system-wide notifications to be sent",
        }
      },
      "required" => ["endpoint"]
    }
  end

  def data(:encryption) do
    %{
      "title" => "Encryption Settings",
      "description" => "View the generated encryption key used for other Sentinel nodes to get access to your resources",
      "type" => "object",
      "properties" => %{
         "encryption_key" => %{
          "type" => "string",
          "description" => "The current instance encryption key",
          "readOnly" => true
        }
      },
      "required" => ["encryption_key"]
    }
  end
end
