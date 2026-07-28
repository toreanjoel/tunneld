defmodule Tunneld.Machines.Exec do
  @moduledoc """
  Interactive `incus exec` over SSH, streamed to a browser terminal.

  The flow:
    1. Browser opens a Phoenix channel topic `exec:<machine_id>:<container_name>`.
    2. `Exec.start/3` spawns an SSH process running `incus exec <name> -- bash`,
       allocating a PTY (`-tt`), and streams stdout/stderr back over the channel.
    3. Browser keypresses are sent as `{:input, data}` messages; tunneld writes
       them to the SSH process stdin.
    4. On exit or disconnect, the SSH process is killed and the channel closes.

  In mock mode (`:tunneld, :mock_data`), a fake shell is simulated that echoes
  input and prints a prompt, so the terminal works on a laptop without a real
  Linux+Incus box.

  This is the highest-risk piece of the redesign: it converges SSH PTY
  allocation, websocket framing, and a browser terminal emulator. The v1
  implementation is deliberately simple — a streaming `<pre>` element with
  a JS hook, not a full xterm.js terminal. ANSI escape handling is left to
  the browser; a later milestone can swap in xterm.js for proper rendering.
  """

  require Logger

  @mock Application.compile_env(:tunneld, :mock_data, false)

  @doc """
  Start an interactive exec session. Returns `{:ok, pid}` where `pid` is the
  process streaming output to the given `channel_pid`, or `{:error, reason}`.

  The caller (channel) will receive `{:exec_output, data}` and
  `{:exec_exit, code}` messages.
  """
  def start(machine, container, channel_pid) do
    if @mock do
      mock_start(channel_pid)
    else
      real_start(machine, container, channel_pid)
    end
  end

  @doc "Send input to the running exec session's stdin."
  def send_input(pid, data) when is_pid(pid) do
    send(pid, {:exec_input, data})
    :ok
  end

  @doc "Stop the exec session (kill the SSH process)."
  def stop(pid) when is_pid(pid) do
    send(pid, {:exec_stop})
    :ok
  end

  # --- Real SSH exec ---

  defp real_start(machine, container, channel_pid) do
    id = machine["id"]
    key = key_path(id)
    host = machine["address"]
    port = Integer.to_string(machine["ssh_port"] || 22)
    cmd = "incus exec #{shell_quote(container)} -- bash"

    # Use a Port with a PTY so we can stream bidirectionally.
    # ssh -tt forces PTY allocation on the remote side.
    args = [
      "-i", key,
      "-o", "StrictHostKeyChecking=accept-new",
      "-o", "ConnectTimeout=10",
      "-tt",
      "-p", port,
      host,
      cmd
    ]

    spawn(fn ->
      port = Port.open({:spawn_executable, ssh_binary()},
        [:binary, :stream, :use_stdio, :exit_status, args: args])

      loop(port, channel_pid)
    end)
    |> then(&{:ok, &1})
  end

  defp loop(port, channel_pid) do
    receive do
      {^port, {:data, data}} ->
        send(channel_pid, {:exec_output, data})
        loop(port, channel_pid)

      {^port, {:exit_status, code}} ->
        send(channel_pid, {:exec_exit, code})

      {:exec_input, data} ->
        Port.command(port, data)
        loop(port, channel_pid)

      {:exec_stop} ->
        Port.close(port)
        send(channel_pid, {:exec_exit, 0})
    end
  end

  # --- Mock exec ---

  defp mock_start(channel_pid) do
    pid = spawn(fn -> mock_loop(channel_pid, "") end)
    send(pid, {:exec_input, ""})
    {:ok, pid}
  end

  defp mock_loop(channel_pid, buffer) do
    receive do
      {:exec_input, data} ->
        # Simulate a basic shell: echo input, show prompt
        cond do
          String.ends_with?(data, "\r") or String.ends_with?(data, "\n") ->
            line = buffer <> String.trim_trailing(data, "\r") |> String.trim_trailing("\n")
            output = handle_mock_command(line)
            send(channel_pid, {:exec_output, output <> "\r\nmock-container:~$ "})
            mock_loop(channel_pid, "")

          data == "" ->
            send(channel_pid, {:exec_output, "Welcome to mock Incus container (Ubuntu 24.04)\r\nmock-container:~$ "})
            mock_loop(channel_pid, "")

          true ->
            mock_loop(channel_pid, buffer <> data)
        end

      {:exec_stop} ->
        send(channel_pid, {:exec_exit, 0})
    end
  end

  defp handle_mock_command(""), do: ""
  defp handle_mock_command("exit"), do: "logout"
  defp handle_mock_command("whoami"), do: "root"
  defp handle_mock_command("hostname"), do: "mock-container"
  defp handle_mock_command("uname -a"), do: "Linux mock-container 6.8.0 #1 SMP x86_64 GNU/Linux"
  defp handle_mock_command("ls"), do: "bin  boot  dev  etc  home  lib  lib64  media  mnt  opt  proc  root  run  sbin  srv  sys  tmp  usr  var"
  defp handle_mock_command("pwd"), do: "/root"
  defp handle_mock_command("id"), do: "uid=0(root) gid=0(root) groups=0(root)"
  defp handle_mock_command(cmd) do
    if String.starts_with?(cmd, "echo ") do
      String.trim_leading(cmd, "echo ")
    else
      "bash: #{cmd}: command not found (mock)"
    end
  end

  defp ssh_binary, do: System.find_executable("ssh") || "ssh"

  defp key_path(machine_id) do
    Path.join([Tunneld.Config.fs_root(), "ssh", machine_id])
  end

  defp shell_quote(s) when is_binary(s) do
    "'" <> String.replace(s, "'", "'\\''") <> "'"
  end
end