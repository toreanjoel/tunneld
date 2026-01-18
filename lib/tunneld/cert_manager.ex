defmodule Tunneld.CertManager do
  use GenServer
  require Logger

  # Check every 6 hours
  @check_interval :timer.hours(6)
  @validity_days "30"

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_) do
    # Run the check immediately on startup (async)
    send(self(), :check_certs)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check_certs, state) do
    check_and_renew_certs()
    Process.send_after(self(), :check_certs, @check_interval)
    {:noreply, state}
  end

  def generate_cert(reserve_name) do
    config = Application.get_env(:tunneld, :certs, [])
    cert_dir = Keyword.get(config, :cert_dir)
    ca_dir = Keyword.get(config, :ca_dir)

    key_path = Path.join(cert_dir, "#{reserve_name}.key")
    csr_path = Path.join(cert_dir, "#{reserve_name}.csr")
    crt_path = Path.join(cert_dir, "#{reserve_name}.crt")

    # Ensure cert directory exists
    File.mkdir_p!(cert_dir)

    case get_root_domain() do
      {:ok, root_domain} ->
        Logger.info("Generating certificate for #{reserve_name}.#{root_domain}")

        with {_, 0} <- System.cmd("openssl", ["genrsa", "-out", key_path, "2048"], stderr_to_stdout: true),
             {_, 0} <- System.cmd("openssl", [
               "req", "-new", "-key", key_path,
               "-out", csr_path,
               "-subj", "/CN=#{reserve_name}.#{root_domain}",
               "-addext", "subjectAltName = DNS:#{reserve_name}.#{root_domain}"
             ], stderr_to_stdout: true),
             {_, 0} <- System.cmd("openssl", [
               "x509", "-req", "-in", csr_path,
               "-CA", Path.join(ca_dir, "rootCA.pem"),
               "-CAkey", Path.join(ca_dir, "rootCA.key"),
               "-CAcreateserial",
               "-out", crt_path,
               "-days", @validity_days,
               "-sha256",
               "-copy_extensions", "copy"
             ], stderr_to_stdout: true) do
          File.rm(csr_path)
          Logger.info("Certificate generated successfully: #{crt_path}")
          :ok
        else
          {out, _} ->
            Logger.error("Failed to generate certificate for #{reserve_name}: #{out}")
            {:error, out}
        end

      {:error, reason} ->
        Logger.error("Skipping certificate generation for #{reserve_name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def delete_cert(reserve_name) do
    config = Application.get_env(:tunneld, :certs)
    cert_dir = Keyword.get(config, :cert_dir)

    File.rm(Path.join(cert_dir, "#{reserve_name}.key"))
    File.rm(Path.join(cert_dir, "#{reserve_name}.csr"))
    File.rm(Path.join(cert_dir, "#{reserve_name}.crt"))
    :ok
  end

  defp check_and_renew_certs do
    config = Application.get_env(:tunneld, :certs, [])
    cert_dir = Keyword.get(config, :cert_dir)

    if File.exists?(cert_dir) do
      cert_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".crt"))
      |> Enum.each(fn file ->
        crt_path = Path.join(cert_dir, file)
        if cert_expired?(crt_path) do
          reserve_name = Path.basename(file, ".crt")
          Logger.info("Certificate for #{reserve_name} is expired or expiring soon. Renewing...")
          generate_cert(reserve_name)
        end
      end)
    else
      Logger.warning("Certificate directory #{cert_dir} does not exist. Skipping check.")
    end
  end

  defp cert_expired?(crt_path) do
    # Check if certificate expires within 24 hours (86400 seconds)
    # Exit code 0 means it will NOT expire (Valid)
    # Exit code 1 means it WILL expire (Invalid/Expired)
    case System.cmd("openssl", ["x509", "-checkend", "86400", "-in", crt_path], stderr_to_stdout: true) do
      {_, 0} -> false
      _ -> true
    end
  end

  defp get_root_domain do
    Tunneld.Servers.Zrok.get_root_domain()
  end
end
