defmodule SentinelWeb.Controllers.FileDownloadController do
  @moduledoc """
  Download the file
  """
  use SentinelWeb, :controller

  @log_dir System.user_home() <> "/logs"

  def download(conn, %{"name" => file_name}) do
    file_path = @log_dir <> "/#{file_name}"

    if File.exists?(file_path) do
      conn
      |> put_resp_header("content-disposition", "attachment; filename=\"#{file_name}\"")
      |> send_file(200, file_path)
    else
      # TODO: change this so that we can fix the toasts that are needed
      conn
      |> fetch_flash()
      |> put_flash(:error, "File not found")
      |> send_resp(204, "")
    end
  end
end
