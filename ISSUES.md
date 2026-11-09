# ISSUES.md

File format: <https://github.com/schwa/issues-format>

---

## 1: Build and explore UI does not fit an iPhone screen

+++
status: new
priority: medium
kind: feature
created: 2026-11-09T03:17:47Z
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
status: new
priority: medium
kind: feature
created: 2026-11-10T04:18:52Z
+++

The villager figures should have the look of sōsaku (creative) kokeshi dolls: wooden Japanese dolls with a simple turned body and a round head, no arms or legs, and modern, freely designed painted patterns. Unlike traditional kokeshi, sōsaku dolls vary in shape and decoration from one artist to another.

Villagers are made in `Villagers.swift`.

---

## 3: Animals don't match the kokeshi villager style

+++
status: new
priority: medium
kind: feature
depends: 2
created: 2026-11-10T04:19:35Z
+++

Once villagers look like sōsaku kokeshi dolls (#2), the animals (creatures) will look out of place next to them. The animals should feel like they belong to the same wooden, turned, hand-painted doll style.

How to do this is open: kokeshi are human figures, so there's no direct animal equivalent. Japanese wooden folk toys and animal-shaped kokeshi exist and may help as references.

---

## 4: World units are not meters; object sizes disagree with each other

+++
status: new
priority: high
kind: bug
created: 2026-11-10T05:03:35Z
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

---

## 5: Not all models are ModelScript files

+++
status: new
priority: low
kind: feature
labels: aspirational
created: 2026-11-10T05:03:40Z
+++

Only the fox (`Models/fox.json`) is a ModelScript file. Every other model is hand-written Swift geometry in `Creatures.swift`, `Villagers.swift`, `PropMesher.swift`, `TreeMesher.swift`, `BuildingMesher.swift` and `GroundMesher.swift`.

Aspirational goal: every model is generated from ModelScript files. Fixed-shape models (animals, villagers, simple props) can move now. Procedural models (buildings that stretch and join neighbors, trees with per-instance variation, cell-shaped props, ground) need features ModelScript doesn't have yet; those are tracked in the ModelScript repo.

Per-model issues are labelled `modelscript`. Related: #4 (meter scale).

---

## 6: Crane is hand-written geometry, not a ModelScript file

+++
status: new
priority: low
kind: task
labels: modelscript
depends: 5
created: 2026-11-10T05:03:49Z
+++

The crane animal is built in Swift (`Creatures.mesh`, `.crane`). Two styles differ by body and neck color and a red crown on style 0.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 7: Frog is hand-written geometry, not a ModelScript file

+++
status: new
priority: low
kind: task
labels: modelscript
depends: 5
created: 2026-11-10T05:03:49Z
+++

The frog animal is built in Swift (`Creatures.mesh`, `.frog`). Two styles differ by skin color.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 8: Cat is hand-written geometry, not a ModelScript file

+++
status: new
priority: low
kind: task
labels: modelscript
depends: 5
created: 2026-11-10T05:03:49Z
+++

The cat animal is built in Swift (`Creatures.mesh`, `.cat`, plus `quadruped`). Three styles differ by fur color; style 0 (calico) has extra patches.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 9: Koi is hand-written geometry, not a ModelScript file

+++
status: new
priority: low
kind: task
labels: modelscript
depends: 5
created: 2026-11-10T05:03:49Z
+++

The koi is built in Swift (`Creatures.mesh`, `.koi`). Three styles differ by two colors.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 10: Tanuki is hand-written geometry, not a ModelScript file

+++
status: new
priority: low
kind: task
labels: modelscript
depends: 5
created: 2026-11-10T05:03:49Z
+++

The tanuki animal is built in Swift (`Creatures.mesh`, `.tanuki`, plus `quadruped`).

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 11: Tanuki statue is hand-written geometry, not a ModelScript file

+++
status: new
priority: low
kind: task
labels: modelscript
depends: 5
created: 2026-11-10T05:03:49Z
+++

The shigaraki tanuki statue (tanuki style 1) is built in Swift (`Creatures.tanukiStatue`).

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 12: Villager is hand-written geometry, not a ModelScript file

+++
status: new
priority: low
kind: task
labels: modelscript
depends: 5
created: 2026-11-10T05:03:49Z
+++

Villagers are built in Swift (`Villagers.makeLooks`). Eight outfits differ by robe, hair and optional hat colors. See also #2 (kokeshi look).

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 13: Stone lantern is hand-written geometry, not a ModelScript file

+++
status: new
priority: low
kind: task
labels: modelscript
depends: 5
created: 2026-11-10T05:03:50Z
+++

The stone lantern is built in Swift (`PropMesher.stoneLantern`). Styles differ in shape; the item's level sets how many lanterns stand in a ring.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 14: Fox statue is hand-written geometry, not a ModelScript file

+++
status: new
priority: low
kind: task
labels: modelscript
depends: 5
created: 2026-11-10T05:03:50Z
+++

The kitsune statue is built in Swift (`PropMesher.fox`). Three styles differ by material; level sets how many statues stand in a ring. Each statue has seeded random variation.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 15: Torii is hand-written geometry, not a ModelScript file

+++
status: new
priority: low
kind: task
labels: modelscript
depends: 5
created: 2026-11-10T05:03:50Z
+++

The small torii is built in Swift (`PropMesher.torii`, `.torii`). Styles change colors; level sets how many gates stand in a row.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 16: Great torii is hand-written geometry, not a ModelScript file

+++
status: new
priority: low
kind: task
labels: modelscript
depends: 5
created: 2026-11-10T05:03:50Z
+++

The great torii is built in Swift (`PropMesher`, `.greatTorii`). Style 2 (Itsukushima) adds braced legs.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 17: Paper lantern is hand-written geometry, not a ModelScript file

+++
status: new
priority: low
kind: task
labels: modelscript
depends: 5
created: 2026-11-10T05:03:50Z
+++

The paper lantern string is built in Swift (`PropMesher`, `.paperLantern`): two poles and a row of lanterns. Level sets pole height and lantern count; styles set lantern colors.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 18: Well is hand-written geometry, not a ModelScript file

+++
status: new
priority: low
kind: task
labels: modelscript
depends: 5
created: 2026-11-10T05:03:50Z
+++

The well is built in Swift (`PropMesher`, `.well`). Two styles: stone or cedar.

Part of #5. The fox (`Models/fox.json`) is the example.

---

## 19: Bell tower is hand-written geometry, not a ModelScript file

+++
status: new
priority: low
kind: task
labels: modelscript
depends: 5
created: 2026-11-10T05:03:51Z
+++

The bell tower is built in Swift (`PropMesher`, `.bellTower`). Two styles differ by post and roof color.

Part of #5. The fox (`Models/fox.json`) is the example.

---
