#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(xcb test 2>&1); echo "$out" | grep -q "Tests passed" || { echo "$out" | tail -40; exit 1; }
out=$(xcb build 2>&1); echo "$out" | grep -q "Build succeeded" || { echo "$out" | tail -20; exit 1; }
