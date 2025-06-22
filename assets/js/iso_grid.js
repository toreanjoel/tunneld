/**
 * IsoGrid LiveView Hook
 *
 * Renders a fixed-scale isometric grid using a single 64×64 sprite
 * (visible diamond = 64×32), centered on-screen, with click-drag
 * panning, diamond-based hover detection, and an entry animation.
 */
export default {
  mounted() {
    // context & canvas
    this.ctx = this.el.querySelector("canvas").getContext("2d");
    this.canvas = this.ctx.canvas;

    this.debug = false;
    this.tileW = +this.el.dataset.tileW;
    this.tileH = +this.el.dataset.tileH;
    this.cols = +this.el.dataset.cols;
    this.rows = +this.el.dataset.rows;
    this.offsetX = 0;
    this.offsetY = 0;

    // This needs to be dynamic from a matrix list maybe?
    // load base ground sprite
    this.groundImg = new Image();
    this.groundImg.src = "../images/blockdetail.png";
    this.groundImg.onload = () => this.draw();

    // We need to layer the icons on another matrix list that gets looped over on top of this?
    // load overlay sprite
    this.overlayImg = new Image();
    this.overlayImg.src = "../images/block.png";
    this.overlayImg.onload = () => this.draw();

    // NOTE: assets need to be able to render animations

    this.resizeCanvas();
    window.addEventListener("resize", () => {
      this.resizeCanvas();
      this.draw();
    });

    // pan handlers
    this.canvas.addEventListener("mousedown", e => {
      this.isDragging = true;
      this.lastDrag   = { x: e.clientX, y: e.clientY };
    });

    this.canvas.addEventListener("mousemove", e => {
      if (!this.isDragging) return;
      const dx = e.clientX - this.lastDrag.x;
      const dy = e.clientY - this.lastDrag.y;
      this.offsetX += dx; this.offsetY += dy;
      this.lastDrag = { x: e.clientX, y: e.clientY };
      this.draw();
    });
    window.addEventListener("mouseup", () => this.isDragging = false);
  },

  resizeCanvas() {
    this.canvas.width  = this.el.clientWidth;
    this.canvas.height = this.el.clientHeight;
  },

  draw() {
    const { ctx, canvas, tileW, tileH, cols, rows, offsetX, offsetY,
            groundImg, overlayImg } = this;
    const cw = canvas.width, ch = canvas.height;
    ctx.resetTransform();
    ctx.clearRect(0, 0, cw, ch);

    // total grid size
    const gridW = tileW * 0.5;
    const gridH = (cols + rows) * (tileH * 0.25);
    const baseX = (cw - gridW) * 0.5 + offsetX;
    const baseY = (ch - gridH) * 0.5 + offsetY;
    const spriteOffsetY = (tileW - tileH) / 2;

    for (const { i, j } of this.computeTileDepths()) {
      const tipX = baseX + (i - j) * 0.5 * tileW;
      const tipY = baseY + (i + j) * 0.5 * tileH;
      const drawX = tipX - tileW * 0.5;
      const drawY = tipY - tileW;

      // draw ground
      if (groundImg.complete) {
        ctx.drawImage(groundImg, drawX, drawY, tileW, tileW);
      }

      // draw overlay on the chosen tile - hard code where
      if (i === 4 && j === 3 && overlayImg.complete) {
        // adjust drawY if you need it to sit higher/lower
        // We need to make sure we loop over the list and set the items on the relevant parent block
        ctx.drawImage(overlayImg, drawX, drawY - (tileH), tileW, tileW);
      }
      
      // draw overlay on the chosen tile - hard code where
      if (i === 2 && j === 0 && overlayImg.complete) {
        // adjust drawY if you need it to sit higher/lower
        // We need to make sure we loop over the list and set the items on the relevant parent block
        ctx.drawImage(overlayImg, drawX, drawY - (tileH), tileW, tileW);
      }
      
      // draw overlay on the chosen tile - hard code where
      if (i === 1 && j === 3 && overlayImg.complete) {
        // adjust drawY if you need it to sit higher/lower
        // We need to make sure we loop over the list and set the items on the relevant parent block
        ctx.drawImage(overlayImg, drawX, drawY - (tileH), tileW, tileW);
      }

      // debug collision diamond
      if (this.debug) {
        const cy = tipY - spriteOffsetY;
        ctx.beginPath();
        ctx.moveTo(tipX,           cy);
        ctx.lineTo(tipX + tileW/2, cy - tileH/2);
        ctx.lineTo(tipX,           cy - tileH);
        ctx.lineTo(tipX - tileW/2, cy - tileH/2);
        ctx.closePath();
        ctx.lineWidth   = 1;
        ctx.strokeStyle = "rgba(0,255,0,0.3)";
        ctx.stroke();
      }
    }
  },

  computeTileDepths() {
    const arr = [];
    for (let i = 0; i < this.cols; i++) {
      for (let j = 0; j < this.rows; j++) {
        arr.push({ i, j, d: i + j });
      }
    }
    return arr.sort((a, b) => a.d - b.d);
  },
}
