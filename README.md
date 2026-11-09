# Tiny Torii

A small Japanese town builder in the spirit of Townscaper, built on [SceneSprockets](../../MetalSprockets/SceneSprockets).

You build on an organic grid: Lloyd-relaxed Voronoi cells on an island. Place houses, inns, teahouses, storehouses, castles, pagodas, shrines and temples; torii (small, great, and tunnels of them), kitsune, stone and paper lanterns, bell towers, zen gardens, koi ponds, drum bridges, wells, bamboo fences, azaleas and stones; cherry, plum, maple, pine, cedar, bamboo, ginkgo and willow; and paint grass, moss, gravel, paths, sand, water and rice paddies. Then walk through the town, stroll, or fly over it at any time of day.

## App

Open `TinyTorii.xcodeproj` and run the TinyTorii scheme (macOS or iOS). Or `xcb build`.

Build mode:

| Tool | What it does |
|---|---|
| Place (1) | Tap a cell to place the chosen thing. Drag to paint ground. |
| Grow (2) | Add a story, grow a tree, add torii to a tunnel, or raise the ground. |
| Shrink (3) | The opposite. |
| Stretch (4) | Drag from a building across its neighbors to make one bigger building. Trees, props and ground spread too. |
| Rotate (5) | Turn gates, foxes, bridges and lanterns. |
| Restyle (6) | Cycle a thing's style. |
| Remove (7) | Tap or drag to clear cells. |

Drag to orbit, scroll or pinch to zoom. When a tool paints along drags, hold Option to orbit. T cycles the time of day, ⌘Z undoes, E explores.

Explore mode: W A S D or arrows to walk, drag to look, Shift to hurry, Space to stroll, F to fly, Esc to go back to building. On iOS use the joystick.

The town saves itself to `~/Library/Application Support/TinyTorii/town.json`. The map menu makes a new island, grows a sample town, and imports or exports towns as JSON.

## CLI

`torii-cli` renders the same scenes offscreen, for testing and screenshots.

```sh
xcb build TinyToriiSupport/torii-cli
cd Packages/TinyToriiSupport
.build/debug/torii-cli render out.png --seed 3 --view low --time dusk     # overview | aerial | low | street | yaw,pitch,distance[,x,y,z]
.build/debug/torii-cli render out.png --walk 60 --time night             # stroll for 60 seconds, then look
.build/debug/torii-cli render out.png --fly 20                           # bird's-eye flight
.build/debug/torii-cli render out.png --empty --ops "place castle 0 260; grow 260; stretch 260 261"
.build/debug/torii-cli render out.png --file town.json                   # a saved town
.build/debug/torii-cli gallery /tmp/gallery [--kinds castle,pagoda]      # close-ups of every kind and style
.build/debug/torii-cli thumbnails Sources/TinyToriiSupport/Thumbnails    # the palette pictures
.build/debug/torii-cli icon Design/icon-source.png                       # the app icon picture
.build/debug/torii-cli save town.json --seed 4
.build/debug/torii-cli info --seed 4
```

## Code

Everything lives in `Packages/TinyToriiSupport`:

- `Grid.swift`: the Voronoi grid with welded corners and neighbors.
- `Town.swift`, `Catalog.swift`: the editable model (cells, items, styles) and its file format.
- `BuildingMesher.swift`: walls, tiers, skirts, balconies, curved roofs and ridges; stretched cells share walls and roofs.
- `PropMesher.swift`, `TreeMesher.swift`, `GroundMesher.swift`: everything else.
- `Palette.swift`: colors as a palette texture, so each chunk of the town draws in one or two draws.
- `TownScene.swift`: the scene graph, chunking, pop-in animation, lamps, picking and walkability.
- `TownModel.swift`, `Brush.swift`, `Explorer.swift`, `TownView.swift`: the app.
- `SampleTown.swift`: a town that grows itself.
