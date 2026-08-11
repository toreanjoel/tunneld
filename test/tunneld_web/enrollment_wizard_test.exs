defmodule TunneldWeb.EnrollmentWizardTest do
  # The wizard's job at step 4 is to say, truthfully, what happened on the
  # target. These tests drive the real handle_async/3 callbacks, because the
  # bug they guard against was never in the markup - it was a result shape that
  # no clause matched, silently falling through to a success-shaped message.
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias TunneldWeb.Live.Components.EnrollmentWizard

  defp socket do
    %Phoenix.LiveView.Socket{}
    |> assign(:overlay_status, :installing)
    |> assign(:overlay_error, nil)
    |> assign(:exit_status, :installing)
    |> assign(:exit_error, nil)
  end

  defp run(result) do
    {:noreply, s} = EnrollmentWizard.handle_async(:setup_machine, {:ok, result}, socket())
    s.assigns
  end

  test "both steps succeeding reports both as successful" do
    a =
      run(%{
        overlay: {:ok, %{overlay_ip: "10.88.0.3"}},
        exit: {:ok, %{iface: "eth0", table: "100"}}
      })

    assert a.overlay_status == :success
    assert a.exit_status == :success
    assert a.overlay_error == nil
    assert a.exit_error == nil
  end

  test "a failed exit step does not taint a working overlay" do
    a =
      run(%{
        overlay: {:ok, %{overlay_ip: "10.88.0.3"}},
        exit: {:error, :no_default_route_on_target}
      })

    assert a.overlay_status == :success
    assert a.exit_status == :failed
    assert a.exit_error =~ "no_default_route_on_target"
  end

  test "exit is skipped, not failed, when the overlay never came up" do
    a = run(%{overlay: {:error, "unreachable"}, exit: :skipped})

    assert a.overlay_status == :failed
    assert a.overlay_error == "unreachable"
    assert a.exit_status == :skipped
  end

  # The regression that produced "Exit node configured for <uuid>": a result
  # shape nothing matched. Unknown must read as failure, never as success.
  test "an unrecognised result for either step is reported as a failure" do
    a = run(%{overlay: {:ok, %{}}, exit: :ok_i_guess})

    assert a.overlay_status == :success
    assert a.exit_status == :failed
    assert a.exit_error =~ "Unrecognised result"
  end

  test "an unrecognised envelope fails both steps rather than claiming success" do
    {:noreply, s} = EnrollmentWizard.handle_async(:setup_machine, {:ok, :surprise}, socket())

    assert s.assigns.overlay_status == :failed
    assert s.assigns.exit_status == :failed
  end

  test "a crashed task fails both steps" do
    {:noreply, s} = EnrollmentWizard.handle_async(:setup_machine, {:exit, :killed}, socket())

    assert s.assigns.overlay_status == :failed
    assert s.assigns.exit_status == :failed
    assert s.assigns.overlay_error =~ "Task failed"
  end

  # Closing the wizard used to `send(socket.parent_pid, :wizard_closed)`, which
  # raised `:erlang.send(nil, :wizard_closed)` - "invalid destination" - the
  # moment anyone dismissed the wizard after a successful enrollment. A
  # live_component has no process of its own, so its callbacks already run in
  # the parent LiveView's process: `self()` is the parent. `parent_pid` means
  # the *nested LiveView* parent and is nil for a root LiveView like Dashboard.
  test "closing the wizard notifies the LiveView process, not parent_pid" do
    {:noreply, s} =
      EnrollmentWizard.handle_event("wizard_close", %{}, assign(socket(), :open, true))

    assert_receive :wizard_closed
    refute s.assigns.open
  end

  # A live_component is mounted once per id and reused, so mount/1 does not run
  # again on reopen. Enrolling a second machine reopened the wizard on step 4
  # showing the FIRST machine's success screen; only a page refresh cleared it.
  defp finished_socket do
    socket()
    |> assign(:open, false)
    |> assign(:step, 4)
    |> assign(:machine, %{"id" => "old-machine"})
    |> assign(:machine_id, "old-machine")
    |> assign(:public_key, "ssh-ed25519 AAAA-old")
    |> assign(:overlay_status, :success)
    |> assign(:exit_status, :success)
  end

  test "reopening the wizard resets it to step 1 instead of the last success screen" do
    {:ok, s} = EnrollmentWizard.update(%{open: true}, finished_socket())

    assert s.assigns.step == 1
    assert s.assigns.machine == nil
    assert s.assigns.machine_id == nil
    assert s.assigns.public_key == nil
    assert s.assigns.overlay_status == nil
    assert s.assigns.exit_status == nil
    assert s.assigns.open
  end

  # The parent re-renders this component constantly; resetting on every update
  # would wipe a half-finished enrollment (e.g. the public key on step 2).
  test "re-rendering while already open does not wipe enrollment progress" do
    in_progress = finished_socket() |> assign(:open, true) |> assign(:step, 2)

    {:ok, s} = EnrollmentWizard.update(%{open: true}, in_progress)

    assert s.assigns.step == 2
    assert s.assigns.public_key == "ssh-ed25519 AAAA-old"
  end

  test "closing does not reset, so the success screen survives until reopen" do
    {:ok, s} = EnrollmentWizard.update(%{open: false}, finished_socket() |> assign(:open, true))

    assert s.assigns.step == 4
    refute s.assigns.open
  end
end
