defmodule TunneldWeb.Live.IsoGrid do
  @moduledoc """
  Isometric page - this will be the start to the renderer
  """
  use TunneldWeb, :live_view

  # Constants
  @tile_w 64
  @tile_h 32

  # NOTE: the cols will be dynamic down the line
  @cols 5
  @rows 5

  @doc """
  Initialize the login page and the session data for the client
  """
  def mount(_params, _session, socket) do
    # The general canvas size
    width = ((@cols + @rows) * (@tile_w / 2)) |> round()
    height = ((@cols + @rows) * (@tile_h / 2)) |> round()

    socket =
      socket
      |> assign(
        grid_w: width,
        grid_h: height,
        tile_w: @tile_w,
        tile_h: @tile_h,
        cols: @cols,
        rows: @rows
      )

    {:ok, socket}
  end

  @doc """
  Render the init data and the canvas
  """
  def render(assigns) do
    ~H"""
    <div
      id="iso-grid"
      phx-hook="IsoGrid"
      data-tile-w={@tile_w}
      data-tile-h={@tile_h}
      data-cols={@cols}
      data-rows={@rows}
      style="
        position: absolute;
        top: 0; left: 0;
        width: 100vw;
        height: 100vh;
        overflow: hidden;
        background: #15151d;
      ">
        <canvas style="
        display: block;
        width: 100%;
        height: 100%;
      "></canvas>
    </div>
    """
  end
end
