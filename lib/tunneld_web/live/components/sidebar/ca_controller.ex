defmodule TunneldWeb.CAController do
  use TunneldWeb, :controller

  def download(conn, _params) do
    certs_config = Application.get_env(:tunneld, :certs) || []
    ca_dir = certs_config[:ca_dir]
    ca_file = certs_config[:ca_file]

    if ca_dir && ca_file do
      # Ensure the path is absolute and correctly resolved
      ca_path = Path.expand(Path.join(ca_dir, ca_file))

      if File.exists?(ca_path) do
        conn
        |> put_resp_content_type("application/x-x509-ca-cert")
        |> put_resp_header("content-disposition", "attachment; filename=\"#{ca_file}\"")
        |> send_file(200, ca_path)
      else
        conn |> put_status(404) |> text("Certificate file not found.")
      end
    else
      conn |> put_status(500) |> text("CA configuration is missing or incomplete.")
    end
  end
end
