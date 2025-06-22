/**
 * IsoGrid LiveView Hook
 *
 * Renders a fixed-scale isometric grid using a single 64×64 sprite
 * (visible diamond = 64×32), centered on-screen, with click-drag
 * panning, diamond-based hover detection, and an entry animation.
 */
export default {
  mounted() {
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
    // Offset position relative from where we start clicking vs where the mouse moved to
    // We use this to move items around the screne using the click drag
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

    // Keep checking if screen resolution changed - we make sure to reinit and render
    this.resizeCanvas();

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
      const dx = e.clientX - this.lastDrag.x;
      const dy = e.clientY - this.lastDrag.y;
      // On the base offset of 0, we add what ever that is with the difference from where we were started dragging from
      // vs where we stopped dragging
      // NOTE: Offset is the point on init render, if we change the offset by a value, we are updating its new position
      // This is for everything being rendered
      this.offsetX += dx;
      this.offsetY += dy;
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
    const {
      ctx,
      canvas,
      tileW,
      tileH,
      cols,
      rows,
      offsetX,
      offsetY,
      groundImg,
      overlayImg,
    } = this;
    // The actual current size of the canvas
    const cw = canvas.width,
      ch = canvas.height;
    //  We need to reset the canvas and clear everything before painting anything new
    // ctx.resetTransform();
    ctx.clearRect(0, 0, cw, ch);

    // total grid size
    const gridW = tileW * 0.5;
    const gridH = tileH * 0.5;

    // Move everything the current half w/h of the canvas - bottom right - it will make sure everything is rendered in the center
    // The grid and width are the dimensions of what we are rendering and want to center this entire thing
    // We need to make sure we account position based off offset so we move it when we click and drag
    const gridX = cw * 0.5 - gridW + offsetX;
    const gridY = ch * 0.5 - gridH + offsetY;

    // Take the data that we use to represent tiles information and loop through everything to render
    for (const { i, j } of this.computeTileDepths()) {
      // Calculate the isometric position of each tile.
      // - `gridX` and `gridY` are the top-left pixel offsets of the entire grid.
      // - `(i - j) * tileW * 0.5` moves tiles horizontally in isometric space.
      // - `(i + j) * tileH * 0.5` moves tiles vertically in isometric space.
      // This centers each tile's tip based on the grid layout and avoids gaps from tile corners.
      const drawX = gridX + (i - j) * tileW * 0.5;
      const drawY = gridY + (i + j) * tileH * 0.5;

      // draw ground item assuming it is loaded into memory
      if (groundImg.complete) {
        ctx.drawImage(groundImg, drawX, drawY, tileW, tileW);
      }

      // draw overlay on the chosen tile - hard code where but assuming its into memoery
      if (i === 4 && j === 3 && overlayImg.complete) {
        // adjust drawY if you need it to sit higher/lower
        // We need to make sure we loop over the list and set the items on the relevant parent block
        ctx.drawImage(overlayImg, drawX, drawY - tileH, tileW, tileW);
      }

      // draw overlay on the chosen tile - hard code where
      if (i === 2 && j === 0 && overlayImg.complete) {
        // adjust drawY if you need it to sit higher/lower
        // We need to make sure we loop over the list and set the items on the relevant parent block
        ctx.drawImage(overlayImg, drawX, drawY - tileH, tileW, tileW);
      }

      // draw overlay on the chosen tile - hard code where
      if (i === 1 && j === 3 && overlayImg.complete) {
        // adjust drawY if you need it to sit higher/lower
        // We need to make sure we loop over the list and set the items on the relevant parent block
        ctx.drawImage(overlayImg, drawX, drawY - tileH, tileW, tileW);
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
};
