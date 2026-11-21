"""Run the real sidebar/Metal view on a booted, isolated iPad simulator (no account)."""
import argparse
from pathlib import Path
import plistlib
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("device", help="UUID of a booted QA simulator, not a student session")
parser.add_argument("scratch", type=Path, help="dedicated reusable build directory")
args = parser.parse_args()
tests = Path(__file__).resolve().parent
root = tests.parents[1]
scratch = args.scratch.resolve()
project = scratch / "Xiaobao.xcodeproj"
original = root / project.name
bundle = "cn.xiaobao.fixture.sidebar-sky"
marker = scratch / ".sidebar-sky-fixture"
if not marker.is_file() and scratch.exists() and any(scratch.iterdir()):
    raise SystemExit("Use an empty directory or a previous sidebar fixture build")
project.mkdir(parents=True, exist_ok=True)
marker.touch(exist_ok=True)

# The temporary target uses the shipping project, shader and Swift sources.
# Its synthetic entry and unprivileged destination exist only in this test.
entry = (root / "Sources/Native/XiaobaoApp.swift").read_text()
if entry.count("@main @MainActor") != 1 or entry.count(".navigationTitle(title)") != 1:
    raise SystemExit("Application entry or screen root changed; review the fixture")
overlay = scratch / "FixtureEntry.swift"
entry = entry.replace(".navigationTitle(title)", ".modifier(SidebarFixtureRoute()).navigationTitle(title)")
overlay.write_text(entry.replace("@main @MainActor", "@MainActor") + "\n" +
                   (tests / "SidebarSkySmoke.swift").read_text())
# Run the school-only routing with a fixed in-memory student, never a live portal.
model = (root / "Sources/Native/AppModel.swift").read_text()
reader = "reader: { try await schoolReader.read($0, expected: $1) }"
if model.count(reader) != 1:
    raise SystemExit("Review the fixture's local identity injection")
model_overlay = scratch / "FixtureAppModel.swift"
model_overlay.write_text(model.replace(reader, "reader: SidebarSkySmoke.read"))
graph = plistlib.loads(subprocess.check_output(
    ["plutil", "-convert", "xml1", "-o", "-", str(original / "project.pbxproj")]))
for obj in graph["objects"].values():
    path = obj.get("path", "")
    settings = obj.get("buildSettings", {})
    if "INFOPLIST_FILE" in settings:
        settings["INFOPLIST_FILE"] = str((root / settings["INFOPLIST_FILE"]).resolve())
    if path == "XiaobaoApp.swift":
        obj.update(path=str(overlay), sourceTree="<absolute>")
    elif path == "AppModel.swift":
        obj.update(path=str(model_overlay), sourceTree="<absolute>")
    elif path in {"Sources", "README.md"} or path.startswith(("Resources/", "Config/", "Sources/", "../xiaobao-backend/")):
        obj.update(path=str((root / path).resolve()), sourceTree="<absolute>")
(project / "project.pbxproj").write_bytes(plistlib.dumps(graph))
schemes = Path("xcshareddata/xcschemes/Xiaobao.xcscheme")
(project / schemes.parent).mkdir(parents=True, exist_ok=True)
(project / schemes).write_bytes((original / schemes).read_bytes())
derived = scratch / "DerivedData"
with (scratch / "build.log").open("w") as log:
    subprocess.run(["xcodebuild", "-project", str(project), "-scheme", "Xiaobao",
                    "-configuration", "Release", "-destination", "id=" + args.device,
                    "-derivedDataPath", str(derived), "-jobs", "2", "ONLY_ACTIVE_ARCH=YES",
                    "CODE_SIGN_IDENTITY=-", "COMPILER_INDEX_STORE_ENABLE=NO",
                    "TSCHEDULE_APP_BUNDLE_IDENTIFIER=" + bundle, "build"],
                   stdout=log, stderr=subprocess.STDOUT, check=True)
app = derived / "Build/Products/Release-iphonesimulator/Xiaobao.app"
if plistlib.loads((app / "Info.plist").read_bytes())["CFBundleIdentifier"] != bundle:
    raise SystemExit("Refusing to install a non-fixture bundle")
subprocess.run(["xcrun", "simctl", "install", args.device, str(app)], check=True)
result = subprocess.run(["xcrun", "simctl", "launch", "--console", args.device, bundle],
                        capture_output=True, text=True, timeout=75)
lines = [line for line in result.stdout.splitlines() if line.startswith("SIDEBAR-SKY ")]
print("\n".join(lines) or "Fixture terminated without a result")
raise SystemExit(0 if any(line.startswith("SIDEBAR-SKY PASS:") for line in lines) else 1)
