/**
 * Attach mouse, wheel, click, and hover handlers.
 * @param {object} hook  The LiveView hook context (`this`).
 */
export function bindPointerEvents(hook) {
  const { canvas } = hook;

  // drag start
  canvas.addEventListener("mousedown", (e) => {
    canvas.style.cursor = "grabbing";
    hook.isDragging = true;
    hook.dragRef = { x: e.clientX, y: e.clientY, t: e.timeStamp };
    hook.velX = hook.velY = 0;
  });

  // drag move
  window.addEventListener("mousemove", (e) => {
    if (!hook.isDragging) return;
    hook.offsetX += e.movementX;
    hook.offsetY += e.movementY;
    const dt = e.timeStamp - hook.dragRef.t || 1;
    hook.velX = (e.movementX / dt) * 16;
    hook.velY = (e.movementY / dt) * 16;
    hook.dragRef = { x: e.clientX, y: e.clientY, t: e.timeStamp };
  });

  // drag end
  window.addEventListener("mouseup", () => {
    hook.isDragging = false;
    canvas.style.cursor = "grab";
  });

  // zoom
  canvas.addEventListener(
    "wheel",
    (e) => {
      e.preventDefault();
      const delta = e.deltaY < 0 ? 0.1 : -0.1;
      hook.targetScale = Math.max(0.5, Math.min(2, hook.targetScale + delta));
    },
    { passive: false }
  );

  // click selection
  canvas.addEventListener("click", (e) => {
    const rect = canvas.getBoundingClientRect();
    const mx = e.clientX - rect.left;
    const my = e.clientY - rect.top;
    for (const [key, bounds] of hook.rendered) {
      if (
        mx >= bounds.x &&
        mx <= bounds.x + bounds.w &&
        my >= bounds.y &&
        my <= bounds.y + bounds.h
      ) {
        hook.selectedKey = key;
        hook.pushEvent("overlay_selected", hook.overlayMap.get(key));
        return;
      }
    }
  });

  // hover
  canvas.addEventListener("mousemove", (e) => {
    if (hook.isDragging) return;
    const rect = canvas.getBoundingClientRect();
    const mx = e.clientX - rect.left;
    const my = e.clientY - rect.top;
    hook.hoverKey = null;
    for (const [key, bounds] of hook.rendered) {
      if (
        mx >= bounds.x &&
        mx <= bounds.x + bounds.w &&
        my >= bounds.y &&
        my <= bounds.y + bounds.h
      ) {
        hook.hoverKey = key;
        break;
      }
    }
  });
}
