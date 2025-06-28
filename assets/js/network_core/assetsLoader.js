// Constants
const ASSETS = ["block", "ground"];

/**
 * Preload named image assets.
 * @returns {Promise<Object<string,HTMLImageElement>>}
 */
export async function initAssets() {
  const result = {};
  await Promise.all(
    ASSETS.map(name => new Promise(res => {
      const img = new Image();
      img.src = `../images/${name}.png`;
      img.onload = () => { result[name] = img; res(); };
    }))
  );
  return result;
}
