import NetworkDiagram from "./network_diagram"

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

export default {
  ...Hooks,
  NetworkDiagram
};
