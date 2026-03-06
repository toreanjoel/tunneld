defmodule Tunneld.Servers.NginxTest do
  use ExUnit.Case, async: false

  alias Tunneld.Servers.Nginx

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "tunneld_nginx_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_dir)

    cert_dir = Path.join(tmp_dir, "certs")
    ca_dir = Path.join(tmp_dir, "ca")
    File.mkdir_p!(cert_dir)
    File.mkdir_p!(ca_dir)

    original_fs = Application.get_env(:tunneld, :fs)
    original_mock = Application.get_env(:tunneld, :mock_data)
    original_certs = Application.get_env(:tunneld, :certs)

    Application.put_env(:tunneld, :fs, root: tmp_dir, auth: "auth.json", resources: "resources.json")
    Application.put_env(:tunneld, :mock_data, true)
    Application.put_env(:tunneld, :certs, cert_dir: cert_dir, ca_dir: ca_dir, ca_file: "rootCA.key")

    on_exit(fn ->
      Application.put_env(:tunneld, :fs, original_fs)
      Application.put_env(:tunneld, :mock_data, original_mock)
      Application.put_env(:tunneld, :certs, original_certs)
      File.rm_rf!(tmp_dir)
    end)

    %{tmp_dir: tmp_dir}
  end

  describe "get_private_port/1" do
    test "returns a deterministic port for the same name" do
      port1 = Nginx.get_private_port("my-service")
      port2 = Nginx.get_private_port("my-service")
      assert port1 == port2
    end

    test "returns different ports for different names" do
      port1 = Nginx.get_private_port("service-a")
      port2 = Nginx.get_private_port("service-b")
      assert port1 != port2
    end

    test "returns a port in the valid range" do
      port = Nginx.get_private_port("test-service")
      assert port >= 20000
      assert port < 30000
    end
  end

  describe "upsert_resource_config/1" do
    test "creates nginx config files for a resource", %{tmp_dir: tmp_dir} do
      resource = %{
        "id" => "test-resource-1",
        "name" => "test-app",
        "ip" => "127.0.0.1",
        "port" => "18000",
        "pool" => ["192.168.1.10:8080"],
        "tunneld" => %{
          "reserved" => %{
            "public" => "testapppub",
            "private" => "testapppriv"
          }
        }
      }

      assert :ok = Nginx.upsert_resource_config(resource)

      available_path = Path.join([tmp_dir, "nginx", "sites-available", "tunneld_test-resource-1"])
      assert File.exists?(available_path)

      enabled_path = Path.join([tmp_dir, "nginx", "sites-enabled", "tunneld_test-resource-1"])
      assert File.exists?(enabled_path)

      content = File.read!(available_path)
      assert content =~ "upstream tunneld_test-resource-1_pool"
      assert content =~ "server 192.168.1.10:8080;"
      assert content =~ "listen 127.0.0.1:18000"
    end

    test "returns error for resource without pool" do
      resource = %{"id" => "bad", "pool" => []}
      assert {:error, :invalid_pool} = Nginx.upsert_resource_config(resource)
    end

    test "returns error for invalid resource" do
      assert {:error, :invalid_resource} = Nginx.upsert_resource_config(%{"name" => "no-id"})
    end
  end

  describe "remove_resource_config/1" do
    test "removes config files", %{tmp_dir: tmp_dir} do
      resource = %{
        "id" => "to-remove",
        "name" => "rm-app",
        "ip" => "127.0.0.1",
        "port" => "18000",
        "pool" => ["10.0.0.5:3000"],
        "tunneld" => %{
          "reserved" => %{"public" => "rmapppub", "private" => "rmapppriv"}
        }
      }

      Nginx.upsert_resource_config(resource)

      available_path = Path.join([tmp_dir, "nginx", "sites-available", "tunneld_to-remove"])
      assert File.exists?(available_path)

      Nginx.remove_resource_config("to-remove")
      refute File.exists?(available_path)
    end

    test "returns error for invalid id" do
      assert {:error, :invalid_resource} = Nginx.remove_resource_config(nil)
    end
  end
end
