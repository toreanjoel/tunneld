// Base hooks
let Hooks = {};

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
 * Obfuscation toggle — reads/writes localStorage and broadcasts to live view.
 */
Hooks.ObfuscationToggle = {
  mounted() {
    const stored = localStorage.getItem("tunneld_obfuscated");
    const obfuscated = stored === "true";

    if (obfuscated) {
      this.pushEvent("toggle_obfuscation", { obfuscated: true });
    }

    this.el.addEventListener("click", () => {
      const current = localStorage.getItem("tunneld_obfuscated") === "true";
      const next = !current;
      localStorage.setItem("tunneld_obfuscated", next.toString());
      this.pushEvent("toggle_obfuscation", { obfuscated: next });
    });
  },
};

export default Hooks;