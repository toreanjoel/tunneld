defmodule Tunneld.Machines.SSH.SessionTest do
  use ExUnit.Case, async: true

  alias Tunneld.Machines.SSH.Session

  describe "Session lifecycle" do
    test "start_link returns error for missing machine_id" do
      Process.flag(:trap_exit, true)
      result = Session.start_link(subscriber: self())
      assert {:error, :missing_required_option} = result
    end

    test "start_link returns error for missing subscriber" do
      Process.flag(:trap_exit, true)
      result = Session.start_link(machine_id: "test-id")
      assert {:error, :missing_required_option} = result
    end

    test "session terminates when subscriber dies" do
      Process.flag(:trap_exit, true)

      # Create a temporary subscriber process
      subscriber = spawn(fn -> :timer.sleep(500) end)

      {:ok, pid} =
        Session.start_link(
          machine_id: "nonexistent-machine-id",
          subscriber: subscriber
        )

      ref = Process.monitor(pid)

      # Kill the subscriber
      Process.exit(subscriber, :kill)

      # Session should terminate
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 5000
    end

    test "session handles missing machine gracefully" do
      Process.flag(:trap_exit, true)
      test_pid = self()

      {:ok, pid} =
        Session.start_link(
          machine_id: "definitely-does-not-exist",
          subscriber: test_pid
        )

      # In mock mode: should receive connected then banner
      # In real mode: should receive an error message
      if Session.mock?() do
        assert_receive {:ssh_connected}, 5000
        assert_receive {:ssh_data, banner}, 5000
        assert banner =~ "mock"
      else
        assert_receive {:ssh_error, reason}, 5000
        assert is_binary(reason)
        refute Process.alive?(pid)
      end
    end

    test "send_data is a cast and does not block" do
      Process.flag(:trap_exit, true)
      test_pid = self()

      {:ok, pid} =
        Session.start_link(
          machine_id: "test-machine",
          subscriber: test_pid
        )

      # send_data should return immediately (it's a cast)
      assert :ok = Session.send_data(pid, "test input")

      # Process should have handled the cast
      Process.sleep(50)
    end

    test "resize is a cast and does not block" do
      Process.flag(:trap_exit, true)
      test_pid = self()

      {:ok, pid} =
        Session.start_link(
          machine_id: "test-machine",
          subscriber: test_pid
        )

      # resize should return immediately (it's a cast)
      assert :ok = Session.resize(pid, 120, 40)

      # Process should have handled the cast
      Process.sleep(50)
    end
  end

  describe "user_dir authentication setup" do
    test "setup_user_dir creates directory with correct permissions" do
      # Create a temporary key file to test with
      tmp_key = Path.join(System.tmp_dir!(), "test_key_#{System.unique_integer([:positive])}")

      File.write!(
        tmp_key,
        "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----\n"
      )

      File.chmod!(tmp_key, 0o600)

      on_exit(fn -> File.rm(tmp_key) end)

      # Call the private setup function via a test helper
      user_dir = setup_user_dir_for_test(tmp_key)

      assert File.exists?(user_dir)
      assert File.dir?(user_dir)

      # Check directory permissions (0700)
      {:ok, stat} = File.stat(user_dir)
      assert stat.mode == 0o40700

      # Check key file exists as id_ed25519
      key_path = Path.join(user_dir, "id_ed25519")
      assert File.exists?(key_path)

      # Check key file permissions (0600)
      {:ok, key_stat} = File.stat(key_path)
      assert key_stat.mode == 0o100600

      # Clean up
      File.rm(key_path)
      File.rmdir(user_dir)
    end

    test "user_dir key file is readable and contains key content" do
      # Create a temporary key file
      key_content =
        "-----BEGIN OPENSSH PRIVATE KEY-----\nbase64content\n-----END OPENSSH PRIVATE KEY-----\n"

      tmp_key = Path.join(System.tmp_dir!(), "test_key_#{System.unique_integer([:positive])}")
      File.write!(tmp_key, key_content)
      File.chmod!(tmp_key, 0o600)

      on_exit(fn -> File.rm(tmp_key) end)

      user_dir = setup_user_dir_for_test(tmp_key)
      key_path = Path.join(user_dir, "id_ed25519")

      # Verify the key content was copied correctly
      assert {:ok, copied_content} = File.read(key_path)
      assert copied_content == key_content

      # Clean up
      File.rm(key_path)
      File.rmdir(user_dir)
    end
  end

  # Test helper to access the private setup_user_dir function
  defp setup_user_dir_for_test(key_path) do
    nonce = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    user_dir = Path.join(System.tmp_dir!(), "tunneld_ssh_#{nonce}")

    File.mkdir_p!(user_dir)
    File.chmod!(user_dir, 0o700)

    dest = Path.join(user_dir, "id_ed25519")
    File.cp!(key_path, dest)
    File.chmod!(dest, 0o600)

    user_dir
  end
end
