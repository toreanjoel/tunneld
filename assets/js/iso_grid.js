/**
 * IsoGrid LiveView Hook
 *
 * Renders a fixed-scale isometric grid using a single 64×64 sprite
 * (visible diamond = 128x64), centered on-screen, with click-drag
 * panning, diamond-based hover detection, and an entry animation.
 *
 * TODO:
 * - Spritesheet atlast rather
 * - Culling to only show what is on screen
 * - Aim to use maps over lists with SIMD parallel rendering of data over loops
 */

// The names of the assets we want to add in memory
const ASSETS = ["block", "ground"];

export default {
  async mounted() {
    // Context and canvas
    this.ctx = this.el.querySelector("canvas").getContext("2d");
    this.canvas = this.ctx.canvas;

    // Set the base canvas cursor
    this.canvas.style.cursor = "grab";

    // The data and values of the amount of rows and each tiles width and height
    // NOTE: the + is a way to convert from a string to a number
    this.tileW = +this.el.dataset.tileW;
    this.tileH = +this.el.dataset.tileH;
    this.cols = +this.el.dataset.cols;
    this.rows = +this.el.dataset.rows;
    // The data that will be rendered
    this.overlays = JSON.parse(this.el.dataset.overlays || "[]");
    this.overlayMap = new Map();
    // Convert overlays to Map with "i,j" as key
    for (const overlay of this.overlays) {
      this.overlayMap.set(`${overlay.i},${overlay.j}`, overlay);
    }

    // Keep track of currently selected overlay
    this.selectedOverlayKey = null;

    // Track rendered overlay bounding boxes for click detection
    this.renderedOverlays = new Map();

    // Offset position relative from where we start clicking vs where the mouse moved to
    // We use this to move items around the screne using the click drag
    this.offsetX = 0;
    this.offsetY = 0;

    // initialize assets
    const loadedAssets = await this.initAssets();
    this.assetsToRender = loadedAssets;

    // Keep checking if screen resolution changed - we make sure to reinit and render
    this.resizeCanvas();
    this.draw();

    // Add event listener to check if the window resize has happned
    window.addEventListener("resize", () => {
      // Update the canvas after resize to use new dimension size
      this.resizeCanvas();
      // Clear and recompute everything
      this.draw();
    });

    // Add event listener to keep track of if we are dragging (while clicking) - on the canvas
    // Also keep track of the point the moment we clicked to get last value
    this.canvas.addEventListener("mousedown", (e) => {
      // We could update the cursor here to be mouse down
      this.canvas.style.cursor = "grabbing";

      //set dragging state and the last vector from when we started dragging
      this.isDragging = true;
      this.lastDrag = { x: e.clientX, y: e.clientY };
    });

    // Add listender if the mouse is moving but only do something while clicked (mouse down)
    this.canvas.addEventListener("mousemove", (e) => {
      if (!this.isDragging) return;
      // Where the mouse currently is vs where it came from
      const newMousePosX = e.clientX - this.lastDrag.x;
      const newMousePosY = e.clientY - this.lastDrag.y;
      // On the base offset of 0, we add what ever that is with the difference from where we were started dragging from
      // vs where we stopped dragging
      // NOTE: Offset is the point on init render, if we change the offset by a value, we are updating its new position
      // This is for everything being rendered
      this.offsetX += newMousePosX;
      this.offsetY += newMousePosY;
      // Set the new
      this.lastDrag = { x: e.clientX, y: e.clientY };
      // Make sure as we are dragging, always re init and draw everything
      this.draw();
    });

    // reset state of dragging and the cursor
    window.addEventListener("mouseup", () => {
      this.canvas.style.cursor = "grab";
      this.isDragging = false;
    });

    // Add click event for selecting overlays
    this.canvas.addEventListener("click", (e) => {
      const rect = this.canvas.getBoundingClientRect();
      const mouseX = e.clientX - rect.left;
      const mouseY = e.clientY - rect.top;

      for (const [key, { overlay, x, y, width, height }] of this
        .renderedOverlays) {
        if (
          mouseX >= x &&
          mouseX <= x + width &&
          mouseY >= y &&
          mouseY <= y + height
        ) {
          this.selectedOverlayKey = key;
          console.log("Selected overlay:", overlay);
          this.draw();
          this.processInteraction();
          return;
        }
      }

      // Clear selection if no match
      this.selectedOverlayKey = null;
      this.draw();
    });
  },

  /**
   * Update the canvas dimensions to be updated (full screen) relative to the vieqport
   * We init to get the size and keep calling if we notice the window size is changing (resizing)
   */
  resizeCanvas() {
    this.canvas.width = this.el.clientWidth;
    this.canvas.height = this.el.clientHeight;
  },

  /**
   * Render the items to the screen
   */
  draw() {
    // Get the relevant information that determines what to render
    // context, canvas, the dementions of tiles, the roles and current position of everything along with images
    const { ctx, canvas, tileW, tileH, offsetX, offsetY, assetsToRender } =
      this;

    // Clear stored overlay bounds for interaction - when render and when we click on canvas in general
    this.renderedOverlays.clear();

    // The actual current size of the canvas
    const cw = canvas.width,
      ch = canvas.height;

    //  We need to reset the canvas and clear everything before painting anything new
    ctx.clearRect(0, 0, cw, ch);

    // Move everything the current half w/h of the canvas - bottom right - it will make sure everything is rendered in the center
    // The grid and width are the dimensions of what we are rendering and want to center this entire thing
    // We need to make sure we account position based off offset so we move it when we click and drag
    const gridX = cw / 2 + offsetX;
    // We make sure the canvas height half minus the half of the full cluster of cubes to center vertically
    const gridY = (ch / 2) * 0.5 + offsetY;

    // Take the data that we use to represent tiles information and loop through everything to render
    for (const { i, j } of this.computeTileDepths()) {
      // Calculate the isometric position of each tile.
      // - `gridX` and `gridY` are the top-left pixel offsets of the entire grid.
      // - `(i - j) * tileW * 0.5` moves tiles horizontally in isometric space.
      // - `(i + j) * tileH * 0.5` moves tiles vertically in isometric space.
      // This centers each tile's tip based on the grid layout and avoids gaps from tile corners.
      const drawX = gridX + (i - j) * tileW * 0.5;
      const drawY = gridY + (i + j) * tileH * 0.5;

      // Culling - This makes sure we dont draw the current block if it is not on the screen
      if (
        drawX + tileW < 0 ||
        drawX > canvas.width ||
        drawY + tileW < 0 ||
        drawY > canvas.height
      ) {
        continue; // Skip this tile if offscreen
      }

      // draw ground item assuming it is loaded into memory
      ctx.drawImage(assetsToRender["ground"], drawX, drawY, tileW, tileW);

      // Check if there's an overlay on this tile - we use this to render the items
      const overlay = this.overlayMap.get(`${i},${j}`);
      if (overlay) {
        ctx.drawImage(
          assetsToRender["block"],
          drawX,
          drawY - tileH,
          tileW,
          tileW
        );

        // Store this overlay’s render position for interaction
        this.renderedOverlays.set(`${i},${j}`, {
          overlay,
          x: drawX,
          y: drawY - tileH,
          width: tileW,
          height: tileW,
        });

        // draw selection outline if this is the selected overlay
        if (this.selectedOverlayKey === `${i},${j}`) {
          ctx.strokeStyle = "yellow";
          ctx.lineWidth = 2;
          ctx.strokeRect(drawX, drawY - tileH, tileW, tileW);

          // draw tooltip or label above on click
          const tooltipWidth = 70;
          const tooltipHeight = 20;
          const tooltipX = drawX + tileW / 2 - tooltipWidth / 2;
          const tooltipY = drawY - tileH - 10;

          this.drawSpeechBubble(
            ctx,
            overlay.label || overlay.kind,
            tooltipX,
            tooltipY,
            tooltipWidth,
            tooltipHeight
          );
        }
      }
    }
  },

  /**
   * Render the tiles, this is based on the rows and columns
   * We should pass an array and use this as a helper to render the items
   */
  computeTileDepths() {
    const arr = [];
    for (let i = 0; i < this.cols; i++) {
      for (let j = 0; j < this.rows; j++) {
        arr.push({ i, j, d: i + j });
      }
    }
    return arr;
  },

  /**
   * Draws a simple speech bubble (rounded rectangle with centered text) on a canvas.
   *
   * @param {CanvasRenderingContext2D} ctx - The canvas 2D rendering context to draw on.
   * @param {string} text - The text to display inside the speech bubble.
   * @param {number} x - The X-coordinate of the top-left corner of the bubble.
   * @param {number} y - The Y-coordinate of the top-left corner of the bubble.
   * @param {number} width - The width of the bubble.
   * @param {number} height - The height of the bubble.
   * @param {number} [radius=6] - The corner radius for the rounded rectangle.
   */
  drawSpeechBubble(ctx, text, x, y, width, height, radius = 3) {
    // Draw the rounded rectangle
    ctx.beginPath();
    ctx.moveTo(x + radius, y);
    ctx.lineTo(x + width - radius, y);
    ctx.quadraticCurveTo(x + width, y, x + width, y + radius);
    ctx.lineTo(x + width, y + height - radius);
    ctx.quadraticCurveTo(x + width, y + height, x + width - radius, y + height);
    ctx.lineTo(x + radius, y + height);
    ctx.quadraticCurveTo(x, y + height, x, y + height - radius);
    ctx.lineTo(x, y + radius);
    ctx.quadraticCurveTo(x, y, x + radius, y);
    ctx.closePath();

    // Fill & border
    ctx.fillStyle = "white";
    ctx.strokeStyle = "black";
    ctx.lineWidth = 1.5;
    ctx.fill();
    ctx.stroke();

    // Draw text
    ctx.fillStyle = "black";
    ctx.font = "10px sans-serif";
    ctx.textBaseline = "middle";
    ctx.textAlign = "center";
    ctx.fillText(text, x + width / 2, y + height / 2);
  },

  /**
   * Initialize the assets that we want to have prepared in memory for renderer usage
   */
  async initAssets() {
    const result = {};
    return Promise.all(
      ASSETS.map((asset) => {
        return new Promise((resolve) => {
          const img = new Image();
          img.src = `../images/${asset}.png`;
          img.onload = () => {
            result[asset] = img;
            resolve();
          };
        });
      })
    ).then(() => result);
  },

  /**
   * Process click events back to the server
   */
  processInteraction() {
    if (!this.selectedOverlayKey) return;

    const overlay = this.overlayMap.get(this.selectedOverlayKey);
    if (!overlay) return;

    this.pushEvent("overlay_selected", overlay);
  },
};
