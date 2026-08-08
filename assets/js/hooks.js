import { HemisphereHook } from "./hemisphere.js"
import GaugeHook from "./gauge_hook.js"
import MapPinHover from "./map_pin_hover.js"
import HelpTooltip from "./help_tooltip.js"
import TerminalHook from "./terminal_hook.js"

let Hooks = {};

Hooks.Hemisphere = HemisphereHook;
Hooks.Gauge = GaugeHook;
Hooks.MapPinHover = MapPinHover;
Hooks.HelpTooltip = HelpTooltip;
Hooks.Terminal = TerminalHook;

/**
 * CopyToClipboard — copies the text of the sibling <pre> (or a data-copy-text
 * value) to the clipboard and gives brief button feedback.
 */
Hooks.CopyToClipboard = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      e.preventDefault();
      const pre = this.el.closest(".relative")?.querySelector("pre");
      // Use textContent, not innerText: innerText inserts soft line breaks at
      // visual wrap points, which would corrupt a wrapped SSH key on copy.
      const text = pre ? pre.textContent : this.el.dataset.copyText || "";
      if (!text) return;

      const flash = () => {
        const original = this.el.textContent;
        this.el.textContent = "Copied!";
        setTimeout(() => { this.el.textContent = original; }, 1500);
      };

      // navigator.clipboard only exists in secure contexts (HTTPS/localhost).
      // The dashboard is served over plain HTTP on a LAN IP, so fall back to
      // the legacy execCommand path which works on any origin.
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(flash).catch(() => legacyCopy(text, flash));
      } else {
        legacyCopy(text, flash);
      }
    });
  },
};

function legacyCopy(text, done) {
  const ta = document.createElement("textarea");
  ta.value = text;
  ta.setAttribute("readonly", "");
  ta.style.position = "fixed";
  ta.style.top = "-1000px";
  ta.style.opacity = "0";
  document.body.appendChild(ta);
  ta.select();
  ta.setSelectionRange(0, text.length);
  let ok = false;
  try { ok = document.execCommand("copy"); } catch (_) {}
  document.body.removeChild(ta);
  if (ok) done();
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