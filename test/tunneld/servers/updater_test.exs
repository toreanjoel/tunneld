defmodule Tunneld.Servers.UpdaterTest do
  use ExUnit.Case, async: false

  alias Tunneld.Servers.Updater

  setup do
    # Ensure Updater is running (it's in the supervision tree)
    unless Process.whereis(Updater), do: Updater.start_link([])
    :ok
  end

  describe "get_status/0" do
    test "returns a map with is_latest and new_version keys" do
      status = Updater.get_status()
      assert Map.has_key?(status, :is_latest)
      assert Map.has_key?(status, :new_version)
    end
  end
end
