defmodule Sentinel.Schema.Login do
  @moduledoc """
  Login schema used to log into the system
  """

  @spec data() :: map()
  @doc """
  The JSON schema data that will be used to render the form structure.
  """
  def data() do
    %{
      "title" => "Blacklist - User",
      "description" => "Blocking a domain for a specific user",
      "type" => "object",
      "properties" => %{
        "name" => %{
          "type" => "string",
          "description" => "The device user account",
        },
        "password" => %{
          "type" => "string",
          "description" => "Password associated with the user account",
        }
      },
      "required" => ["name", "password"]
    }
  end
end
