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

\- `2026-11-12T22:11:06Z`: Most of this looks already done by wvtknvqk (Nov 9, 'iPhone-sized build and explore UI'): compact top bar without title, time picker as a menu, tools moved into the palette as a scrolling row (no left column), style picker as a menu, smaller thumbnails in landscape, materials respect safe areas, explore has a joystick plus Stroll/Fly buttons (touch for space/F), ContentView no longer sets a min frame. Not done: build-mode camera control is off on iOS (noted in that commit: it hangs at launch).

Punting the close: I could not verify on a phone. The iOS Simulator build fails because MetalSprockets/MetalSupport need Metal 4 (MTL4CommandBuffer etc. are missing from the simulator SDK), and no device is attached. Unblocker: run it on an iPhone (portrait + landscape) and report anything clipped, overlapping or unreachable; or close #1 if it looks right.

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

- `2026-11-12T19:17:00Z`: Looked at restyling the animals after #2. Punting: the issue says the approach is open, and it's a design call (e.g. kokeshi-style turned bodies with painted markings vs. Japanese wooden folk-toy shapes per animal). It also overlaps #6-#10, which move the crane, frog, cat, koi and tanuki to ModelScript files, so restyling the Swift geometry now may be redone there. Unblocker: pick a direction (turned/lathed bodies + painted patterns like the villagers, or a reference toy per animal) and whether to do it before or as part of the ModelScript ports.
- `2026-11-12T22:08:40Z`: Re-checked in the second autonomous run. The ModelScript ports (#6-#10) are done, so the overlap is gone: a restyle now means editing crane/frog/cat/koi/tanuki/fox .json files. Still punting: the style direction is still unanswered. Unblocker: pick one, e.g. (a) lathed kokeshi-like bodies with painted markings, as the villagers have, or (b) a specific Japanese wooden folk toy as the reference for each animal.

---

## 4: World units are not meters; object sizes disagree with each other

+++
status: closed
priority: high
kind: bug
labels: effort:l, area:world
created: 2026-11-10T05:03:35Z
updated: 2026-11-12T21:03:32Z
closed: 2026-11-12T21:03:32Z
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
- `2026-11-12T20:04:15Z`: Correction to my earlier comment: villagers are scaled by 1.7 when placed (Villagers.place), and the kokeshi model is ~0.29 tall, so a villager is ~0.49 units on screen, not 0.32. A 1.7 m villager means a world scale of ~x3.5, not x5. At x3.5: grid cell ~7.4 m, island radius ~91 m, fox (0.5 long) ~1.75 m (still too big; real ~1 m), explore eye height (0.55) ~1.9 m (a bit above a 1.7 m person's eyes, ~1.6 m).

---

## 5: Not all models are ModelScript files

+++
status: closed
priority: low
kind: task
labels: aspirational, effort:xl, area:modelscript
depends: 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19
created: 2026-11-10T05:03:40Z
updated: 2026-11-12T21:07:56Z
closed: 2026-11-12T21:07:56Z
+++

Only the fox (`Models/fox.json`) is a ModelScript file. Every other model is hand-written Swift geometry in `Creatures.swift`, `Villagers.swift`, `PropMesher.swift`, `TreeMesher.swift`, `BuildingMesher.swift` and `GroundMesher.swift`.

Aspirational goal: every model is generated from ModelScript files. Fixed-shape models (animals, villagers, simple props) can move now. Procedural models (buildings that stretch and join neighbors, trees with per-instance variation, cell-shaped props, ground) need features ModelScript doesn't have yet; those are tracked in the ModelScript repo.

Per-model issues are labelled `modelscript`. Related: #4 (meter scale).

- `2026-11-12T21:07:56Z`: All fourteen sub-issues (#6-#19) are done. The remaining Swift-built models are filed individually: #24 zen garden, #25 koi pond, #26 bridge, #27 bamboo fence, #28 azalea, #29 stones, #30 buildings, #31 trees, #32 ground. Closing this tracking issue.

---

## 6: Crane is hand-written geometry, not a ModelScript file

+++
status: closed
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:49Z
updated: 2026-11-12T19:20:04Z
closed: 2026-11-12T19:20:04Z
+++

The crane animal is built in Swift (`Creatures.mesh`, `.crane`). Two styles differ by body and neck color and a red crown on style 0.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 7: Frog is hand-written geometry, not a ModelScript file

+++
status: closed
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:49Z
updated: 2026-11-12T19:21:19Z
closed: 2026-11-12T19:21:19Z
+++

The frog animal is built in Swift (`Creatures.mesh`, `.frog`). Two styles differ by skin color.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 8: Cat is hand-written geometry, not a ModelScript file

+++
status: closed
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:49Z
updated: 2026-11-12T19:23:04Z
closed: 2026-11-12T19:23:04Z
+++

The cat animal is built in Swift (`Creatures.mesh`, `.cat`, plus `quadruped`). Three styles differ by fur color; style 0 (calico) has extra patches.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 9: Koi is hand-written geometry, not a ModelScript file

+++
status: closed
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:49Z
updated: 2026-11-12T19:26:22Z
closed: 2026-11-12T19:26:22Z
+++

The koi is built in Swift (`Creatures.mesh`, `.koi`). Three styles differ by two colors.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 10: Tanuki is hand-written geometry, not a ModelScript file

+++
status: closed
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:49Z
updated: 2026-11-12T19:28:03Z
closed: 2026-11-12T19:28:03Z
+++

The tanuki animal is built in Swift (`Creatures.mesh`, `.tanuki`, plus `quadruped`).

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 11: Tanuki statue is hand-written geometry, not a ModelScript file

+++
status: closed
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:49Z
updated: 2026-11-12T19:29:41Z
closed: 2026-11-12T19:29:41Z
+++

The shigaraki tanuki statue (tanuki style 1) is built in Swift (`Creatures.tanukiStatue`).

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 12: Villager is hand-written geometry, not a ModelScript file

+++
status: closed
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:49Z
updated: 2026-11-12T19:33:28Z
closed: 2026-11-12T19:33:28Z
+++

Villagers are built in Swift (`Villagers.makeLooks`). Eight outfits differ by robe, hair and optional hat colors. See also #2 (kokeshi look).

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 13: Stone lantern is hand-written geometry, not a ModelScript file

+++
status: closed
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:50Z
updated: 2026-11-12T19:36:00Z
closed: 2026-11-12T19:36:00Z
+++

The stone lantern is built in Swift (`PropMesher.stoneLantern`). Styles differ in shape; the item's level sets how many lanterns stand in a ring.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 14: Fox statue is hand-written geometry, not a ModelScript file

+++
status: closed
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:50Z
updated: 2026-11-12T19:38:03Z
closed: 2026-11-12T19:38:03Z
+++

The kitsune statue is built in Swift (`PropMesher.fox`). Three styles differ by material; level sets how many statues stand in a ring. Each statue has seeded random variation.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 15: Torii is hand-written geometry, not a ModelScript file

+++
status: closed
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:50Z
updated: 2026-11-12T19:41:38Z
closed: 2026-11-12T19:41:38Z
+++

The small torii is built in Swift (`PropMesher.torii`, `.torii`). Styles change colors; level sets how many gates stand in a row.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 16: Great torii is hand-written geometry, not a ModelScript file

+++
status: closed
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:50Z
updated: 2026-11-12T19:44:18Z
closed: 2026-11-12T19:44:18Z
+++

The great torii is built in Swift (`PropMesher`, `.greatTorii`). Style 2 (Itsukushima) adds braced legs.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 17: Paper lantern is hand-written geometry, not a ModelScript file

+++
status: closed
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:50Z
updated: 2026-11-12T19:49:06Z
closed: 2026-11-12T19:49:06Z
+++

The paper lantern string is built in Swift (`PropMesher`, `.paperLantern`): two poles and a row of lanterns. Level sets pole height and lantern count; styles set lantern colors.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 18: Well is hand-written geometry, not a ModelScript file

+++
status: closed
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:50Z
updated: 2026-11-12T19:52:31Z
closed: 2026-11-12T19:52:31Z
+++

The well is built in Swift (`PropMesher`, `.well`). Two styles: stone or cedar.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 19: Bell tower is hand-written geometry, not a ModelScript file

+++
status: closed
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-10T05:03:51Z
updated: 2026-11-12T19:54:51Z
closed: 2026-11-12T19:54:51Z
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
status: closed
priority: high
kind: bug
labels: effort:m, area:camera
created: 2026-11-12T19:02:36Z
updated: 2026-11-12T21:29:22Z
closed: 2026-11-12T21:29:22Z
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
- `2026-11-12T21:29:22Z`: Fixed by guarding: TownModel now rejects non-finite rtsPose and cameraMatrix writes (keeps the last good pose and logs a fault with the stack). Which writer produced the NaN is still unknown; if the fault log fires, it names the caller.

---

## 23: Camera falls forever after turning off flying in explore mode

+++
status: closed
priority: medium
kind: bug
labels: effort:s, area:camera
created: 2026-11-12T19:06:03Z
updated: 2026-11-12T22:08:22Z
closed: 2026-11-12T22:08:22Z
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

## 24: Zen garden is hand-written geometry, not a ModelScript file

+++
status: closed
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-12T21:07:52Z
updated: 2026-11-12T22:21:08Z
closed: 2026-11-12T22:21:08Z
+++

The zen garden (PropMesher, .zenGarden) is built in Swift: rocks with raked gravel rings around them. Rock count, placement and sizes vary per item seed and level. Formerly tracked by #5.

---

## 25: Koi pond is hand-written geometry, not a ModelScript file

+++
status: closed
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-12T21:07:52Z
updated: 2026-11-12T22:26:48Z
closed: 2026-11-12T22:26:48Z
+++

The koi pond (PropMesher, .koiPond) is built in Swift: edge stones scattered around the cell outline, koi, lily pads, lotus, reeds and irises. Placement depends on the cell polygon and the item seed. Formerly tracked by #5.

---

## 26: Bridge is hand-written geometry, not a ModelScript file

+++
status: closed
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-12T21:07:52Z
updated: 2026-11-12T22:31:42Z
closed: 2026-11-12T22:31:42Z
+++

The arched bridge (PropMesher, .bridge) is built in Swift: an arched deck in 12 steps with side boards, railings, posts and gold caps on style 0. Formerly tracked by #5.

---

## 27: Bamboo fence is hand-written geometry, not a ModelScript file

+++
status: closed
priority: low
kind: task
labels: area:modelscript, effort:m
created: 2026-11-12T21:07:52Z
updated: 2026-11-12T23:10:18Z
closed: 2026-11-12T23:10:18Z
+++

The bamboo fence (PropMesher, .bambooFence) is built in Swift along the cell edges that don't join another fence, with post count from each edge's length. It depends on the cell polygon and its neighbors. Formerly tracked by #5.

---

## 28: Azalea is hand-written geometry, not a ModelScript file

+++
status: closed
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-12T21:07:52Z
updated: 2026-11-12T22:44:18Z
closed: 2026-11-12T22:44:18Z
+++

The azalea bushes (PropMesher, .azalea) are built in Swift: leaf blobs with flower blobs, count and placement from the cell polygon and item seed. Formerly tracked by #5.

---

## 29: Stones are hand-written geometry, not a ModelScript file

+++
status: closed
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-12T21:07:52Z
updated: 2026-11-12T22:54:54Z
closed: 2026-11-12T22:54:54Z
+++

The stones (PropMesher, .stones) are built in Swift: stacked stones on style 2, otherwise mossy rocks scattered in the cell; sizes and rotations from the item seed. Formerly tracked by #5.

---

## 30: Buildings are hand-written geometry, not ModelScript files

+++
status: open
priority: low
kind: task
labels: area:modelscript, effort:xl
created: 2026-11-12T21:07:52Z
updated: 2026-11-12T21:25:42Z
+++

All buildings (BuildingMesher) are built in Swift. They stretch across cells, join neighboring cells of the same building, inset walls along exterior edges, and build roofs over the combined footprint. Formerly tracked by #5, which noted this needs ModelScript features that don't exist yet.

---

## 31: Trees are hand-written geometry, not ModelScript files

+++
status: open
priority: low
kind: task
labels: area:modelscript, effort:l
created: 2026-11-12T21:07:52Z
updated: 2026-11-12T21:25:42Z
+++

All trees (TreeMesher) are built in Swift with recursive random branching per item seed and level. Formerly tracked by #5, which noted per-instance variation needs ModelScript features that don't exist yet.

- `2026-11-12T21:10:18Z`: Correction to #5's note: ModelScript does support recursion. A component can use itself; parts with a false `if` are skipped before they are built, and use is limited to 32 levels (ModelCompiler.componentTooDeep). Seeded random() also exists. So trees are not blocked on missing features.
- `2026-11-12T23:10:41Z`: Looked at porting TreeMesher. Punting: it needs a design decision. Recursion exists in ModelScript, but expressions have no sin/cos (only min, max, sqrt, abs, random), and every tree picks random branch and blob directions with cos/sin of random angles. Two ways forward: (a) Swift computes every branch/blob/petal transform from the seed and passes flat lists, so trees stay identical, but the model file is just a generic primitive list with no tree logic; or (b) add sin/cos to ModelScript and author trees in-model with random(), which changes how every tree looks (different random sequence). Also unmeasured: each tree would be a CSG union of tens to hundreds of parts, and trees are the most common item, so build time for a full island could suffer. Unblocker: pick (a) or (b), and whether a changed tree look is acceptable.

---

## 32: Ground is hand-written geometry, not ModelScript files

+++
status: open
priority: low
kind: task
labels: area:modelscript, effort:l
created: 2026-11-12T21:07:52Z
updated: 2026-11-12T21:25:42Z
+++

Ground cells (GroundMesher) are built in Swift from each cell's polygon: beveled tops, sides down to lower neighbors, stone courses, and scattered decoration. Formerly tracked by #5, which noted cell-shaped geometry needs ModelScript features that don't exist yet.

- `2026-11-12T23:12:15Z`: Measured before porting. Over 50 cells of Town.sample(seed: 3) (510 cells total): the current GroundMesher.build takes about 0.015 ms per cell, including bevel, side walls, stone courses and decorations. A ModelScript ground cell with only two extrudes of the cell outline (no bevel, sides, courses or decorations) takes about 0.49 ms per cell to compile, about 32x slower for a fraction of the geometry. A full port (per-side walls down to each neighbor, bevel strip, stone courses, scattered grass and pebbles) would cost several times more again, and the whole island's ground is rebuilt on load and its chunks on every terrain edit. Punting: whether that cost is acceptable (or worth caching or batching) is a design call. Unblocker: decide if ground should stay in Swift (close as won't-do) or if a slower build is acceptable.

---

## 33: ModelScript colors are matched to Paint by nearest color, not by palette name

+++
status: closed
priority: low
kind: task
labels: area:modelscript, effort:s
created: 2026-11-12T21:10:18Z
updated: 2026-11-12T23:04:14Z
closed: 2026-11-12T23:04:14Z
+++

ModelLibrary turns each compiled triangle into a Paint by finding the Paint with the nearest color (`Paint.nearest`, `MeshBuilder.append(_ model:)` in Models.swift). So every palette color in a model file must exactly match a Paint hex value, and no two Paints may share a color (the gold koi came out grey before #9 gave each Paint a unique hex; `everyPaintRoundTripsThroughItsColor` guards this).

ModelScript compiled models now report which palette entry each triangle came from (`CompiledModel.paletteName(of:)`, ModelScript issue #3), and the model files already use Paint names as palette names. The color matching is no longer the only option.

---

## 34: No weather or seasons

+++
status: new
priority: medium
kind: feature
created: 2026-11-12T23:33:42Z
+++

The town always looks the same apart from time of day. There is no weather (rain, snow, fog, wind) and no seasons (spring blossom, summer green, autumn leaves, winter snow).

---

## 35: Night sky has no stars or moon

+++
status: new
priority: medium
kind: feature
created: 2026-11-12T23:33:42Z
+++

At night the sky is a plain dark color. There are no stars and no moon.

---

## 36: Sky has no clouds

+++
status: new
priority: medium
kind: feature
created: 2026-11-12T23:33:42Z
+++

The sky is empty at every time of day; there are no clouds.

---

## 37: Chimneys don't smoke

+++
status: new
priority: medium
kind: feature
created: 2026-11-12T23:33:42Z
+++

Buildings with chimneys show no smoke rising from them.

---

## 38: No deer

+++
status: new
priority: medium
kind: feature
created: 2026-11-12T23:33:42Z
+++

The town has no deer. Nara-style deer that nod (bow) would fit the setting.

---
