defmodule TunneldWeb.Live.Components.Wireguard.PeerCreatedModal do
  @moduledoc """
  Modal shown once after peer creation with QR code and download link.

  Displays the peer's WireGuard config as a QR code and provides
  a download button for the .conf file. The private key is shown
  only here and is not stored.
  """
  use TunneldWeb, :live_component

  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="text-center">
        <div class="text-sm font-semibold text-green-400 mb-1">Peer Created</div>
        <div class="text-xs text-gray-400">
          Scan the QR code or download the config file to set up your device.
          <br />
          <span class="text-yellow-400">This config will not be shown again.</span>
        </div>
      </div>

      <div :if={@qr_svg} class="flex justify-center">
        <%= raw(@qr_svg) %>
      </div>

      <div class="bg-secondary rounded-md p-3">
        <div class="text-[10px] text-gray-400 mb-1">Config</div>
        <pre class="text-[10px] text-gray-300 overflow-x-auto whitespace-pre-wrap font-mono break-all"><%= @config_text %></pre>
      </div>

      <div class="flex flex-col gap-2">
        <a
          href={@download_url}
          download={@filename}
          class="w-full text-center bg-blue-600 hover:bg-blue-700 text-white text-xs py-2 px-4 rounded transition-colors duration-150"
        >
          Download .conf file
        </a>
        <button
          phx-click="modal_close"
          class="w-full text-center bg-primary hover:bg-secondary text-gray-1 text-xs py-2 px-4 rounded transition-colors duration-150"
        >
          Done
        </button>
      </div>
    </div>
    """
  end

  def update(assigns, socket) do
    config_text = Map.get(assigns, :config_text, "")
    filename = Map.get(assigns, :filename, "wg0.conf")

    qr_svg =
      if config_text != "" do
        config_text
        |> EQRCode.encode()
        |> EQRCode.svg(width: 192)
      else
        nil
      end

    download_url =
      if config_text != "" do
        "data:application/octet-stream;base64," <> Base.encode64(config_text)
      else
        "#"
      end

    socket =
      socket
      |> assign(:config_text, config_text)
      |> assign(:filename, filename)
      |> assign(:qr_svg, qr_svg)
      |> assign(:download_url, download_url)

    {:ok, socket}
  end
end