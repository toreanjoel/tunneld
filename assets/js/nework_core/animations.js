import { draw } from "./renderer.js";

/**
 * The RAF loop: interpolates scale, applies inertia, then draws.
 */
export function loop(hook, timestamp) {
  const dt = (timestamp - hook.prevTime) / 1000;
  hook.prevTime = timestamp;

  // zoom interpolation
  if (hook.scale !== hook.targetScale) {
    hook.scale += (hook.targetScale - hook.scale) * 0.12;
  }

  // inertia
  if (!hook.isDragging) {
    hook.offsetX += hook.velX;
    hook.offsetY += hook.velY;
    hook.velX *= 0.9;
    hook.velY *= 0.9;
    if (Math.abs(hook.velX) < 0.1) hook.velX = 0;
    if (Math.abs(hook.velY) < 0.1) hook.velY = 0;
  }

  draw(hook, timestamp);
  requestAnimationFrame((ts) => loop(hook, ts));
}
