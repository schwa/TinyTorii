# Autoresearch: Tiny Torii frame rate

## Objective
Raise the frame rate of the Tiny Torii town (macOS app, SceneView + SceneSprockets + MetalSprockets). The app was
reported at ~20 fps (likely a Debug build). Frames are CPU-bound: GPU time is ~1-2 ms while CPU frame time is 6-10 ms
(Release) and 18-34 ms (Debug). Most CPU goes into building the MetalSprockets element tree each frame
(`Element.trackedBody`, `SceneGraphElement.body`, `SceneGraph.bounds`, per-draw parameter binding), proportional to
the number of meshes/draws and lights.

## Metrics
- **Primary**: total_ms (ms, lower is better) — sum of median Release frame times of three scenes: day overview
  (seed 7), night low view (seed 7, 10 lamp point lights), dusk street view (seed 3).
- **Secondary**: day_ms, night_ms, street_ms, gpu_day_ms, gpu_night_ms, debug_ms (Debug day+night; what the user sees).

## How to Run
`./.auto/measure.sh` — builds Release and Debug `torii-cli`, runs `torii-cli bench`, prints `METRIC` lines.
`./.auto/checks.sh` — unit tests + app build.

## Files in Scope
- `Packages/TinyToriiSupport/Sources/TinyToriiSupport/*` — town meshing, scene graph setup, lamps, villagers, creatures.
- `~/Projects/MetalSprockets/SceneSprockets` (local path dependency, separate jj repo). Changes there are NOT reverted by
  autoresearch: commit them with jj on keep, `jj restore` on discard. Keep SceneSprockets' own tests passing.
- MetalSprockets and other packages come from GitHub; making them local cascades identity conflicts (tried, reverted).

## Off Limits / Constraints
- No cheating: the bench must do the same work the app does each frame (advance villagers/creatures, actions,
  particles, full SceneGraphElement render with shadows, waiting for the GPU). Don't special-case the bench, its seeds
  or cameras. Visual output must stay the same or nearly so (check renders with `torii-cli render`).
- Don't overfit: changes should help the app generally (any town, any camera), not just these three views.
- Tests must pass.

## What's Been Tried
- Baseline (chunkSize 14, palette-texture materials): total 24.2 ms (day 6.2, night 9.7, street 8.3), debug 52.
- Earlier: chunkSize 7 → 14 halved meshes and ~halved frame time.
