defmodule Tunneld.Machines.SSH.Mock do
  @moduledoc """
  Simulated SSH target for development without a real remote box.

  Provides mock responses for the commands that Tunneld.Machines.Runtime uses
  during probe operations (nproc, free, uname, os-release, ss). Returns plausible
  output so the enroll -> probe -> list loop works end-to-end with `MOCK_DATA=1`.
  """

  require Logger

  @doc "Mock run of a command on a fake remote host."
  def run(_machine, command, _opts) do
    {:ok, mock_output(command)}
  end

  defp mock_output("nproc") do
    "4\n"
  end

  defp mock_output("free -m | awk '/^Mem:/ {print $2}'") do
    "8192\n"
  end

  defp mock_output("ip route | awk '/^default/ {print $5; exit}'") do
    "eth0\n"
  end

  defp mock_output("cat /etc/os-release | grep ^PRETTY_NAME") do
    "PRETTY_NAME=\"Ubuntu 24.04 LTS\"\n"
  end

  defp mock_output("ss -tlnp 2>/dev/null || ss -tln 2>/dev/null") do
    "State   Recv-Q  Send-Q   Local Address:Port   Peer Address:Port   Process\n" <>
      "LISTEN  0       4096     0.0.0.0:22           0.0.0.0:*           users:((\"sshd\",pid=1234,fd=3))\n" <>
      "LISTEN  0       4096     0.0.0.0:8080         0.0.0.0:*           users:((\"node\",pid=5678,fd=9))\n" <>
      "LISTEN  0       128      127.0.0.53:53        0.0.0.0:*           users:((\"systemd-resolve\",pid=999,fd=5))\n" <>
      "LISTEN  0       4096     [::]:80              0.0.0.0:*           users:((\"nginx\",pid=4321,fd=7))\n"
  end

  defp mock_output("uname -r") do
    "6.8.0-31-generic\n"
  end

  defp mock_output("uname -m") do
    "x86_64\n"
  end

  # Runtime detection: no container runtimes installed in mock env
  defp mock_output("test -x /usr/bin/" <> _rest) do
    "no\n"
  end

  defp mock_output(_other) do
    ""
  end
end
