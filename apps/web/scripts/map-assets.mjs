// Copies MapLibre's web worker next to the dashboard's other map assets (public/map), so the
// map needs no third-party server at runtime. The bundler cannot follow MapLibre's own
// reference to the file, so the dashboard points MapLibre at /map/maplibre-gl-worker.mjs.
// Runs before `next dev` and `next build`.
import { copyFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const from = join(root, "node_modules", "maplibre-gl", "dist", "maplibre-gl-worker.mjs");
const to = join(root, "public", "map", "maplibre-gl-worker.mjs");
mkdirSync(dirname(to), { recursive: true });
copyFileSync(from, to);
