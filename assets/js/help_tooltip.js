let tooltipEl = null;

const HelpTooltip = {
  mounted() {
    const trigger = this.el;
    const text = trigger.getAttribute("data-help-text");

    trigger.addEventListener("mouseenter", () => {
      if (!text) return;
      tooltipEl = document.createElement("div");
      tooltipEl.className = "help-tooltip-portal";
      tooltipEl.textContent = text;
      document.body.appendChild(tooltipEl);
      positionTooltip(trigger, tooltipEl);
    });

    trigger.addEventListener("mouseleave", () => {
      if (tooltipEl) {
        tooltipEl.remove();
        tooltipEl = null;
      }
    });
  },

  destroyed() {
    if (tooltipEl) {
      tooltipEl.remove();
      tooltipEl = null;
    }
  },
};

function positionTooltip(trigger, tooltip) {
  // Apply visual + sizing styles first so the tooltip has its real dimensions
  tooltip.style.position = "absolute";
  tooltip.style.top = "-9999px";  // park offscreen while we measure
  tooltip.style.left = "-9999px";
  tooltip.style.zIndex = "99999";
  tooltip.style.maxWidth = "256px";
  tooltip.style.padding = "10px";
  tooltip.style.fontSize = "12px";
  tooltip.style.lineHeight = "1.5";
  tooltip.style.color = "var(--text-2)";
  tooltip.style.backgroundColor = "var(--surface)";
  tooltip.style.border = "1px solid var(--border)";
  tooltip.style.borderRadius = "8px";
  tooltip.style.boxShadow = "0 8px 24px rgba(0,0,0,0.5)";
  tooltip.style.pointerEvents = "none";
  tooltip.style.whiteSpace = "normal";
  tooltip.style.textAlign = "left";

  // Now measure
  const rect = trigger.getBoundingClientRect();
  const scrollX = window.scrollX;
  const scrollY = window.scrollY;
  const tipHeight = tooltip.offsetHeight;
  const tipWidth = tooltip.offsetWidth;
  const viewportWidth = window.innerWidth;

  let topVp = rect.top - tipHeight - 6;
  let leftVp = rect.left + rect.width / 2 - tipWidth / 2;

  if (topVp < 8) {
    topVp = rect.bottom + 6;
  }
  if (leftVp < 8) {
    leftVp = 8;
  } else if (leftVp + tipWidth > viewportWidth - 8) {
    leftVp = viewportWidth - tipWidth - 8;
  }

  // Place it
  tooltip.style.top = topVp + scrollY + "px";
  tooltip.style.left = leftVp + scrollX + "px";
}

export default HelpTooltip;
