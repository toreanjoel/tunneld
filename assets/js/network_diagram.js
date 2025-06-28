import { initAssets } from "./network_core/assetsLoader.js";
import { draw, depthOrder, resizeCanvas } from "./network_core/renderer.js";
import { loop } from "./network_core/animations.js";
import { bindPointerEvents } from "./network_core/pointerEvents.js";

export default {
  async mounted() {
    // 1. Canvas & context
    this.ctx = this.el.querySelector("canvas").getContext("2d");
    this.canvas = this.ctx.canvas;
    this.canvas.style.cursor = "grab";

    // 2. Grid params
    this.tileW = +this.el.dataset.tileW;
    this.tileH = +this.el.dataset.tileH;
    this.cols = +this.el.dataset.cols;
    this.rows = +this.el.dataset.rows;

    // 3. Overlays map
    const raw = JSON.parse(this.el.dataset.overlays || "[]");
    this.overlayMap = new Map(raw.map((o) => [`${o.i},${o.j}`, o]));

    // 4. Interaction state
    this.selectedKey = null;
    this.hoverKey = null;
    this.rendered = new Map();

    // 5. Camera & physics
    this.offsetX = 0;
    this.offsetY = 0;
    this.velX = 0;
    this.velY = 0;
    this.scale = 0.75;
    this.targetScale = 1;
    this.isDragging = false;

    // 6. Remove loader
    document.getElementById("iso-loader")?.remove();

    // 7. Load assets & kick things off
    this.assets = await initAssets();
    resizeCanvas(this);
    this.prevTime = performance.now();
    requestAnimationFrame((ts) => loop(this, ts));

    // 8. Handlers
    window.addEventListener("resize", () => resizeCanvas(this));
    bindPointerEvents(this);
    this.handleEvent("overlay_closed", () => {
      this.selectedKey = null;
    });
  },
};
