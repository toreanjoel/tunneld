defmodule Tunneld.Servers.Dnsmasq do
  @moduledoc false
  require Logger

  def add_entry(subdomain) do
    with {:ok, domain} <- get_domain() do
      line = config_line(subdomain, domain)
      file = config_file()

      ensure_dir(file)

      try do
        current = if File.exists?(file), do: File.read!(file), else: ""

        unless String.contains?(current, line) do
          File.write!(file, line, [:append])
          Logger.info("Added local DNS entry for #{subdomain}.#{domain}")
        end
      rescue
        e -> Logger.error("Failed to add DNS entry: #{inspect(e)}")
      end
    end
  end

  def remove_entry(subdomain) do
    with {:ok, domain} <- get_domain() do
      line = config_line(subdomain, domain)
      file = config_file()

      if File.exists?(file) do
        try do
          current = File.read!(file)

          if String.contains?(current, line) do
            new_content = String.replace(current, line, "")
            File.write!(file, new_content)
            Logger.info("Removed local DNS entry for #{subdomain}.#{domain}")
          end
        rescue
          e -> Logger.error("Failed to remove DNS entry: #{inspect(e)}")
        end
      end
    end
  end

  defp get_domain do
    Tunneld.Servers.Zrok.get_root_domain()
  end

  defp config_line(subdomain, domain) do
    ip = get_target_ip()
    "address=/#{subdomain}.#{domain}/#{ip}\n"
  end

  defp get_target_ip do
    Application.get_env(:tunneld, :network, [])
    |> Keyword.get(:gateway)
  end

  defp config_file do
    Application.get_env(:tunneld, :fs)[:dns_file]
  end

  defp ensure_dir(path), do: Path.dirname(path) |> File.mkdir_p()
end
