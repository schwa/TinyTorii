# ISSUES.md

File format: <https://github.com/schwa/issues-format>

---

## 1: Build and explore UI does not fit an iPhone screen

+++
status: open
priority: medium
kind: feature
labels: effort:l, area:ui
created: 2026-11-09T03:17:47Z
updated: 2026-11-12T19:10:20Z
+++

The app builds for iOS, but TownView's layout was designed for a Mac window (min 900x600) and hasn't been checked on a phone.

On an iPhone (portrait and landscape):
- The build top bar (title, undo/redo, map menu, status text, time-of-day segmented picker, Explore button) is one wide row that won't fit a phone width.
- The bottom palette (category tabs, kind title, style segmented picker, thumbnails) is also one wide row; the style picker can be long (up to 4 names).
- The left tool column has 7 x 40pt buttons stacked above the palette, which may overlap the palette or run off a short landscape screen.
- Explore overlay puts a long key-help line ('W A S D to walk ...') and a time picker in one row; the keyboard help is meaningless on a phone.
- Keyboard-only features (tool numbers, T for time, X to explore, RTS keys, M mouse capture) have no touch equivalent where they matter.
- ContentView sets .frame(minWidth: 900, minHeight: 600) for every platform.
- Safe areas (notch, home indicator) are not considered for the overlays.

Expected: the build and explore UI are usable on iPhone in portrait and landscape, every action is reachable by touch, and nothing is clipped or overlapping.

---

## 2: Villagers should look like sōsaku kokeshi dolls

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:models
created: 2026-11-10T04:18:52Z
updated: 2026-11-12T19:16:50Z
closed: 2026-11-12T19:16:50Z
+++

The villager figures should have the look of sōsaku (creative) kokeshi dolls: wooden Japanese dolls with a simple turned body and a round head, no arms or legs, and modern, freely designed painted patterns. Unlike traditional kokeshi, sōsaku dolls vary in shape and decoration from one artist to another.

Villagers are made in `Villagers.swift`.

- `2026-11-12T19:16:50Z`: Villagers are now sōsaku kokeshi: lathe-turned bodies with eight different profiles (column, flared, waisted, bell, belly...), painted bands, a turned round head with a painted hair cap and two eye marks. No unit test: this is a visual change with no testable behavior; checked by rendering with torii-cli.

---

## 3: Animals don't match the kokeshi villager style

+++
status: open
priority: medium
kind: feature
labels: effort:m, area:models
depends: 2
created: 2026-11-10T04:19:35Z
updated: 2026-11-12T19:10:20Z
+++

Once villagers look like sōsaku kokeshi dolls (#2), the animals (creatures) will look out of place next to them. The animals should feel like they belong to the same wooden, turned, hand-painted doll style.

How to do this is open: kokeshi are human figures, so there's no direct animal equivalent. Japanese wooden folk toys and animal-shaped kokeshi exist and may help as references.

---

## 4: World units are not meters; object sizes disagree with each other

+++
status: open
priority: high
kind: bug
labels: effort:l, area:world
created: 2026-11-10T05:03:35Z
updated: 2026-11-12T19:10:20Z
+++

TinyTorii's units have no real-world scale, and objects are sized inconsistently with each other. The intended scale is 1 unit = 1 meter.

Current sizes (units):
- Villager: about 0.32 tall (`Villagers.swift`).
- Explore camera eye height: 0.55 (`Explorer.eyeHeight`), so the walker's eyes are well above a villager's head.
- Fox: about 0.5 long (`Models/fox.json`).
- Grid cell spacing: 2.1; island radius: 26 (`Grid.swift`).
- Terrace step: 0.45 (`Town.elevationStep`).
- Small torii: 1.0 tall; great torii: 2.4 tall (`PropMesher.swift`).
- Explore gravity is a guess scaled to these units (3.5, `Explorer.swift`).

Real-world reference: a person is about 1.6 m, a fox about 1 m long, a great torii 8–16 m.

This matters for ModelScript models (sizes are documented in meters), walking speed, gravity, camera ranges, fog and shadow distances, and anything shared with other projects.

- `2026-11-12T19:12:21Z`: Tried scoping a rescale to meters. Punting: this is a cross-cutting change (100+ size/distance constants across grid, meshers, models, camera ranges, explore gravity/speed, fog and shadow distances), and the target sizes are a design decision, not a uniform factor. Scaling villagers 0.32 -> 1.6 m is x5, which would make the fox 2.5 m and the small torii 5 m, so objects need individual targets too. Unblocker: confirm (a) a uniform world scale factor (e.g. x5, so a grid cell is ~10.5 m and the island radius ~130 m) and (b) target sizes for the outliers (fox ~1 m long, eye height ~1.5 m, small/great torii heights), and I'll do it as a mechanical pass.

---

## 5: Not all models are ModelScript files

+++
status: open
priority: low
kind: task
labels: aspirational, effort:xl, area:modelscript
depends: 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19
created: 2026-11-10T05:03:40Z
updated: 2026-11-12T19:11:10Z
+++

Only the fox (`Models/fox.json`) is a ModelScript file. Every other model is hand-written Swift geometry in `Creatures.swift`, `Villagers.swift`, `PropMesher.swift`, `TreeMesher.swift`, `BuildingMesher.swift` and `GroundMesher.swift`.

Aspirational goal: every model is generated from ModelScript files. Fixed-shape models (animals, villagers, simple props) can move now. Procedural models (buildings that stretch and join neighbors, trees with per-instance variation, cell-shaped props, ground) need features ModelScript doesn't have yet; those are tracked in the ModelScript repo.

Per-model issues are labelled `modelscript`. Related: #4 (meter scale).

---

## 6: Crane is hand-written geometry, not a ModelScript file

+++
status: open
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:49Z
updated: 2026-11-12T19:11:10Z
+++

The crane animal is built in Swift (`Creatures.mesh`, `.crane`). Two styles differ by body and neck color and a red crown on style 0.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 7: Frog is hand-written geometry, not a ModelScript file

+++
status: open
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:49Z
updated: 2026-11-12T19:11:10Z
+++

The frog animal is built in Swift (`Creatures.mesh`, `.frog`). Two styles differ by skin color.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 8: Cat is hand-written geometry, not a ModelScript file

+++
status: open
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:49Z
updated: 2026-11-12T19:11:10Z
+++

The cat animal is built in Swift (`Creatures.mesh`, `.cat`, plus `quadruped`). Three styles differ by fur color; style 0 (calico) has extra patches.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 9: Koi is hand-written geometry, not a ModelScript file

+++
status: open
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:49Z
updated: 2026-11-12T19:11:10Z
+++

The koi is built in Swift (`Creatures.mesh`, `.koi`). Three styles differ by two colors.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 10: Tanuki is hand-written geometry, not a ModelScript file

+++
status: open
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:49Z
updated: 2026-11-12T19:11:10Z
+++

The tanuki animal is built in Swift (`Creatures.mesh`, `.tanuki`, plus `quadruped`).

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 11: Tanuki statue is hand-written geometry, not a ModelScript file

+++
status: open
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:49Z
updated: 2026-11-12T19:11:10Z
+++

The shigaraki tanuki statue (tanuki style 1) is built in Swift (`Creatures.tanukiStatue`).

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 12: Villager is hand-written geometry, not a ModelScript file

+++
status: open
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:49Z
updated: 2026-11-12T19:11:10Z
+++

Villagers are built in Swift (`Villagers.makeLooks`). Eight outfits differ by robe, hair and optional hat colors. See also #2 (kokeshi look).

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 13: Stone lantern is hand-written geometry, not a ModelScript file

+++
status: open
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:50Z
updated: 2026-11-12T19:11:10Z
+++

The stone lantern is built in Swift (`PropMesher.stoneLantern`). Styles differ in shape; the item's level sets how many lanterns stand in a ring.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 14: Fox statue is hand-written geometry, not a ModelScript file

+++
status: open
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:50Z
updated: 2026-11-12T19:11:10Z
+++

The kitsune statue is built in Swift (`PropMesher.fox`). Three styles differ by material; level sets how many statues stand in a ring. Each statue has seeded random variation.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 15: Torii is hand-written geometry, not a ModelScript file

+++
status: open
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:50Z
updated: 2026-11-12T19:11:10Z
+++

The small torii is built in Swift (`PropMesher.torii`, `.torii`). Styles change colors; level sets how many gates stand in a row.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 16: Great torii is hand-written geometry, not a ModelScript file

+++
status: open
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:50Z
updated: 2026-11-12T19:11:10Z
+++

The great torii is built in Swift (`PropMesher`, `.greatTorii`). Style 2 (Itsukushima) adds braced legs.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 17: Paper lantern is hand-written geometry, not a ModelScript file

+++
status: open
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:50Z
updated: 2026-11-12T19:11:10Z
+++

The paper lantern string is built in Swift (`PropMesher`, `.paperLantern`): two poles and a row of lanterns. Level sets pole height and lantern count; styles set lantern colors.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 18: Well is hand-written geometry, not a ModelScript file

+++
status: open
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:50Z
updated: 2026-11-12T19:11:10Z
+++

The well is built in Swift (`PropMesher`, `.well`). Two styles: stone or cedar.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 19: Bell tower is hand-written geometry, not a ModelScript file

+++
status: open
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:51Z
updated: 2026-11-12T19:11:10Z
+++

The bell tower is built in Swift (`PropMesher`, `.bellTower`). Two styles differ by post and roof color.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 20: Stack overflow when camera target reaches the island edge

+++
status: closed
priority: high
kind: bug
created: 2026-11-12T19:01:57Z
updated: 2026-11-12T19:05:27Z
closed: 2026-11-12T19:05:27Z
+++

Panning the build camera to the edge of the island crashes with EXC_BAD_ACCESS (stack overflow).

## Repro
1. Zoom out to max distance.
2. Edge-pan or key-pan the camera target until it reaches the island boundary (~`grid.radius * 1.2`).

Not reliably reproducible; depends on the exact target where the clamp triggers.

## Observed
Backtrace is ~1500 frames of `TownModel._rtsPose.didset` (TownModel.swift:80) -> `TownModel.rtsPose.modify` -> `TownModel._rtsPose.setter`, all with the same `oldValue` (target ≈ [-25.09, 0, -18.54], yaw 14.70, pitch 1.5608, distance 110). Entered from `RTSPoseModifier` `onChange` (RTSMovementModifier.swift:227).

The clamp in `rtsPose.didSet` writes `rtsPose.target`. With `@Observable` this re-enters `didSet`, and the clamped value (`simd_normalize(flat) * limit`) can have length slightly above `limit` in Float, so it clamps again forever.

---

## 21: Camera crash during orbit/zoom, not reproduced

+++
status: new
priority: medium
kind: bug
created: 2026-11-12T19:01:57Z
+++

An earlier crash during build-camera interaction (orbit/zoom/pan) could not be reproduced. Diagnostic logging (Camera category: rtsPose / cameraMatrix transitions, faults on non-finite values) was added to TownModel to catch it.

## Notes from a non-crashing run
- SwiftUI logged `onChange(of: RTSCameraPose) action tried to update multiple times per frame.`
- Many rtsPose updates are written 2-3 times with identical old/new values.
- `yaw` is never wrapped (grows past 2π, reached ~14.7).

No crash log or backtrace for the original crash yet.

---

## 22: Crash: 'Range requires lowerBound <= upperBound' in SceneGraphShadows when camera pose becomes NaN

+++
status: open
priority: high
kind: bug
labels: effort:m, area:camera
created: 2026-11-12T19:02:36Z
updated: 2026-11-12T19:10:20Z
+++

The app crashes during rendering with a fatal error in SceneSprockets shadow setup. Seen on iPad (UIKit run loop), build-mode camera. Repro steps unknown.

## Error

```
Fatal error: Range requires lowerBound <= upperBound
frame #4: SceneGraphShadows.shadowViewsAndDroppedLights(lights=2 values, bounds=(min = (NaN, NaN, NaN), max = (NaN, NaN, NaN))) at Shadows.swift:246:118
frame #5: SceneGraphShadows.prepare(entries=59 values, ..., bounds=(min = (-67.6, -0.9, -67.6), max = (67.6, 5.39, 67.6)), viewSize=(width = 2752, height = 2064)) at Shadows.swift:115:40
frame #6: closure #4 in SceneGraphElement.body.getter at SceneGraphRenderer.swift:152:30
... MetalSprockets reconcile / MTKView draw / display link
```

Shadows.swift:246 is the directional light `OrthographicProjection(... depthMode: .reversed(zClip: radius * 0.5 ... radius * 3.5))`, with `radius` = NaN.

## Observations

- Scene bounds passed to `prepare` are finite. They become NaN after `cameraRelative(..., to: cameraPosition)`, so the camera matrix given to the renderer has a NaN translation.
- In the debugger the camera-relative light transform has a finite rotation but a NaN translation; `center`, `radius`, `position`, `far`, `near`, `eye` are all NaN.
- The camera matrix comes from `TownModel.rtsPose.cameraMatrix` (Interaction3D `RTSCameraPose`). A NaN/infinite `target` or `distance` in the pose gives this pattern.
- Interaction3D gesture paths (`viewFraction`, `magnify`, `clampedDistance`) appear guarded against zero view height and zero ratios.
- Unverified suspect: the `TownModel.cameraMatrix` setter (written back by SceneView) does not reject non-finite matrices or clamp `distance`; an infinite translation would produce infinite `distance` and then NaN translation.
- Camera logging (subsystem `io.schwa.TinyTorii`, category `Camera`) was added to `TownModel` to catch which writer produces the non-finite value.

## Expected

No crash; the camera pose never becomes non-finite.

- `2026-11-12T19:10:20Z`: Possibly the same crash as #21 (camera crash not reproduced).

---

## 23: Camera falls forever after turning off flying in explore mode

+++
status: open
priority: medium
kind: bug
labels: effort:s, area:camera
created: 2026-11-12T19:06:03Z
updated: 2026-11-12T19:10:20Z
+++

In explore mode, turning flying on and then off can leave the camera falling with no ground under it. It never lands and keeps falling.

## Repro
1. Switch to explore mode.
2. Press F to fly and let it fly for a while.
3. Press F again to stop flying.

Observed: the camera drops and keeps falling forever.
Expected: the camera lands on the ground (or is put back on the island) and walking resumes.

Not confirmed: whether it only happens when flying ended outside the island / over water.

---
