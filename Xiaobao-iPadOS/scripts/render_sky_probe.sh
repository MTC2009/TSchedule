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
core=()
while IFS= read -r -d '' file; do core+=("$file"); done < <(find Sources/Core -name '*.swift' -print0)
# Seasonal artwork can still be developed explicitly, without enabling it in the app.
compiler_flags=(-O)
seasonal=()
case "$mode" in
    pair|catalog)
        # Exercise the shipping target, not unregistered work-in-progress geometry.
        while IFS= read -r file; do seasonal+=("Sources/Native/$file"); done < <(
            plutil -convert json -o - Xiaobao.xcodeproj/project.pbxproj | python3 -c '
import json, sys
objects = json.load(sys.stdin)["objects"]
target = next(o for o in objects.values() if o["isa"] == "PBXNativeTarget" and o["name"] == "Xiaobao")
phase = next(objects[i] for i in target["buildPhases"] if objects[i]["isa"] == "PBXSourcesBuildPhase")
for i in phase["files"]:
    path = objects[objects[i]["fileRef"]]["path"]
    if path.startswith("Atmosphere/Seasonal/") and path.endswith(".swift"): print(path)'
        ) ;;
    *) compiler_flags+=(-D TSCHEDULE_SEASONAL_ART); seasonal=("$sources/Seasonal/"*.swift) ;;
esac
xcrun swiftc "${compiler_flags[@]}" "${core[@]}" "$sources/SkyDetails.swift" "${seasonal[@]}" \
    "$sources/VolumetricSky.swift" "$sources/VolumetricSkyState.swift" \
    Tests/AtmospherePreview/SeasonalProbe.swift Tests/AtmospherePreview/SeasonalLightProbe.swift \
    Tests/AtmospherePreview/SeasonalSparrowProbe.swift Tests/AtmospherePreview/SeasonalImpressionProbe.swift Tests/AtmospherePreview/SeasonalFestivalProbe.swift Tests/AtmospherePreview/RenderSky.swift -o "$output/render-sky"
"$output/render-sky" "$output" "$width" "$height" "$mode"
