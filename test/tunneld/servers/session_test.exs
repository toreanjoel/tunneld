defmodule Tunneld.Servers.SessionTest do
  use ExUnit.Case, async: false

  alias Tunneld.Servers.Session

  setup do
    # Ensure the Session GenServer is running (may have been killed by another test)
    unless GenServer.whereis(Session), do: Session.start_link([])
    :ok
  end

  describe "create/1" do
    test "creates a new session" do
      assert {:ok, "Session Created"} = Session.create("10.0.0.1")
    end

    test "overwrites an existing session" do
      {:ok, _} = Session.create("10.0.0.1")
      {:ok, first_session} = Session.get("10.0.0.1")

      # Small delay to get a different timestamp
      Process.sleep(1100)
      {:ok, _} = Session.create("10.0.0.1")
      {:ok, second_session} = Session.get("10.0.0.1")

      assert second_session.expires_at >= first_session.expires_at
    end
  end

  describe "get/1" do
    test "returns the session when it exists and is valid" do
      Session.create("10.0.0.1")
      assert {:ok, %{expires_at: _}} = Session.get("10.0.0.1")
    end

    test "returns error for non-existent session" do
      assert {:error, "Session not found"} = Session.get("10.0.0.99")
    end
  end

  describe "valid?/1" do
    test "returns true for a valid session" do
      Session.create("10.0.0.1")
      assert Session.valid?("10.0.0.1")
    end

    test "returns false for a non-existent session" do
      refute Session.valid?("10.0.0.99")
    end
  end

  describe "renew/1" do
    test "renews a valid session" do
      Session.create("10.0.0.1")
      assert :ok = Session.renew("10.0.0.1")
    end

    test "returns error for non-existent session" do
      assert {:error, "Session not found"} = Session.renew("10.0.0.99")
    end
  end

  describe "delete/1" do
    test "deletes an existing session" do
      Session.create("10.0.0.1")
      assert {:ok, "Session deleted"} = Session.delete("10.0.0.1")
      refute Session.valid?("10.0.0.1")
    end

    test "returns error for non-existent session" do
      assert {:error, "Session not found"} = Session.delete("10.0.0.99")
    end
  end

  describe "multiple sessions" do
    test "manages independent sessions by IP" do
      Session.create("10.0.0.1")
      Session.create("10.0.0.2")

      assert Session.valid?("10.0.0.1")
      assert Session.valid?("10.0.0.2")

      Session.delete("10.0.0.1")

      refute Session.valid?("10.0.0.1")
      assert Session.valid?("10.0.0.2")
    end
  end
end
