defmodule Tunneld.Machines.SSH do
  @moduledoc """
  SSH transport for managed machines.

  Generates an Ed25519 keypair per machine at enrollment, stores the private
  half under `TUNNELD_DATA/ssh/<machine_id>` (mode 0600), and runs commands on
  the machine via shelled-out `ssh` with ControlMaster multiplexing so repeat
  calls reuse one master connection.

  In mock mode (`:tunneld, :mock_data`), no SSH is performed; a fake remote
  machine is simulated so the full enroll -> probe -> list loop works on a
  laptop without a real Linux box.

  Credential model (v1): plain SSH key, shell user. The operator installs the
  public half on the target's `authorized_keys`. Blast radius is documented:
  a leaked private key is root-equivalent on that machine; rotate by removing
  the machine and re-enrolling.
  """

  require Logger

  @mock Application.compile_env(:tunneld, :mock_data, false)

  @doc "Generate an Ed25519 keypair. Returns `{public_key_string, private_key_pem}`."
  def generate_keypair do
    tmp = Path.join(System.tmp_dir!(), "tunneld_key_#{System.unique_integer([:positive])}")

    {_, 0} =
      System.cmd("ssh-keygen", [
        "-t",
        "ed25519",
        "-N",
        "",
        "-C",
        "tunneld",
        "-f",
        tmp,
        "-q"
      ])

    {:ok, priv} = File.read(tmp)
    {:ok, pub} = File.read(tmp <> ".pub")
    File.rm(tmp)
    File.rm(tmp <> ".pub")
    {pub, priv}
  end

  @doc "Store a private key (and its public half) for a machine on disk."
  def store_key(machine_id, priv_pem) do
    dir = ssh_dir()
    File.mkdir_p!(dir)
    path = key_path(machine_id)

    # Derive the public half from the private key so public_key_string/1 can
    # always read it back (previously the .pub was never written, so the key
    # vanished from the UI after enrollment).
    pub = public_from_private(priv_pem)

    :ok = File.write(path, priv_pem)
    :ok = File.chmod(path, 0o600)
    :ok = File.write(path <> ".pub", pub)
    :ok = File.chmod(path <> ".pub", 0o644)
    :ok
  end

  @doc "Derive an OpenSSH public key line from a PEM private key via ssh-keygen."
  def public_from_private(priv_pem) do
    tmp = Path.join(System.tmp_dir!(), "tunneld_key_#{System.unique_integer([:positive])}")
    :ok = File.write(tmp, priv_pem)
    File.chmod(tmp, 0o600)

    {pub, 0} = System.cmd("ssh-keygen", ["-y", "-f", tmp, "-q"])
    File.rm(tmp)
    pub
  end

  @doc "Delete a machine's private key."
  def delete_key(machine_id) do
    path = key_path(machine_id)
    File.rm(path)
    File.rm(path <> ".pub")
    :ok
  end

  @doc "Return the public key string the operator must install on the target."
  def public_key_string(machine_id) do
    path = key_path(machine_id) <> ".pub"

    case File.read(path) do
      {:ok, pub} -> pub
      _ -> nil
    end
  end

  @doc """
  Run a command on the machine over SSH. Returns `{:ok, stdout}` or `{:error, reason}`.

  Uses ControlMaster so repeat calls reuse the master connection. In mock
  mode, dispatches to `Mock.run/2` instead of touching SSH.
  """
  def run(machine, command, opts \\ []) do
    if @mock do
      Tunneld.Machines.SSH.Mock.run(machine, command, opts)
    else
      real_run(machine, command, opts)
    end
  end

  defp real_run(machine, command, _opts) do
    id = machine["id"]
    key = key_path(id)
    host = machine["address"]
    user = machine["ssh_user"] || "root"
    port = Integer.to_string(machine["ssh_port"] || 22)

    args = [
      "-i",
      key,
      "-o",
      "StrictHostKeyChecking=accept-new",
      "-o",
      "ConnectTimeout=10",
      "-o",
      "ControlMaster=auto",
      "-o",
      "ControlPath=#{control_path(id)}",
      "-o",
      "ControlPersist=600",
      "-p",
      port,
      "#{user}@#{host}",
      command
    ]

    case System.cmd("ssh", args, stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      {out, code} -> {:error, {:ssh_failed, code, out}}
    end
  end

  defp ssh_dir do
    Path.join(Tunneld.Config.fs_root(), "ssh")
  end

  defp key_path(machine_id) do
    Path.join(ssh_dir(), machine_id)
  end

  defp control_path(machine_id) do
    Path.join(System.tmp_dir!(), "tunneld_ssh_#{machine_id}")
  end

  # --- Mock ---

  @doc false
  def mock?, do: @mock
end
