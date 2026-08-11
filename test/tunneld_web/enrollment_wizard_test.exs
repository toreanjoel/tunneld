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
end
