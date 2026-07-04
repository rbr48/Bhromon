# ADR 006: Offline Maps via MapLibre Offline Regions

## Status
Accepted — 2026-07-04

## Context
The original offline map implementation (`TileDownloader`) manually fetched
vector tiles over HTTP into app documents storage and generated a minimal
hand-written MapLibre style pointing at `file://` tile URLs. It failed in
production for four compounding reasons:

1. The tile endpoint (`basemaps.cartocdn.com/vectortiles/voyager-gl/v1/...`)
   returned **404 for every tile**; download errors were swallowed while
   progress advanced, so the vault reported success with an empty tile folder.
2. The hand-written style referenced source-layers (`roads`, `buildings`)
   that do not exist in the CARTO `carto.streets` schema (`transportation`,
   `building`), so even valid tiles would have rendered mostly empty.
3. Only zoom 10–12 was fetched while the style declared maxzoom 14, blanking
   the map outside that narrow zoom band.
4. No glyphs or sprites were downloaded, so labels and icons could never
   render offline.

The result was the reported "white screen" in offline mode.

## Decision
Use MapLibre GL's native offline-region engine (`downloadOfflineRegion`)
via `OfflineMapService` (`lib/core/services/offline_map_service.dart`):

- A region download stores the **actual production style JSON, sprites,
  glyphs and all vector tiles (z8–z14)** in MapLibre's internal cache DB.
- Offline rendering is **transparent**: the map keeps using the normal
  online style URL and MapLibre serves cached resources when the network is
  unavailable. No style switching, no `file://` URLs, no view recreation.
- Both the light (voyager) and dark (dark-matter) styles are downloaded per
  district; they share the same `carto.streets` tile source, so the second
  pass costs only the style/sprites/glyphs.
- Regions are tagged with `{district: <name>}` metadata for listing and
  deletion; deleting a vault bundle also evicts its map region.
- The per-download tile limit is raised to 60,000 (default 6,000) because
  large districts exceed the default at z14.

The map screen shows a connectivity banner (with a shortcut to the Offline
Vault) instead of a silent blank map when the device is offline.

## Consequences
- Full-fidelity offline maps: labels (including Bengali place names), icons,
  water, roads, buildings — identical to the online map.
- Vector tiles overzoom natively beyond z14, so every zoom level renders.
- MapLibre manages storage dedup/eviction; district sizes are roughly
  10–40 MB depending on area.
- Satellite style is online-only (raster imagery is too heavy to bundle);
  it now uses keyless Esri World Imagery instead of the broken MapTiler
  demo-key URL.
- maplibre_gl 0.20 cannot cancel an in-flight region download; the vault UI
  treats downloads as atomic (they can be deleted afterwards).
