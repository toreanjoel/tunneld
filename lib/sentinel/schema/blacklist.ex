defmodule Sentinel.Schema.Blacklist do
  @moduledoc """
  Blacklist JSON Schema - reference the relevant one in order to get the data tied to either user or system wide
  """

  @spec data(atom()) :: map()
  @doc """
  The JSON schema data that will be used to render the form structure.
  """
  def data(:user) do
    %{
      "title" => "Blacklist - User",
      "description" => "Blocking a domain for a specific user",
      "type" => "object",
      "properties" => %{
        "domain" => %{
          "type" => "string",
          "description" => "The domain name to be blacklisted",
          "minLength" => 1
        },
        "mac" => %{
          "type" => "string",
          # This below is just for reference but it throws errors, when empty, we pass the values for this dynamically
          # This is not needed to be described here but will be added at runtime in the renderer
          # "enum" => [],
          "description" => "The MAC address of the user to be blacklisted (only required for user-level blocking)"
        },
        "ttl" => %{
          "type" => "string",
          "description" => "Time-to-live (TTL) for the blacklist entry (in minutes)",
          "minimum" => 1
        }
      },
      "required" => ["domain"]
    }
  end

  def data(:system) do
    %{
      "title" => "Blacklist - System",
      "description" => "Blocking a domain system wide",
      "type" => "object",
      "properties" => %{
        "domain" => %{
          "type" => "string",
          "description" => "The domain name to be blacklisted",
          "minLength" => 1
        },
        "ttl" => %{
          "type" => "string",
          "description" => "Time-to-live (TTL) for the blacklist entry (in minutes)",
          "minimum" => 1
        }
      },
      "required" => ["domain"]
    }
  end
end
