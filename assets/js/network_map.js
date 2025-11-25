import cloudIcon from "../images/Cloud_v2.svg";
import routerIcon from "../images/Access Point_v2.svg";
import switchIcon from "../images/Router.svg";
import wifiIcon from "../images/Access Point_v2.svg";
import deviceIcon from "../images/Generic Device.svg";
import resourcePrivate from "../images/Private Resource.svg";
import resourcePublic from "../images/Public Resource.svg";
import defaultIcon from "../images/Generic Device.svg";

const ISO = Math.PI / 6;
const COS = Math.cos(ISO);
const SIN = Math.sin(ISO);
const GRID = 96;
const GRID_SPAN = 64;
const NODE_SCALE = 0.3;
const NODE_HEIGHT_SCALE = 0.3;
const LINK_PARTICLE_FACTOR = 6;

const INTRO_STAGGER = 110;
const INTRO_DURATION = 650;

const NODE_GRID_SIZE = 1.5;
const GRID_STEP = 1;
const GRID_CENTER_OFFSET = 1;

const iconSources = {
  cloud: cloudIcon,
  router: routerIcon,
  switch: switchIcon,
  device: deviceIcon,
};

const iconCache = new Map();

const emptyGraph = {
  nodes: [],
  links: [],
};

export default {
  mounted() {
    this.map = makeNetworkMap(this.el);
    this.map.start(readGraph(this.el));
    this._visible = isVisible(this.el);
  },

  updated() {
    const nowVisible = isVisible(this.el);
    if (nowVisible && !this._visible) {
      requestAnimationFrame(() => this.map?.onShow());
    }
    this._visible = nowVisible;
    this.map?.hydrateGraph(readGraph(this.el));
  },

  destroyed() {
    this.map?.destroy();
    this.map = null;
  },
};

function makeNetworkMap(root) {
  const canvas = root.querySelector("canvas") || root;
  const ctx = canvas.getContext("2d");
  const board = root;
  const loader = root.querySelector("#loader");
  const theme = getThemeVars(root);
  const iconLibrary = createIconLibrary();

  const state = {
    scale: 1,
    offset: { x: 0, y: 0 },
    draggingPlane: false,
    dragStart: { x: 0, y: 0 },
    draggingNode: null,
    nodeDragMoved: false,
    planeDragMoved: false,
    hasUserZoomed: false,
  };

  const spriteCache = new Map();
  const linkStreams = new Map();
  let linkRoutes = new Map();
  let screenCache = new Map();
  let nodes = [];
  let links = [];
  let lastTime = performance.now();
  let introStartTime = null;
  let introDone = false;
  let rafId = null;
  let lastCanvasSize = { w: 0, h: 0 };
  let lastDpr = window.devicePixelRatio || 1;
  const cleanupFns = [];

  const textColor = theme.text || "#f0f3ff";

  function addListener(target, type, fn, options) {
    if (!target || typeof target.addEventListener !== "function") return;
    target.addEventListener(type, fn, options);
    cleanupFns.push(() => target.removeEventListener(type, fn, options));
  }

  function resize(options = {}) {
    const { force = false } = options;
    if (!canvas || !ctx) return;
    const w = canvas.clientWidth;
    const h = canvas.clientHeight;
    if (!w || !h) return;
    const dpr = window.devicePixelRatio || 1;
    const expectedW = Math.round(w * dpr);
    const expectedH = Math.round(h * dpr);
    const sizeChanged = w !== lastCanvasSize.w || h !== lastCanvasSize.h;
    const dprChanged = dpr !== lastDpr;
    const backingStoreChanged = canvas.width !== expectedW || canvas.height !== expectedH;
    if (!force && !sizeChanged && !dprChanged && !backingStoreChanged) return;
    lastCanvasSize = { w, h };
    lastDpr = dpr;
    canvas.width = expectedW;
    canvas.height = expectedH;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.imageSmoothingEnabled = true;
    fitScene();
  }

  function screenPointFromEvent(e) {
    const rect = canvas.getBoundingClientRect();
    return {
      x: (e.clientX - rect.left - (canvas.clientWidth / 2 + state.offset.x)) / state.scale,
      y: (e.clientY - rect.top - (canvas.clientHeight / 2 + state.offset.y)) / state.scale,
    };
  }

  function withViewport(fn) {
    ctx.save();
    ctx.translate(canvas.clientWidth / 2 + state.offset.x, canvas.clientHeight / 2 + state.offset.y);
    ctx.scale(state.scale, state.scale);
    fn();
    ctx.restore();
  }

  function clear() {
    ctx.save();
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.restore();
  }

  function cacheNodeScreens() {
    screenCache = new Map();
    nodes.forEach((node) => {
      const pos = isoToScreen(node.pos.x, node.pos.y, node.pos.z);
      const size = node.size * GRID * NODE_SCALE;
      const height = size * NODE_HEIGHT_SCALE;
      screenCache.set(node.id, { x: pos.x, y: pos.y, s: size, h: height });
    });
  }

  function hitTest(pt) {
    let result = null;
    let min = Infinity;
    screenCache.forEach((info, id) => {
      const dx = pt.x - info.x;
      const dy = pt.y - info.y;
      const dist = Math.hypot(dx, dy);
      if (dist < info.s && dist < min) {
        result = id;
        min = dist;
      }
    });
    return result;
  }

  function drawGrid() {
    ctx.lineWidth = 1;
    const offset = 0;
    for (let i = -GRID_SPAN; i <= GRID_SPAN; i++) {
      ctx.strokeStyle = theme.grid;
      const isoLine = i + offset;
      const aStart = isoToScreen(-GRID_SPAN + offset, isoLine);
      const aEnd = isoToScreen(GRID_SPAN + offset, isoLine);
      ctx.beginPath();
      ctx.moveTo(aStart.x, aStart.y);
      ctx.lineTo(aEnd.x, aEnd.y);
      ctx.stroke();
      const bStart = isoToScreen(isoLine, -GRID_SPAN + offset);
      const bEnd = isoToScreen(isoLine, GRID_SPAN + offset);
      ctx.beginPath();
      ctx.moveTo(bStart.x, bStart.y);
      ctx.lineTo(bEnd.x, bEnd.y);
      ctx.stroke();
    }
  }

  function nodeCenter(node) {
    const snap = snappedNodePositionData(node);
    return isoToScreen(snap.x, snap.y, 0);
  }

  function drawLinks() {
    linkRoutes = new Map();
    ctx.lineWidth = 2.2;
    ctx.lineCap = "round";
    links.forEach((link) => {
      const startNode = nodes.find((n) => n.id === link.from);
      const endNode = nodes.find((n) => n.id === link.to);
      if (!startNode || !endNode) return;
      const route = orthPath(startNode, endNode);
      const start = nodeCenter(startNode);
      const end = nodeCenter(endNode);
      const points = route.map((point, i) => {
        if (i === 0) return start;
        if (i === route.length - 1) return end;
        return isoToScreen(point.x, point.y, point.z);
      });
      ctx.strokeStyle = shade(startNode.color, 8);
      ctx.shadowColor = "rgba(0,0,0,0.35)";
      ctx.shadowBlur = 10;
      ctx.beginPath();
      ctx.moveTo(points[0].x, points[0].y);
      for (let i = 1; i < points.length; i++) {
        ctx.lineTo(points[i].x, points[i].y);
      }
      ctx.stroke();
      const segments = [];
      let total = 0;
      let prev = points[0];
      for (let i = 1; i < points.length; i++) {
        const point = points[i];
        const seg = Math.hypot(point.x - prev.x, point.y - prev.y);
        segments.push({ length: seg, from: prev, to: point });
        total += seg;
        prev = point;
      }
      linkRoutes.set(link.id, { points, segments, length: total });
      ctx.fillStyle = "rgba(255,255,255,0.2)";
      for (let i = 1; i < points.length - 1; i++) {
        const p = points[i];
        ctx.beginPath();
        ctx.arc(p.x, p.y, 3, 0, Math.PI * 2);
        ctx.fill();
      }
    });
    ctx.shadowBlur = 0;
  }

  function drawLinkParticles() {
    ctx.save();
    ctx.fillStyle = "rgba(255,255,255,0.85)";
    links.forEach((link) => {
      const route = linkRoutes.get(link.id);
      const stream = linkStreams.get(link.id);
      if (!route || !stream) return;
      stream.forEach((particle) => {
        const pos = interpolateRoute(route, particle.progress % 1);
        if (!pos) return;
        ctx.beginPath();
        ctx.arc(pos.x, pos.y, 3.2, 0, Math.PI * 2);
        ctx.fill();
      });
    });
    ctx.restore();
  }

  function drawNodes(time) {
    let allIntroComplete = true;
    nodes.forEach((node, index) => {
      const info = screenCache.get(node.id);
      if (!info) return;
      const { x, y, s: baseS } = info;
      let s = baseS;
      let yOffset = 0;
      let alpha = 1;

      if (!introDone && introStartTime !== null) {
        const elapsed = time - introStartTime - index * INTRO_STAGGER;
        const tRaw = Math.max(0, Math.min(1, elapsed / INTRO_DURATION));
        if (tRaw < 1) {
          allIntroComplete = false;
        }
        const ease = tRaw * (2 - tRaw);
        const scale = 0.75 + 0.25 * ease;
        s = baseS * scale;
        yOffset = (1 - ease) * 24;
        alpha = ease;
      }

      ctx.save();
      ctx.globalAlpha = alpha;
      ctx.translate(0, yOffset);

      ctx.save();
      ctx.translate(x, y);
      renderIconForNode(node, s * 3, time);
      ctx.restore();

      ctx.fillStyle = "rgba(0,0,0,0.35)";
      ctx.font = "700 13px 'Space Grotesk', system-ui";
      ctx.textAlign = "center";
      ctx.fillText(node.label, x, y - s * 0.9);

      ctx.fillStyle = textColor;
      ctx.fillText(node.label, x, y - s);

      ctx.restore();
    });

    if (!introDone && allIntroComplete) {
      introDone = true;
      if (loader) loader.classList.add("hidden");
    }
  }

  function orthPath(a, b) {
    const start = snappedNodePositionData(a);
    const end = snappedNodePositionData(b);
    if (Math.abs(start.x - end.x) < 0.001 || Math.abs(start.y - end.y) < 0.001) {
      return [start, end];
    }
    const midZ = (start.z + end.z) / 2;
    const dx = Math.abs(end.x - start.x);
    const dy = Math.abs(end.y - start.y);
    if (dx >= dy) {
      return [start, { x: end.x, y: start.y, z: midZ }, end];
    }
    return [start, { x: start.x, y: end.y, z: midZ }, end];
  }

  function snappedNodePositionData(node) {
    return {
      x: snapToGridCenter(node.pos.x),
      y: snapToGridCenter(node.pos.y),
      z: 0,
    };
  }

  function interpolateRoute(route, t) {
    if (!route || !route.segments.length) return null;
    const target = route.length * t;
    let travelled = 0;
    for (const segment of route.segments) {
      if (!segment.length) continue;
      if (travelled + segment.length >= target) {
        const ratio = (target - travelled) / segment.length;
        return {
          x: segment.from.x + (segment.to.x - segment.from.x) * ratio,
          y: segment.from.y + (segment.to.y - segment.from.y) * ratio,
        };
      }
      travelled += segment.length;
    }
    const last = route.points[route.points.length - 1];
    return { x: last.x, y: last.y };
  }

  function resolveIconFrames(node) {
    const icon = node.icon || {};
    const variant = icon.variant || node.type;
    const stateName = icon.state || "enabled";
    const library = iconLibrary[variant] || iconLibrary.device;
    const cachedSprites = ensureSpriteFrames(node)?.[stateName];
    const frames = cachedSprites?.length ? cachedSprites : library?.[stateName] || library?.enabled;
    const frameDuration = icon.frameDuration || library?.frameDuration || 800;
    return { frames, frameDuration };
  }

  function ensureSpriteFrames(node) {
    if (!node.icon?.frameSources) return null;
    if (!spriteCache.has(node.id)) {
      const loaded = {};
      Object.entries(node.icon.frameSources).forEach(([stateName, urls]) => {
        loaded[stateName] = urls.map((src) => {
          const img = new Image();
          img.src = src;
          return img;
        });
      });
      spriteCache.set(node.id, loaded);
    }
    return spriteCache.get(node.id);
  }

  function renderIconForNode(node, size, time) {
    const { frames, frameDuration } = resolveIconFrames(node);
    if (!frames || !frames.length) return;
    const index = Math.floor(time / frameDuration) % frames.length;
    const frame = frames[index];
    if (typeof frame === "function") {
      frame(ctx, size);
    } else if (frame instanceof HTMLImageElement && frame.complete) {
      const w = frame.width;
      const h = frame.height;
      const scale = size / Math.max(w, h);
      ctx.drawImage(frame, -w * scale * 0.5, -h * scale * 0.5, w * scale, h * scale);
    }
  }

  function snapToGridCenter(value) {
    return Math.round((value - GRID_CENTER_OFFSET) / GRID_STEP) * GRID_STEP + GRID_CENTER_OFFSET;
  }

  function snapNodePosition(node) {
    if (node.snap === false) return;
    node.pos.x = snapToGridCenter(node.pos.x);
    node.pos.y = snapToGridCenter(node.pos.y);
  }

  function fitScene(options = {}) {
    const { respectUser = true } = options;
    if (respectUser && state.hasUserZoomed) return;
    if (!nodes.length || !canvas) {
      state.offset.x = 0;
      state.offset.y = 0;
      return;
    }
    const cw = canvas.clientWidth || 1;
    const ch = canvas.clientHeight || 1;
    const points = nodes.map((n) => isoToScreen(n.pos.x, n.pos.y, n.pos.z));
    const padPx = GRID * 1.1; // one grid block margin around content
    const minX = Math.min(...points.map((p) => p.x)) - padPx;
    const maxX = Math.max(...points.map((p) => p.x)) + padPx;
    const minY = Math.min(...points.map((p) => p.y)) - padPx;
    const maxY = Math.max(...points.map((p) => p.y)) + padPx;
    state.offset.x = -((minX + maxX) / 2);
    state.offset.y = -((minY + maxY) / 2) * 0.6;
    const spanX = Math.max(1, maxX - minX);
    const spanY = Math.max(1, maxY - minY);
    const target = Math.min((cw * 0.98) / spanX, (ch * 0.98) / spanY);
    state.scale = Math.max(0.5, Math.min(2.6, target));
  }

  function updateLinkParticles(delta) {
    links.forEach((link) => {
      if (!linkStreams.has(link.id)) linkStreams.set(link.id, []);
      const stream = linkStreams.get(link.id);
      const target = Math.max(0, Math.round((link.activity ?? 0.3) * LINK_PARTICLE_FACTOR));
      while (stream.length < target) {
        stream.push({ progress: Math.random(), speed: 0.18 + Math.random() * 0.25 });
      }
      while (stream.length > target) {
        stream.pop();
      }
      stream.forEach((particle) => {
        particle.progress += particle.speed * delta;
        if (particle.progress > 1) particle.progress -= 1;
      });
    });
  }

  function render(time = 0) {
    resize();
    clear();
    withViewport(() => {
      cacheNodeScreens();
      drawGrid();
      drawLinks();
      drawLinkParticles();
      drawNodes(time);
    });
  }

  function loop(timestamp) {
    if (introStartTime === null) {
      introStartTime = timestamp;
    }
    const delta = (timestamp - lastTime) / 1000 || 0;
    lastTime = timestamp;
    updateLinkParticles(delta);
    render(timestamp);
    rafId = requestAnimationFrame(loop);
  }

  function setDraggingCursor(active) {
    canvas.classList.toggle("grabbing", active);
  }

  function hydrateGraph(rawGraph) {
    const graph = typeof rawGraph === "string" ? JSON.parse(rawGraph) : rawGraph || emptyGraph;
    const cleanedNodes = (graph.nodes || []).map((node, i) => {
      const copy = cloneGraph(node);
      copy.pos = copy.pos || { x: 0, y: 0, z: 0 };
      copy.size = NODE_GRID_SIZE;
      copy.phase = i * 0.7;
      snapNodePosition(copy);
      return copy;
    });
    nodes = cleanedNodes;
    links = (graph.links || []).map((link) => cloneGraph(link));
    linkStreams.clear();
    linkRoutes = new Map();
    screenCache = new Map();
    state.scale = 1;
    state.offset = { x: 0, y: 0 };
    state.hasUserZoomed = false;
    introDone = false;
    introStartTime = null;
    loader?.classList.remove("hidden");
    resize();
    fitScene({ respectUser: false });
  }

  const onMouseDown = (e) => {
    cacheNodeScreens();
    const pt = screenPointFromEvent(e);
    const hit = hitTest(pt);
    if (hit) {
      const node = nodes.find((n) => n.id === hit);
      const iso = screenToIso(pt, node.pos.z);
      state.draggingNode = { node, offset: { x: node.pos.x - iso.x, y: node.pos.y - iso.y } };
    } else {
      state.draggingPlane = true;
      state.dragStart = { x: e.clientX - state.offset.x, y: e.clientY - state.offset.y };
    }
    state.nodeDragMoved = false;
    state.planeDragMoved = false;
    setDraggingCursor(true);
  };

  const onMouseMove = (e) => {
    if (state.draggingNode) {
      const node = state.draggingNode.node;
      const pt = screenPointFromEvent(e);
      const iso = screenToIso(pt, node.pos.z);
      node.pos.x = iso.x + state.draggingNode.offset.x;
      node.pos.y = iso.y + state.draggingNode.offset.y;
      state.nodeDragMoved = true;
      return;
    }
    if (!state.draggingPlane) return;
    state.planeDragMoved = true;
    state.offset.x = e.clientX - state.dragStart.x;
    state.offset.y = e.clientY - state.dragStart.y;
  };

  const onMouseUp = () => {
    if (state.draggingNode) {
      snapNodePosition(state.draggingNode.node);
    }
    state.draggingPlane = false;
    state.draggingNode = null;
    state.nodeDragMoved = false;
    state.planeDragMoved = false;
    setDraggingCursor(false);
  };

  const onWheel = (e) => {
    e.preventDefault();
    const delta = -e.deltaY * 0.0015;
    const next = Math.min(2.6, Math.max(0.4, state.scale * (1 + delta)));
    const pt = screenPointFromEvent(e);
    state.offset.x -= pt.x * (next - state.scale);
    state.offset.y -= pt.y * (next - state.scale);
    state.scale = next;
    state.hasUserZoomed = true;
  };

  const onResize = () => {
    resize();
  };

  function bindEvents() {
    addListener(canvas, "mousedown", onMouseDown);
    addListener(window, "mousemove", onMouseMove);
    addListener(window, "mouseup", onMouseUp);
    addListener(canvas, "wheel", onWheel, { passive: false });
    addListener(canvas, "dblclick", () => {
      state.hasUserZoomed = false;
      state.scale = 1;
      fitScene({ respectUser: false });
    });
    addListener(window, "resize", onResize);

    if (typeof ResizeObserver !== "undefined") {
      const observer = new ResizeObserver(() => resize());
      observer.observe(board);
      cleanupFns.push(() => observer.disconnect());
    }

    if (typeof IntersectionObserver !== "undefined") {
      const vis = new IntersectionObserver((entries) => {
        const visible = entries.some((entry) => entry.isIntersecting);
        if (visible) {
          state.hasUserZoomed = false;
          resize({ force: true });
          fitScene({ respectUser: false });
        }
      });
      vis.observe(board);
      cleanupFns.push(() => vis.disconnect());
    }

    addListener(document, "visibilitychange", () => {
      if (document.visibilityState !== "visible") return;
      if (!isVisible(board)) return;
      resize({ force: true });
      fitScene({ respectUser: state.hasUserZoomed });
    });

    addListener(board, "network-map:download", () => {
      resize({ force: true });
      const dataUrl = canvas.toDataURL("image/png");
      if (!dataUrl) return;
      const link = document.createElement("a");
      link.href = dataUrl;
      link.download = "network-map.png";
      link.click();
    });
  }

  function destroy() {
    cleanupFns.forEach((fn) => fn());
    cleanupFns.length = 0;
    if (rafId) cancelAnimationFrame(rafId);
  }

  function start(graph) {
    resize();
    bindEvents();
    board.style.setProperty("--tiltX", "0deg");
    board.style.setProperty("--tiltY", "0deg");
    hydrateGraph(graph || emptyGraph);
    fitScene({ respectUser: false });
    rafId = requestAnimationFrame(loop);
  }

  function onShow() {
    state.hasUserZoomed = false;
    resize({ force: true });
    fitScene({ respectUser: false });
  }

  return { start, hydrateGraph, destroy, onShow };
}

function readGraph(el) {
  try {
    return JSON.parse(el.dataset.graph || "{}");
  } catch (_e) {
    return emptyGraph;
  }
}

function cloneGraph(data) {
  return JSON.parse(JSON.stringify(data || {}));
}

function isoToScreen(x, y, z = 0) {
  const sx = (x - y) * COS * GRID;
  const sy = (x + y) * SIN * GRID - z * GRID * 0.9;
  return { x: sx, y: sy };
}

function screenToIso(pt, z = 0) {
  const xMinusY = pt.x / (COS * GRID);
  const xPlusY = (pt.y + z * GRID * 0.9) / (SIN * GRID);
  const x = 0.5 * (xMinusY + xPlusY);
  const y = x - xMinusY;
  return { x, y };
}

function shade(hex, amt) {
  const clean = (hex || "#ffffff").replace("#", "");
  const num = parseInt(clean, 16);
  const r = Math.min(255, Math.max(0, (num >> 16) + amt * 2));
  const g = Math.min(255, Math.max(0, ((num >> 8) & 0xff) + amt * 2));
  const b = Math.min(255, Math.max(0, (num & 0xff) + amt * 2));
  return `#${(b | (g << 8) | (r << 16)).toString(16).padStart(6, "0")}`;
}

function getThemeVars(root) {
  const rootStyle = getComputedStyle(root);
  const docStyle = getComputedStyle(document.documentElement);
  const pick = (name, fallback) => (rootStyle.getPropertyValue(name) || docStyle.getPropertyValue(name) || fallback).trim() || fallback;
  return {
    grid: pick("--grid", "rgba(255,255,255,0.14)"),
    gridBold: pick("--grid-bold", "rgba(255,255,255,0.28)"),
    text: pick("--text", "#f0f3ff"),
    muted: pick("--muted", "#8f9bc3"),
    accent: pick("--accent", "#8b9bff"),
    accent2: pick("--accent-2", "#60e8c2"),
  };
}

function isVisible(el) {
  if (!el) return false;
  const style = getComputedStyle(el);
  if (style.display === "none" || style.visibility === "hidden") return false;
  return el.offsetWidth > 0 && el.offsetHeight > 0;
}

function loadSvgIcon(src) {
  if (iconCache.has(src)) return iconCache.get(src);
  const img = new Image();
  img.src = encodeURI(src);
  iconCache.set(src, img);
  return img;
}

function imageFrame(src) {
  const img = loadSvgIcon(src);
  return (context, size) => {
    if (!img.complete) {
      img.onload = () => {};
      return;
    }
    const w = img.width || size;
    const h = img.height || size;
    const scale = size / Math.max(w, h);
    context.drawImage(img, -w * scale * 0.5, -h * scale * 0.5, w * scale, h * scale);
  };
}

function createIconLibrary() {
  const pick = (key) => iconSources[key] || iconSources.default;
  return {
    cloud: { enabled: [imageFrame(pick("cloud"))], disabled: [imageFrame(pick("cloud"))], frameDuration: 800 },
    router: { enabled: [imageFrame(pick("router"))], disabled: [imageFrame(pick("router"))], frameDuration: 800 },
    switch: { enabled: [imageFrame(pick("switch"))], disabled: [imageFrame(pick("switch"))], frameDuration: 800 },
    device: { enabled: [imageFrame(pick("device"))], disabled: [imageFrame(pick("device"))], frameDuration: 800 },
  };
}
