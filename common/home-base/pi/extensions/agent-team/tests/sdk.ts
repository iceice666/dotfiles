// The loader is internal to the pinned development SDK, not a public export.
// Resolve relative to its exported entry rather than a machine's global install.
const entry = import.meta.resolve("@earendil-works/pi-coding-agent");
export const { loadExtensions } = await import(new URL("./core/extensions/loader.js", entry).href);
