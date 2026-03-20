defmodule TunneldWeb.BackupController do
  @moduledoc """
  Controller for backup and restore of Tunneld configuration.

  Export bundles all JSON config files into a single downloadable JSON file.
  Import restores configs from a previously exported backup.
  """
  use TunneldWeb, :controller
  require Logger

  @config_files [:auth, :resources, :ai]

  def export(conn, _params) do
    root = Tunneld.Config.fs_root()

    backup =
      @config_files
      |> Enum.reduce(%{}, fn key, acc ->
        filename = Tunneld.Config.fs(key)

        if filename do
          path = Path.join(root, filename)

          case Tunneld.Persistence.read_json(path) do
            {:ok, data} -> Map.put(acc, to_string(key), data)
            _ -> acc
          end
        else
          acc
        end
      end)
      |> maybe_add_sqm(root)

    backup_json =
      %{
        "tunneld_backup" => true,
        "version" => Application.get_env(:tunneld, :version),
        "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "data" => backup
      }
      |> Jason.encode!(pretty: true)

    timestamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%d_%H%M%S")

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("content-disposition", "attachment; filename=\"tunneld-backup-#{timestamp}.json\"")
    |> send_resp(200, backup_json)
  end

  def import(conn, %{"backup" => %Plug.Upload{path: path}}) do
    with {:ok, content} <- File.read(path),
         {:ok, parsed} <- Jason.decode(content),
         %{"tunneld_backup" => true, "data" => data} <- parsed do
      root = Tunneld.Config.fs_root()
      restored = restore_configs(data, root)

      Logger.info("Backup restored: #{inspect(Map.keys(restored))}")

      conn
      |> put_status(200)
      |> json(%{status: "ok", restored: Map.keys(restored)})
    else
      _ ->
        conn
        |> put_status(400)
        |> json(%{status: "error", message: "Invalid backup file"})
    end
  end

  def import(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{status: "error", message: "No backup file provided"})
  end

  defp maybe_add_sqm(backup, root) do
    sqm_file = Tunneld.Config.fs(:sqm)

    if sqm_file do
      path = Path.join(root, sqm_file)

      case Tunneld.Persistence.read_json(path) do
        {:ok, data} -> Map.put(backup, "sqm", data)
        _ -> backup
      end
    else
      backup
    end
  end

  defp restore_configs(data, root) do
    Enum.reduce(data, %{}, fn {key, value}, acc ->
      filename = config_filename(key)

      if filename do
        path = Path.join(root, filename)

        case Tunneld.Persistence.write_json(path, value) do
          :ok -> Map.put(acc, key, :ok)
          _ -> acc
        end
      else
        acc
      end
    end)
  end

  defp config_filename("auth"), do: Tunneld.Config.fs(:auth)
  defp config_filename("resources"), do: Tunneld.Config.fs(:resources)
  defp config_filename("ai"), do: Tunneld.Config.fs(:ai)
  defp config_filename("sqm"), do: Tunneld.Config.fs(:sqm)
  defp config_filename(_), do: nil
end
