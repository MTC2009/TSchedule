#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift test
find Sources/Core Sources/Native Sources/ActivityWidget -type f -name '*.swift' -print0 | xargs -0 swiftc -frontend -parse
python3 - <<'PY'
import json, plistlib, pathlib, struct, xml.etree.ElementTree as ET
root = pathlib.Path('.')
with (root / 'Config/Info.plist').open('rb') as file:
    assert plistlib.load(file)['NSSupportsLiveActivities'] is True
with (root / 'Config/LessonActivity-Info.plist').open('rb') as file:
    assert plistlib.load(file)['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension'
for path in root.glob('Resources/**/*.json'):
    json.loads(path.read_text())
# Both system surfaces and the sidebar use the same two appearance roles.
catalog = root / 'Resources/Assets.xcassets'
for name, side in [('AppIcon.appiconset', 1024), ('TScheduleMark.imageset', 96)]:
    asset = catalog / name
    images = json.loads((asset / 'Contents.json').read_text())['images']
    keys = [tuple((a['appearance'], a['value']) for a in i.get('appearances', [])) for i in images]
    assert keys.count(()) == keys.count((('luminosity', 'dark'),)) == 1, name
    assert len({(asset / i['filename']).read_bytes() for i in images}) == len(images), name
    for i in images:
        png = (asset / i['filename']).read_bytes()
        assert png[:8] == b'\x89PNG\r\n\x1a\n' and struct.unpack('>II', png[16:24]) == (side, side), name
for variant, filename in [('Light', 'tschedule-campus-light.png'), ('Dark', 'tschedule-campus-v1.png')]:
    asset = catalog / f'AppIcon{variant}.appiconset'
    images = json.loads((asset / 'Contents.json').read_text())['images']
    assert len(images) == 1 and images[0]['filename'] == filename
    assert (asset / filename).read_bytes() == (catalog / 'AppIcon.appiconset' / filename).read_bytes()
ET.parse(root / 'Xiaobao.xcodeproj/xcshareddata/xcschemes/Xiaobao.xcscheme')
print('Swift syntax, configuration and assets checked.')
PY

if command -v xcodebuild >/dev/null 2>&1; then
    xcodebuild -project Xiaobao.xcodeproj -scheme Xiaobao \
        -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath ./DerivedData CODE_SIGN_IDENTITY=- \
        CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES build
else
    printf '%s\n' 'UI build was not run: Xcode 26+ on macOS is required.'
fi
