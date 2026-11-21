#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:?Choose a new output directory}"
width="${2:-1180}"
height="${3:-840}"
mode="${4:-pair}"
if [[ -e "$output" || -L "$output" ]]; then
    printf 'Output directory already exists: %s\n' "$output" >&2
    exit 2
fi
mkdir "$output"
output="$(cd "$output" && pwd)"
sources="Sources/Native/Atmosphere"
xcrun -sdk macosx metal -std=metal3.1 -O3 -c "$sources/Shaders/VolumetricSky.metal" -o "$output/Sky.air"
xcrun -sdk macosx metallib "$output/Sky.air" -o "$output/Sky.metallib"
xcrun swiftc -O Sources/Core/SchoolDay.swift Sources/Core/Atmosphere/*.swift \
    "$sources/VolumetricSky.swift" "$sources/VolumetricSkyState.swift" \
    Tests/AtmospherePreview/RenderSky.swift -o "$output/render-sky"
"$output/render-sky" "$output" "$width" "$height" "$mode"
