import { HemisphereHook } from "./hemisphere.js"
import GaugeHook from "./gauge_hook.js"
import MapPinHover from "./map_pin_hover.js"
import HelpTooltip from "./help_tooltip.js"

let Hooks = {};

Hooks.Hemisphere = HemisphereHook;
Hooks.Gauge = GaugeHook;
Hooks.MapPinHover = MapPinHover;
Hooks.HelpTooltip = HelpTooltip;

Hooks.CopyToClipboard = {
  mounted() {
    this.handleEvent("copy_to_clipboard", ({ text }) => {
      copyText(text);
    });
  },
};

function copyText(text) {
  if (navigator.clipboard && window.isSecureContext) {
    navigator.clipboard.writeText(text).catch(() => {
      fallbackCopy(text);
    });
  } else {
    fallbackCopy(text);
  }
}

function fallbackCopy(text) {
  const textarea = document.createElement("textarea");
  textarea.value = text;
  textarea.style.position = "fixed";
  textarea.style.opacity = "0";
  document.body.appendChild(textarea);
  textarea.select();
  try {
    document.execCommand("copy");
  } catch (e) {
    // ignore
  }
  document.body.removeChild(textarea);
}

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

    this.handleEvent("update_obfuscation", ({ obfuscated }) => {
      localStorage.setItem("tunneld_obfuscated", obfuscated.toString());
    });
  },
};

export default Hooks;