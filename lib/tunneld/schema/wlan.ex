defmodule Tunneld.Schema.Wlan do
  @moduledoc """
  Wlan to interact or connect device to public networks
  """

  @spec data(%{ title: String.t() }) :: map()
  @doc """
  The JSON schema data that will be used to render the form structure.
  """
  def data(%{ title: title }) do
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
end
