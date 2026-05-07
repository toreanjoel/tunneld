const Gauge = {
  mounted() {
    this.animate()
  },

  updated() {
    this.animate()
  },

  animate() {
    const el = this.el
    const value = parseFloat(el.dataset.value) || 0
    const max = parseFloat(el.dataset.max) || 100
    const circle = el.querySelector('[data-ref="gauge-fg"]')
    if (!circle) return

    const r = 55
    const circumference = 2 * Math.PI * r
    const pct = Math.max(0, Math.min(1, value / max))
    const offset = circumference * (1 - pct)

    circle.style.transition = "stroke-dashoffset 800ms ease-out"
    circle.style.strokeDashoffset = offset
  }
}

export default Gauge
