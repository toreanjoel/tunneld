defmodule TunneldWeb.CAController do
  use TunneldWeb, :controller

  def download(conn, _params) do
    certs_config = Application.get_env(:tunneld, :certs)
    ca_path = Path.join(certs_config[:ca_dir], certs_config[:ca_file])

    conn
    |> put_resp_content_type("application/x-x509-ca-cert")
    |> put_resp_header(
      "content-disposition",
      "attachment; filename=\"#{certs_config[:ca_file]}\""
    )
    |> send_file(200, ca_path)
  end
end
