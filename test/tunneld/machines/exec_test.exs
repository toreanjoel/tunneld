defmodule Tunneld.Machines.ExecTest do
  use ExUnit.Case, async: false

  alias Tunneld.Machines.Exec

  # mock_data is on in test.exs, so Exec uses the mock shell.

  test "mock exec starts and streams a welcome message" do
    {:ok, pid} = Exec.start(%{"id" => "test"}, "mock-app", self())

    assert_receive {:exec_output, output}, 500
    assert String.contains?(output, "Welcome to mock Incus container")
    Exec.stop(pid)
  end

  test "mock exec echoes input commands" do
    {:ok, pid} = Exec.start(%{"id" => "test2"}, "mock-app", self())
    assert_receive {:exec_output, _}, 500

    :ok = Exec.send_input(pid, "whoami\r")

    assert_receive {:exec_output, output}, 500
    assert String.contains?(output, "root")
    Exec.stop(pid)
  end

  test "mock exec handles unknown commands" do
    {:ok, pid} = Exec.start(%{"id" => "test3"}, "mock-app", self())
    assert_receive {:exec_output, _}, 500

    :ok = Exec.send_input(pid, "foobar\r")

    assert_receive {:exec_output, output}, 500
    assert String.contains?(output, "command not found")
    Exec.stop(pid)
  end

  test "stop sends exit to channel" do
    {:ok, pid} = Exec.start(%{"id" => "test4"}, "mock-app", self())
    assert_receive {:exec_output, _}, 500

    :ok = Exec.stop(pid)
    assert_receive {:exec_exit, _}, 1000
  end
end