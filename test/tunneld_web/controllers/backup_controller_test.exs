defmodule TunneldWeb.BackupControllerTest do
  use TunneldWeb.ConnCase, async: false

  describe "GET /download/backup" do
    test "returns a JSON backup file", %{conn: conn} do
      conn = get(conn, "/download/backup")
      assert response_content_type(conn, :json)
      assert conn.status == 200

      body = Jason.decode!(conn.resp_body)
      assert body["tunneld_backup"] == true
      assert is_binary(body["exported_at"])
      assert is_map(body["data"])
    end
  end

  describe "POST /restore/backup" do
    test "rejects requests without a file", %{conn: conn} do
      conn = post(conn, "/restore/backup", %{})
      assert conn.status == 400
    end

    test "rejects invalid backup files", %{conn: conn} do
      # Create a temp file with invalid content
      path = Path.join(System.tmp_dir!(), "bad-backup.json")
      File.write!(path, Jason.encode!(%{"not" => "a backup"}))

      upload = %Plug.Upload{path: path, filename: "bad-backup.json", content_type: "application/json"}
      conn = post(conn, "/restore/backup", %{"backup" => upload})
      assert conn.status == 400

      File.rm(path)
    end
  end
end
