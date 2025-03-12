defmodule Cloudflare do
  @moduledoc """
  The cloudflare helper module that will be used in order to interact with the APIs to forward tunnel trafic to that device
  """
  @cloudflare_api "https://api.cloudflare.com/client/v4/user"
  @account_id "YOUR_ACCOUNT_ID"
  @tunnel_id "YOUR_TUNNEL_ID"
  @api_token "YOUR_CLOUDFLARE_API_TOKEN"

  def expose_service(subdomain, ip, port) do
    #TODO
    :ok
  end
end
