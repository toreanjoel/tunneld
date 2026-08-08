defmodule Tunneld.Schema.Machine do
  @moduledoc """
  Machine enrollment JSON Schema - rendered as a form by `JsonSchemaRenderer`.
  """

  @spec data() :: map()
  @doc "The JSON schema data used to render the machine enrollment form."
  def data do
    %{
      "title" => "Enroll Machine",
      "description" =>
        "Register a machine (local or remote) to manage Incus containers and VMs over SSH. After enrolling, the modal shows the SSH key to install and the passwordless-sudo setup required for Incus install.",
      "type" => "object",
      "ui:order" => ["name", "address", "ssh_port", "ssh_user", "location"],
      "properties" => %{
        "name" => %{
          "type" => "string",
          "description" => "A human-friendly label for this machine.",
          "ui:help" =>
            "Used across the dashboard to identify this machine (e.g. office-box, vps-1).",
          "minLength" => 1
        },
        "address" => %{
          "type" => "string",
          "description" => "Hostname or IP address of the machine.",
          "ui:help" =>
            "A subnet IP (e.g. 10.0.0.5) for local machines, or a public address for a remote VPS.",
          "minLength" => 1
        },
        "ssh_port" => %{
          "type" => "integer",
          "default" => 22,
          "description" => "SSH port on the target.",
          "minimum" => 1,
          "maximum" => 65535
        },
        "ssh_user" => %{
          "type" => "string",
          "default" => "root",
          "description" => "SSH user to connect as on the target.",
          "ui:help" =>
            "The user tunneld will SSH in as. It needs passwordless sudo (for Incus install) and access to Incus (e.g. add it to the incus group)."
        },
        "location" => %{
          "type" => "string",
          "enum" => ["local", "remote"],
          "default" => "local",
          "description" => "Where the machine is reachable from.",
          "ui:help" =>
            "Local machines sit on this gateway's subnet and can use macvlan containers. Remote machines are reached over the internet and use NAT-bridged containers."
        }
      },
      "required" => ["name", "address", "location"]
    }
  end
end
