defmodule Tunneld do
  @moduledoc """
  Root module for the Tunneld application.

  Contains the `Tunneld.Template` submodule which ensures the Zrok error
  page template (`error.gohtml`) exists in the data directory on startup.
  """

  defmodule Template do
    @moduledoc """
    Ensures the Zrok error page template exists in the data directory.

    Copies from priv/templates/error.gohtml if the file doesn't already exist.
    """

    @template_source Path.join(:code.priv_dir(:tunneld), "templates/error.gohtml")

    def ensure_template do
      root = Application.get_env(:tunneld, :fs)[:root]
      path = Path.join(root, "error.gohtml")

      unless File.exists?(path) do
        File.mkdir_p!(root)
        File.cp!(@template_source, path)
      end
    end
  end
end