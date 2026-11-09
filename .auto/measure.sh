#!/bin/bash
# Frame time of the town: Release and Debug torii-cli bench over three scenes.
set -euo pipefail
cd "$(dirname "$0")/.."
xcb build TinyToriiSupport/torii-cli -c Release 2>&1 | grep -q "Build succeeded" || { xcb build TinyToriiSupport/torii-cli -c Release 2>&1 | tail -20; exit 1; }
xcb build TinyToriiSupport/torii-cli 2>&1 | grep -q "Build succeeded" || { xcb build TinyToriiSupport/torii-cli 2>&1 | tail -20; exit 1; }
R=Packages/TinyToriiSupport/.build/release/torii-cli
D=Packages/TinyToriiSupport/.build/debug/torii-cli
med() { echo "$1" | sed -E 's/.*median ([0-9.]+) ms.*/\1/'; }
gpu() { echo "$1" | sed -E 's/.*gpu ([0-9.]+) ms.*/\1/'; }
day=$($R bench --seed 7 --frames 150 --view overview)
night=$($R bench --seed 7 --frames 150 --view low --time night)
street=$($R bench --seed 3 --frames 150 --view street --time dusk)
dday=$($D bench --seed 7 --frames 60 --view overview)
dnight=$($D bench --seed 7 --frames 60 --view low --time night)
echo "release day:    $day"; echo "release night:  $night"; echo "release street: $street"; echo "debug day:      $dday"; echo "debug night:    $dnight"
total=$(echo "$(med "$day") + $(med "$night") + $(med "$street")" | bc -l)
dtotal=$(echo "$(med "$dday") + $(med "$dnight")" | bc -l)
echo "METRIC total_ms=$total"
echo "METRIC day_ms=$(med "$day")"
echo "METRIC night_ms=$(med "$night")"
echo "METRIC street_ms=$(med "$street")"
echo "METRIC gpu_day_ms=$(gpu "$day")"
echo "METRIC gpu_night_ms=$(gpu "$night")"
echo "METRIC debug_ms=$dtotal"
