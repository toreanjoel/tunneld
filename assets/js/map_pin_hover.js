const MapPinHover = {
  mounted() {
    this.tooltip = null

    this.showTooltip = (e) => {
      const pin = e.target.closest("[data-pin-name]")
      if (!pin) return

      const oldTip = this.tooltip
      this.tooltip = this.buildTooltip()

      const name = pin.dataset.pinName || ""
      const country = pin.dataset.pinCountry || ""
      const ip = pin.dataset.pinIp || ""

      this.tooltip.innerHTML = `
        <div class="text-[13px] font-medium text-text-primary mb-0.5">${this.esc(name)}</div>
        <div class="text-[11px] text-text-secondary leading-[1.4]">Apparent location: ${this.esc(country)}</div>
        <div class="text-[10px] text-text-tertiary font-mono mt-1">${this.esc(ip)}</div>
      `

      const rect = pin.getBoundingClientRect()
      const svg = this.el.closest("svg")
      if (!svg) return
      const svgRect = svg.getBoundingClientRect()
      const x = rect.left + rect.width / 2
      const y = rect.top

      this.tooltip.style.left = `${x - svgRect.left}px`
      this.tooltip.style.top = `${y - svgRect.top - 8}px`
      this.tooltip.classList.remove("hidden")

      if (oldTip && oldTip !== this.tooltip) {
        oldTip.remove()
      }
    }

    this.hideTooltip = () => {
      if (this.tooltip) {
        this.tooltip.classList.add("hidden")
        this.tooltip.remove()
        this.tooltip = null
      }
    }

    this.el.addEventListener("pointerenter", this.showTooltip)
    this.el.addEventListener("pointerleave", this.hideTooltip)
  },

  destroyed() {
    this.el.removeEventListener("pointerenter", this.showTooltip)
    this.el.removeEventListener("pointerleave", this.hideTooltip)
    if (this.tooltip) {
      this.tooltip.remove()
      this.tooltip = null
    }
  },

  buildTooltip() {
    const svg = this.el.closest("svg")
    if (!svg) return document.createElement("div")

    let wrapper = svg.parentElement.querySelector(".map-tooltip-container")
    if (!wrapper) {
      wrapper = document.createElement("div")
      wrapper.className = "map-tooltip-container absolute inset-0 pointer-events-none"
      svg.parentElement.style.position = "relative"
      svg.parentElement.appendChild(wrapper)
    }

    const tip = document.createElement("div")
    tip.className =
      "absolute hidden bg-[#1C1B26] border border-[#2A2838] rounded-lg px-3 py-2 shadow-xl z-50 whitespace-nowrap transform -translate-x-1/2 -translate-y-full"
    wrapper.appendChild(tip)
    return tip
  },

  esc(str) {
    const div = document.createElement("div")
    div.appendChild(document.createTextNode(str))
    return div.innerHTML
  },
}

export default MapPinHover
