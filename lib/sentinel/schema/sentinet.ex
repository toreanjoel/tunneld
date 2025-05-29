defmodule Sentinel.Schema.Sentinet do
  @moduledoc """
  Setup Sentinet settings to manage access over a private network to your artifacts
  """

  @spec data(atom()) :: map()
  @doc """
  The JSON schema data that will be used to render the form structure.
  """
  def data(:settings) do
    %{
      "title" => "Sentinet Settings",
      "description" => "Setup artifact settings and access over the private Sentinel network",
      "type" => "object",
      "properties" => %{
        "id" => %{
          "type" => "string",
          "description" => "The Id of the Artifact instance",
          "ui:widget" => "hidden",
        },
        "enabled" => %{
          "type" => "boolean",
          "description" => "Enable or disable artifact availibility to other trusted users",
        },
        "route" => %{
          "type" => "string",
          "description" => "The route or path on your server that the trusted user will trigger when interacting with your schema",
        },
        "schema" => %{
          "type" => "string",
          "description" => "The JSON schema in which the trusted user will render to interact with your artifact",
          "ui:widget" => "textarea"
        }
      },
      "required" => ["enabled", "route", "schema"]
    }
  end
end
