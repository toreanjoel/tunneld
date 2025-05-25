defmodule Sentinel.Schema.Instance do
  @moduledoc """
  Instance JSON Schema - This is the schema that will be used to generate a form how we interact with instance
  """

  @spec data(atom()) :: map()
  @doc """
  The JSON schema data that will be used to render the form structure.
  """
  def data(:add) do
    %{
      "title" => "Instance Add",
      "description" => "Add a reference to a device running on the sentinel network",
      "type" => "object",
      "properties" => %{
        "name" => %{
          "type" => "string",
          "description" => "Name the instance to make it easy to reference",
          "minLength" => 1
        },
        "icon" => %{
          "type" => "string",
          "description" => "Choose basic icon to represent instance",
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
      "required" => ["ip", "port", "name", "icon"]
    }
  end
end
