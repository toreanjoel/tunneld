/**
 * Draw the isometric grid and overlays.
 * @param {object} hook  The LiveView hook context (`this`).
 * @param {number} timestamp
 */
export function draw(hook, timestamp) {
  const {
    ctx,
    canvas,
    tileW,
    tileH,
    scale,
    assets,
    overlayMap,
    selectedKey,
    hoverKey,
  } = hook;
  ctx.clearRect(0, 0, canvas.width, canvas.height);

  ctx.save();
  ctx.translate(
    canvas.width / 2 + hook.offsetX,
    canvas.height * 0.25 + hook.offsetY
  );
  ctx.scale(scale, scale);

  hook.rendered.clear();

  const frameIndex = Math.floor(timestamp / 500) % Object.keys(assets).length;
  const overlayImage = assets[Object.keys(assets)[frameIndex]];

  for (const cell of depthOrder(hook)) {
    const x = (cell.i - cell.j) * tileW * 0.5;
    const y = (cell.i + cell.j) * tileH * 0.5;

    // cull off-screen
    if (
      x * scale + canvas.width / 2 + hook.offsetX < -tileW ||
      x * scale - canvas.width / 2 + hook.offsetX > canvas.width ||
      y * scale + hook.offsetY > canvas.height
    )
      continue;

    // ground
    ctx.drawImage(assets.ground, x, y, tileW, tileW);

    const key = `${cell.i},${cell.j}`;
    if (!overlayMap.has(key)) continue;

    const oy = y - tileH;
    hook.rendered.set(key, {
      x: x * scale + canvas.width / 2 + hook.offsetX,
      y: oy * scale + canvas.height * 0.25 + hook.offsetY,
      w: tileW * scale,
      h: tileW * scale,
    });

    ctx.drawImage(overlayImage, x, oy, tileW, tileW);

    // highlights
    if (key === selectedKey) {
      ctx.save();
      ctx.shadowColor = "rgba(255,100,100,0.8)";
      ctx.shadowBlur = 15;
      ctx.drawImage(overlayImage, x, oy, tileW, tileW);
      ctx.restore();
    } else if (key === hoverKey) {
      ctx.save();
      ctx.shadowColor = "rgba(100,255,100,0.6)";
      ctx.shadowBlur = 12;
      ctx.drawImage(overlayImage, x, oy, tileW, tileW);
      ctx.restore();
    }
  }

  ctx.restore();
}

/**
 * Return cells in depth-sorted order.
 */
export function depthOrder({ cols, rows }) {
  const cells = [];
  for (let i = 0; i < cols; i++) {
    for (let j = 0; j < rows; j++) {
      cells.push({ i, j, d: i + j });
    }
  }
  return cells.sort((a, b) => a.d - b.d);
}

/**
 * Resize the canvas to fill its container.
 */
export function resizeCanvas({ canvas, el }) {
  canvas.width = el.clientWidth;
  canvas.height = el.clientHeight;
}
