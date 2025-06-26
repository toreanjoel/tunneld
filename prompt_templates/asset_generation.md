# 🎨 Tunneld Isometric Asset Prompt Template

This prompt is designed to generate **high-resolution isometric 3D assets** for the **Tunneld networking project**. The assets represent visualized components in a programmable, tile-based network system. While the **visual theme is fully customizable** (e.g., cyberpunk city, forest, pixel world), the **style must remain clean, realistic, high-definition**, and consistent across all components.

---

## 🧭 Supported Asset Types

Your world can have any artistic or thematic direction, but it must include visual representations of these five **core system entities**:

| Type     | Description |
|----------|-------------|
| **Ground** | The base tile. Determines the visual foundation for all other components. |
| **Gateway** | The central hub or device managing the network. Must appear distinct and important. |
| **Services** | Represent operating system processes or system functions. Think of these as towers, robots, billboards, or modular utility buildings. |
| **Devices** | Real-world devices connected to the network: laptops, TVs, phones, PCs, tablets, etc. |
| **Artifacts** | Applications or services running on devices or the gateway. Represented as small icons or overlays near/atop their host device. |

> ⚠️ These are the five **mandatory object types** for a complete Tunneld UI representation, regardless of your aesthetic theme.

---

## 🧾 Prompt Structure

> Create a **high-resolution, isometric 3D block** that visually represents a core component in a **networking or infrastructure system**, rendered with precision and realism. The block should follow the technical constraints below but can be visually adapted to suit any **artistic theme** (e.g., a forest, desert, cyberpunk city, retro pixel art world, or fantasy techland).

---

### 📐 Shape & Projection

- Orthographically projected with a **2:1 isometric angle**.
- **Top-down diamond (rhombus)** top face, with two **trapezoidal side faces**.
- The block must **occupy the full 256×256 canvas**, properly aligned to fit into an isometric grid layout.
- Strictly **no perspective distortion**—ensure consistent geometry across all tiles.

---

### 🧱 Surface Details

#### `TOP_SURFACE` Options (theme-specific, example formats):

- `"moss-covered stone with glowing runes"` (forest/fantasy)
- `"metal panel with subtle circuit etching"` (modern tech)
- `"glass top with neon stripes"` (cyberpunk)
- `"sandy tile with cracked pathways"` (desert/ruins)

Convey surface depth with:
- Light bounce, reflection, or roughness cues
- Thematic material fidelity (wood, metal, rock, plastic, neon, pixel)
- Etched symbols, device markings, or active UI glows

---

### 🧱 Side Material

#### `SIDE_MATERIAL` Examples (based on theme):

- `"metallic sides with vent grilles and status lights"`  
- `"stone bricks with embedded glowing roots"`  
- `"smooth plastic with embedded fiber optic lines"`  
- `"pixel-style 8-bit shading with 3-color highlights"`

Side details may include:
- Connection ports
- LED strips or digital displays
- Cabling or piping
- Animated status indicators (on/off, blinking)

---

### 💡 Lighting & Shading

- Use a **top-left ambient lighting gradient** with light drop-off to bottom-right.
- Materials must respond to light correctly (e.g., reflective glass, soft matte, glowing plastic).
- Avoid flat shading—emphasize 3D form subtly and cleanly.
- Optional glow effects (for active components like status lights or artifact icons).

---

### 🎨 Styling & Aesthetic

- Assets must be:
  - **High-definition** (no pixelation)
  - **Clean-edged**
  - **Realistic or semi-stylized**, fitting within a consistent visual system
- Themes may vary (e.g., garden, cyberpunk, retro pixel-art), but all tiles must:
  - Respect scale
  - Maintain spatial harmony
  - Share the same **lighting model** and **perspective rules**
- Assets must tile and align naturally in an **isometric grid system**.

---

### 🧊 Environment & Canvas Constraints

- Full 256x256 px canvas
- Transparent background (`alpha = 0`)
- The visual footprint of the block must **fill the canvas** edge-to-edge, aligning isometrically
- No extraneous background, shadows, or floating elements

---

## 💎 Notes for Consistency

- Consistent **visual rules across all asset types**, regardless of theme
- Preserve **high resolution**, **depth perception**, and **clean transparency**
- Maintain alignment fidelity to support **live rendering in a game/UI dashboard**

---

## 💡 Filled-In Example Prompt

> An isometric 3D block rendered in ultra-high detail for a cyberpunk-themed networking dashboard. The top surface is a glass panel with etched neon circuitry glowing faintly purple, and the sides are brushed black metal with small embedded fiber optic ports. The block is orthographically projected with a diamond-shaped top and two trapezoidal sides, occupying the full 256x256 canvas. It includes soft lighting from the top-left corner with subtle glows along connection points. The background is fully transparent. This block is designed to represent a **gateway node**, fitting into a larger tile-based infrastructure grid in a futuristic urban network.

---

## 🧩 Optional Thematic Examples per Type

| Type     | Theme        | Prompt Snippet |
|----------|--------------|----------------|
| Ground   | Forest       | `"mossy grass with glowing mushrooms and scattered roots"` |
| Gateway  | Cyberpunk    | `"glass roof server core with digital status ring"` |
| Services | City/Tech    | `"holographic billboard tower with scrolling logs"` |
| Devices  | Pixel-style  | `"pixelated laptop with animated screen and open lid"` |
| Artifacts| Fantasy tech | `"floating crystal orb icon hovering above a console"` |


# Your goal is to generate the images - are you ready for me to send you a prompt to generate?

