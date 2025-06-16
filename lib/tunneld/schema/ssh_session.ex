defmodule Tunneld.Schema.SshSession do
  @moduledoc """
  SshSession JSON Schema - The form that will trigger and open the ssh instance
  """

  @spec data() :: map()
  @doc """
  The JSON schema data that will be used to render the form structure.
  """
  def data() do
    %{
      "title" => "SSH Session",
      "description" => "Starts a ssh session against a given device",
      "type" => "object",
      "properties" => %{
        "user" => %{
          "type" => "string",
          "description" => "The user account associated with a device for SSH access",
          "minLength" => 1
        },
        "ip" => %{
          "type" => "string",
          "description" => "The IP address of the machine requesting access to",
        }
      },
      "required" => ["ip", "user"]
    }
  end
end
