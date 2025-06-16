defmodule Tunneld.Schema.Signup do
  @moduledoc """
  Signup schema used to log into the system
  """

  @spec data() :: map()
  @doc """
  The JSON schema data that will be used to render the form structure.
  """
  def data() do
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
end
