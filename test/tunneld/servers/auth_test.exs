defmodule Tunneld.Servers.AuthTest do
  use ExUnit.Case, async: false

  alias Tunneld.Servers.Auth

  setup do
    # Use a temp directory for auth file operations
    tmp_dir = Path.join(System.tmp_dir!(), "tunneld_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_dir)

    original_fs = Application.get_env(:tunneld, :fs)
    Application.put_env(:tunneld, :fs, root: tmp_dir, auth: "auth.json")

    on_exit(fn ->
      Application.put_env(:tunneld, :fs, original_fs)
      File.rm_rf!(tmp_dir)
    end)

    %{tmp_dir: tmp_dir}
  end

  describe "file_exists?/0" do
    test "returns false when no auth file exists" do
      refute Auth.file_exists?()
    end

    test "returns true after creating auth file" do
      Auth.create_file("admin", "password123")
      assert Auth.file_exists?()
    end
  end

  describe "create_file/2" do
    test "creates auth file with hashed password" do
      assert {:ok, "Auth file created"} = Auth.create_file("admin", "secret")

      {:ok, data} = Auth.read_file()
      assert data["user"] == "admin"
      assert Bcrypt.verify_pass("secret", data["pass"])
      assert data["hide_login"] == false
    end
  end

  describe "read_file/0" do
    test "returns error when file does not exist" do
      assert {:error, _} = Auth.read_file()
    end

    test "returns decoded data after creation" do
      Auth.create_file("admin", "pass")
      assert {:ok, %{"user" => "admin"}} = Auth.read_file()
    end
  end

  describe "path/0" do
    test "returns the correct path" do
      path = Auth.path()
      assert String.ends_with?(path, "auth.json")
    end
  end
end
