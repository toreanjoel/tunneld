defmodule Tunneld.Schema.Zrok do
  @moduledoc """
  Connecting and interacting with the overlay network and enabling devices on an account
  """

  @spec data(:endpoint) :: map()
  def data(:endpoint) do
    %{
      "title" => "Set the endpoint network to connect to",
      "description" => "The network endpoint (control plane) that you will have this device connected under",
      "type" => "object",
      "properties" => %{
        "url" => %{
          "type" => "string",
          "description" => "The URL endpoint of the control plane",
        },
      },
      "required" => ["url"]
    }
  end

  @spec data(:conf_device) :: map()
  def data(:conf_device) do
    %{
      "title" => "Enable device on an account",
      "description" => "Connect this device as an environment on an account for the control plane you are connected to",
      "type" => "object",
      "properties" => %{
        "account_token" => %{
          "type" => "string",
          "description" => "The account token to enable this device against",
        },
      },
      "required" => ["account_token"]
    }
  end
end
