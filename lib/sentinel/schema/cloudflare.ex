defmodule Sentinel.Schema.Cloudflare do
  @moduledoc """
  Setup Cloudflare tunnels and form to help setup the domain for a running services
  """

  @spec data(atom()) :: map()
  @doc """
  The JSON schema data that will be used to render the form structure.
  """
  def data(:add) do
    %{
      "title" => "Connect to Cloudflare Tunnel",
      "description" => "Connect a local running service to a Cloudflared domain",
      "type" => "object",
      "properties" => %{
        "domain" => %{
          "type" => "string",
          "description" => "The domain on cloudflare you want to connect the service to",
          "minLength" => 1,
        },
        "service" => %{
          "type" => "string",
          "description" => "The service that will be tunneled to",
          "readOnly" => true
        }
      },
      "required" => ["domain", "service"]
    }
  end
end
