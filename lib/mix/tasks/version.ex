defmodule Mix.Tasks.Version do
  @shortdoc "Show or bump the project version (major|minor|patch|<semver>)"
  @moduledoc """
  Show or bump the version in mix.exs and config/config.exs.

  ## Usage

      mix version              # show current version
      mix version patch        # 0.10.5 -> 0.10.6
      mix version minor        # 0.10.5 -> 0.11.0
      mix version major        # 0.10.5 -> 1.0.0
      mix version 1.2.3        # set explicit version
  """
  use Mix.Task

  @version_files [
    {"mix.exs", ~r/version:\s*"(\d+\.\d+\.\d+)"/},
    {"config/config.exs", ~r/version:\s*"(\d+\.\d+\.\d+)"/}
  ]

  @impl Mix.Task
  def run([]) do
    Mix.shell().info(current_version())
  end

  def run([bump]) do
    current = current_version()
    next = next_version(current, bump)

    Enum.each(@version_files, fn {path, regex} ->
      content = File.read!(path)
      updated = Regex.replace(regex, content, fn full, _old ->
        String.replace(full, current, next)
      end)
      File.write!(path, updated)
    end)

    Mix.shell().info("#{current} -> #{next}")
  end

  defp current_version do
    content = File.read!("mix.exs")
    [_, version] = Regex.run(~r/version:\s*"(\d+\.\d+\.\d+)"/, content)
    version
  end

  defp next_version(current, "patch") do
    [major, minor, patch] = parse(current)
    "#{major}.#{minor}.#{patch + 1}"
  end

  defp next_version(current, "minor") do
    [major, minor, _patch] = parse(current)
    "#{major}.#{minor + 1}.0"
  end

  defp next_version(current, "major") do
    [major, _minor, _patch] = parse(current)
    "#{major + 1}.0.0"
  end

  defp next_version(_current, explicit) do
    case Regex.match?(~r/^\d+\.\d+\.\d+$/, explicit) do
      true -> explicit
      false -> Mix.raise("Invalid version: #{explicit}. Use major|minor|patch or a semver like 1.2.3")
    end
  end

  defp parse(version) do
    version |> String.split(".") |> Enum.map(&String.to_integer/1)
  end
end
