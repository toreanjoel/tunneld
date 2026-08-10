defmodule TunneldWeb.ExecChannelTest do
  use TunneldWeb.ChannelCase, async: false

  alias TunneldWeb.UserSocket

  describe "authorization" do
    test "rejects join without valid session" do
      # Connect without a valid client_id
      # no session at all
      assert :error = connect(UserSocket, %{}, connect_info: %{session: %{}})
      assert :error = connect(UserSocket, %{}, connect_info: %{})
      # a session that is not a live one
      assert :error =
               connect(UserSocket, %{},
                 connect_info: %{session: %{"client_id" => "not-a-session"}}
               )

      assert :error = connect(UserSocket, %{}, connect_info: %{session: %{"client_id" => ""}})

      # REGRESSION: a client_id supplied as a socket PARAM must never authenticate,
      # even if it is a genuinely valid session id. Auth comes from the signed
      # HttpOnly session cookie only - params are attacker-controlled.
      valid = UUID.uuid4()
      Tunneld.Servers.Session.create(valid)
      assert :error = connect(UserSocket, %{"client_id" => valid})
      assert :error = connect(UserSocket, %{"client_id" => valid}, connect_info: %{session: %{}})
    end

    test "accepts connection with valid session" do
      # Create a valid session
      client_id = "test-client-#{System.unique_integer([:positive])}"
      {:ok, _} = Tunneld.Servers.Session.create(client_id)

      # Connect with valid client_id
      {:ok, socket} =
        connect(UserSocket, %{}, connect_info: %{session: %{"client_id" => client_id}})

      assert socket.assigns.client_id == client_id
    end

    test "rejects channel join for non-existent machine" do
      # Create a valid session
      client_id = "test-client-#{System.unique_integer([:positive])}"
      {:ok, _} = Tunneld.Servers.Session.create(client_id)

      {:ok, socket} =
        connect(UserSocket, %{}, connect_info: %{session: %{"client_id" => client_id}})

      # Try to join a channel for a machine that doesn't exist
      assert {:error, %{reason: "Machine not found"}} =
               subscribe_and_join(socket, "exec:nonexistent-machine")
    end

    test "socket connection validates session on connect" do
      # Invalid session should fail at socket connect level
      assert :error = connect(UserSocket, %{"client_id" => "definitely-not-valid"})
    end
  end

  describe "channel module structure" do
    test "channel module is defined and uses Phoenix.Channel" do
      # Verify the module exists and has the expected structure
      assert Code.ensure_loaded?(TunneldWeb.ExecChannel)

      # Phoenix channels define join/3
      assert {:join, 3} in TunneldWeb.ExecChannel.__info__(:functions)
    end

    test "channel module defines handle_in callback" do
      # Phoenix channels compile handle_in clauses into a single function
      assert {:handle_in, 3} in TunneldWeb.ExecChannel.__info__(:functions)
    end

    test "channel module defines terminate callback" do
      # Verify cleanup is implemented
      assert {:terminate, 2} in TunneldWeb.ExecChannel.__info__(:functions)
    end
  end
end
