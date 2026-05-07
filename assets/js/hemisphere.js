export const HemisphereHook = {
  mounted() {
    this.svgNS = "http://www.w3.org/2000/svg"
    this.connected = this.el.dataset.connected === "true"
    this.animId = null
    this.startMs = null
    this.build()
    if (this.connected) this.startAnimation()
  },

  updated() {
    const wasConnected = this.connected
    this.connected = this.el.dataset.connected === "true"
    if (wasConnected !== this.connected) this.startAnimation()
    else this.stopAnimation()
    this.build()
  },

  destroyed() { this.stopAnimation() },

  build() {
    const el = this.el
    el.innerHTML = ""
    el.setAttribute("viewBox", "0 0 460 460")

    const cx = 230, cy = 230, r = 190
    const tilt = -0.35

    const geoToVec = (lat, lon) => {
      const lt = (lat * Math.PI) / 180, ln = (lon * Math.PI) / 180
      return { x: Math.cos(lt) * Math.sin(ln), y: Math.sin(lt), z: Math.cos(lt) * Math.cos(ln) }
    }

    const project = (v) => {
      const cT = Math.cos(tilt), sT = Math.sin(tilt)
      return { x: cx + v.x * r, y: cy - (v.y * cT - v.z * sT) * r, z: v.y * sT + v.z * cT }
    }

    const make = (tag, attrs = {}) => {
      const e = document.createElementNS(this.svgNS, tag)
      for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v)
      return e
    }

    const g = make("g", { opacity: this.connected ? "1" : "0.25" })
    let html = ""

    for (let lat = -75; lat <= 75; lat += 25) {
      const pts = []
      for (let lon = -180; lon <= 180; lon += 5) pts.push(project(geoToVec(lat, lon)))
      for (let i = 1; i < pts.length; i++) {
        const a = pts[i - 1], b = pts[i]
        if ((a.z + b.z) < 0) continue
        html += `<line x1="${a.x.toFixed(1)}" y1="${a.y.toFixed(1)}" x2="${b.x.toFixed(1)}" y2="${b.y.toFixed(1)}" stroke="rgba(6,182,212,0.28)" stroke-width="0.8"/>`
      }
    }
    for (let lon = -180; lon < 180; lon += 15) {
      const pts = []
      for (let lat = -90; lat <= 90; lat += 3) pts.push(project(geoToVec(lat, lon)))
      for (let i = 1; i < pts.length; i++) {
        const a = pts[i - 1], b = pts[i]
        if ((a.z + b.z) < 0) continue
        html += `<line x1="${a.x.toFixed(1)}" y1="${a.y.toFixed(1)}" x2="${b.x.toFixed(1)}" y2="${b.y.toFixed(1)}" stroke="rgba(6,182,212,0.22)" stroke-width="1.0"/>`
      }
    }
    g.innerHTML = html
    el.appendChild(g)

    el.appendChild(make("circle", {
      cx: "230", cy: "230", r: String(r),
      fill: "none", stroke: this.connected ? "rgba(6,182,212,0.35)" : "rgba(6,182,212,0.1)", "stroke-width": "1.5"
    }))
  },

  startAnimation() {
    this.startMs = performance.now()
    const svg = this.el
    const tick = () => {
      const deg = ((performance.now() - this.startMs) / 1000 * 6) % 360
      svg.style.transform = `rotateY(${deg}deg)`
      this.animId = requestAnimationFrame(tick)
    }
    this.animId = requestAnimationFrame(tick)
  },

  stopAnimation() {
    if (this.animId) { cancelAnimationFrame(this.animId); this.animId = null }
    this.el.style.transform = ""
  }
}
