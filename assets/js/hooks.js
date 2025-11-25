import NetworkDiagram from "./network_diagram"
import NetworkMap from "./network_map"
import Auth from "./auth.js"

// Base hooks
let Hooks = {};

/**
 * Listen and request access trigger for the fullscreen click event
 */
Hooks.FullscreenIframe = {
  mounted() {
    document.getElementById("fullscreen-btn").addEventListener("click", () => {
      const iframe = document.querySelector("iframe");
      if (iframe && iframe.requestFullscreen) {
        iframe.requestFullscreen();
      }
    });
  },
};

/**
 * Copy to the clipboard
 */
Hooks.CopyToClipboard = {
  mounted() {
    this.handleEvent("copy_to_clipboard", ({ text }) => {
      navigator.clipboard
        .writeText(text)
        .then(() => {
          // Some logging or pushing event to the server to render UI
        })
        .catch((err) => {
          // Push errors here to the liveview
        });
    });
  },
};

/**
 * Trigger a download of the current network map canvas.
 */
Hooks.DownloadNetworkMap = {
  mounted() {
    this.onClick = () => {
      const target = document.getElementById("network-map");
      if (!target) return;
      target.dispatchEvent(new CustomEvent("network-map:download", { bubbles: true }));
    };
    this.el.addEventListener("click", this.onClick);
  },
  destroyed() {
    this.el.removeEventListener("click", this.onClick);
  }
};

export default {
  ...Hooks,
  Auth,
  NetworkDiagram,
  NetworkMap
};
