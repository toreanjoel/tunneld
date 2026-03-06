defmodule Tunneld.Servers.ServicesTest do
  use ExUnit.Case, async: false

  alias Tunneld.Servers.Services

  setup do
    # Ensure Services GenServer is running
    unless Process.whereis(Services), do: Services.start_link([])
    :ok
  end

  describe "get_service_logs/1" do
    test "rejects unknown service names" do
      # This should not create a new atom — the safe lookup prevents it
      assert {:error, _} = Services.get_service_logs("malicious_service_name")
    end

    test "accepts known service names" do
      # In test/mock environment systemctl won't work, but the service name
      # should pass validation. The function may return ok with empty string
      # due to the rescue clause.
      result = Services.get_service_logs("dnsmasq")
      assert match?({:ok, _}, result)
    end
  end
end
