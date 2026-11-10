# Satellite imagery for the estate map

The dashboard draws the estate on satellite imagery with MapLibre GL JS. The map is locked to the
estate's boundary (drawn by the estate admin in Staff and settings, Estate map): `maxBounds` is the
boundary's box with a small margin and `minZoom` is the zoom at which that box fills the view.
Everything Gatelog draws (boundary, grid, gates, guards, shuttles, rides, entries) is our own layer
on top, so the imagery provider can change without touching the markers.

All provider code is in `app/(dashboard)/_map/provider.ts`, plus the Google session route
`app/(dashboard)/dashboard/map-session/route.ts`. Day and night use the same imagery: at night it is
darkened and desaturated with `raster-brightness-max`, `raster-saturation` and `raster-contrast`
(`RASTER_PAINT` in provider.ts).

MapLibre's web worker is copied from `node_modules` to `public/map/` by `scripts/map-assets.mjs`
before `next dev` and `next build` (gitignored), because the bundler cannot follow MapLibre's own
reference to it.

## Development: Esri World Imagery (default)

Nothing to set. With `NEXT_PUBLIC_MAP_PROVIDER` unset the map uses
`https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}` and
shows "Imagery: Esri, Maxar, Earthstar Geographics · prototype use only". Esri's terms do not cover
production use without an ArcGIS account, so this is for development and demos only.

`NEXT_PUBLIC_MAP_DEFAULT_CENTER=lng,lat` sets where the map editor opens before an estate has a
boundary. The admin can also type the estate's coordinates in the editor.

## Production: Google Map Tiles API (decided)

Google's Map Tiles API serves 2D satellite tiles for use in third-party renderers such as MapLibre,
on condition that the Google logo and the attribution for the current view are shown. That is the
route taken: MapLibre stays the renderer, so the markers, the editor and the bounds lock are the
same in every environment. (The fallback, if the terms ever change, is the Maps JavaScript API with
`restriction: { latLngBounds, strictBounds: true }` and our markers drawn over it; it would replace
`EstateMap.tsx`'s renderer, not the rest of the dashboard.)

How it works:

1. The browser asks `/dashboard/map-session` (signed-in users only). The server calls
   `POST https://tile.googleapis.com/v1/createSession?key=GOOGLE_MAPS_SERVER_KEY` with
   `{"mapType":"satellite","language":"en-GB","region":"NG","scale":"scaleFactor2x","highDpi":true}`
   and caches the session until a day before it expires (sessions last about two weeks).
2. The browser fetches tiles from
   `https://tile.googleapis.com/v1/2dtiles/{z}/{x}/{y}?session=...&key=NEXT_PUBLIC_GOOGLE_MAPS_KEY`.
   Google requires a key on every tile request, so this key is in the browser by design. It must be
   restricted (below). Proxying tiles through our server to hide it would put every tile through
   Vercel and is not needed once the key is restricted.
3. After each move the browser calls
   `https://tile.googleapis.com/tile/v1/viewport?session=...&zoom=...&north=...&south=...&east=...&west=...&key=...`
   and shows the returned copyright in the credit chip, with the Google logo.

Environment:

| Variable | Where | Value |
| --- | --- | --- |
| `NEXT_PUBLIC_MAP_PROVIDER` | build | `google` |
| `NEXT_PUBLIC_GOOGLE_MAPS_KEY` | build (browser) | the browser key |
| `GOOGLE_MAPS_SERVER_KEY` | server only | the server key |
| `NEXT_PUBLIC_MAP_MAX_ZOOM` | build, optional | `21` (default for Google) |

Google Cloud setup:

1. One Google Cloud project for Gatelog maps, with billing on.
2. Enable **Map Tiles API**.
3. Browser key: API restriction "Map Tiles API" only; application restriction "HTTP referrers" with
   the dashboard's origins (for example `https://app.gatelog.ng/*` and the Vercel preview domain).
4. Server key: API restriction "Map Tiles API" only. Vercel has no fixed egress IPs, so restrict it
   by API only and keep it in Vercel's encrypted env (server-side, not `NEXT_PUBLIC_`).
5. Both keys must be in the same project: a session is tied to the project that created it.
6. Set a daily quota cap on the Map Tiles API in the console so a bug cannot run up the bill.
7. Add Google's logo files from Google's brand resources for Maps Platform as
   `public/map/google_on_white.png` (day) and `public/map/google_on_non_white.png` (night). They
   could not be downloaded from this machine; until they are added, the chip shows the word "Google".

The NEXT_PUBLIC_ variables are inlined at build time: rebuild after changing them.

## Another XYZ provider (Mapbox Satellite and the like)

```
NEXT_PUBLIC_MAP_PROVIDER=custom
NEXT_PUBLIC_MAP_TILES_URL=https://api.mapbox.com/v4/mapbox.satellite/{z}/{x}/{y}@2x.jpg90?access_token=pk...
NEXT_PUBLIC_MAP_ATTRIBUTION=© Mapbox © Maxar
NEXT_PUBLIC_MAP_TILE_SIZE=512
NEXT_PUBLIC_MAP_MAX_ZOOM=19
```

## Per estate

Nothing per estate lives in the tile setup: the imagery covers the world, and the lock comes from
the boundary the admin draws. A new estate needs only its boundary, gate pins and places, drawn in
the editor.
