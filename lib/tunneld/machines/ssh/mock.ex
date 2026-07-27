defmodule Tunneld.Machines.SSH.Mock do
  @moduledoc """
  Simulated SSH target for development without a real Linux+Incus box.

  Recognises the small set of commands the Provider module issues
  (incus version/list/storage, nproc, free, lscpu, lspci) and returns
  plausible output so the full enroll -> probe -> list_containers loop
  works end-to-end on a laptop with `MOCK_DATA=1`.
  """

  @doc "Mock run of a command on a fake Incus host."
  def run(_machine, command, _opts) do
    {:ok, mock_output(command)}
  end

  defp mock_output("incus version") do
    "Incus 6.0.0\n"
  end

  defp mock_output("incus list --format json") do
    Jason.encode!([
      %{
        "name" => "mock-app",
        "status" => "Running",
        "type" => "container",
        "ipv4" => "10.10.0.42",
        "image" => "ubuntu/24.04"
      },
      %{
        "name" => "mock-vm",
        "status" => "Stopped",
        "type" => "virtual-machine",
        "ipv4" => "",
        "image" => "ubuntu/24.04"
      }
    ])
  end

  defp mock_output("incus storage list --format json") do
    Jason.encode!([%{"name" => "default", "driver" => "dir", "used_by" => 2}])
  end

  defp mock_output("nproc") do
    "4\n"
  end

  defp mock_output("free -m | awk '/^Mem:/ {print $2}'") do
    "8192\n"
  end

  defp mock_output("lscpu | grep -i kvm") do
    "Virtualization: kvm\n"
  end

  defp mock_output("lspci | grep -i vga") do
    ""
  end

  defp mock_output("test -x /usr/bin/incus && echo yes || echo no") do
    "yes\n"
  end

  defp mock_output("cat /etc/os-release | grep ^PRETTY_NAME") do
    "PRETTY_NAME=\"Ubuntu 24.04 LTS\"\n"
  end

  defp mock_output(_other) do
    ""
  end
end