defmodule Tunneld.Schema.Wireguard do
  @moduledoc """
  JSON Schema definitions for WireGuard peer creation form.
  """

  def data(:add_peer) do
    %{
      "type" => "object",
      "required" => ["name"],
      "properties" => %{
        "name" => %{
          "type" => "string",
          "minLength" => 1,
          "maxLength" => 64,
          "title" => "Peer Name",
          "description" => "A name to identify this device (e.g. 'Phone', 'Laptop')"
        },
        "full_tunnel" => %{
          "type" => "boolean",
          "title" => "Full Tunnel",
          "description" => "Route all internet traffic through the VPN",
          "default" => false
        }
      },
      "ui:order" => ["name", "full_tunnel"]
    }
  end
end