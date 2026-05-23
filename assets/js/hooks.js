import { HemisphereHook } from "./hemisphere.js"
import GaugeHook from "./gauge_hook.js"
import MapPinHover from "./map_pin_hover.js"
import HelpTooltip from "./help_tooltip.js"

let Hooks = {};

Hooks.Hemisphere = HemisphereHook;
Hooks.Gauge = GaugeHook;
Hooks.MapPinHover = MapPinHover;
Hooks.HelpTooltip = HelpTooltip;

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