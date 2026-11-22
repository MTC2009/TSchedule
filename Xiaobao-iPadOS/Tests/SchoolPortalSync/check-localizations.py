"""Check shipping catalogs, optionally against a simulator product and Swift compiler extraction."""
import argparse
import json
from pathlib import Path
import plistlib
import re

ROOT = Path(__file__).resolve().parents[2]
LANGUAGES = {"en", "zh-Hans"}
# Literal brand names and the school's rotation code are language-neutral, not missing translations.
NEUTRAL = {"GPA", "TSchedule", "XIAOBAO", "Day %lld", "Day %lld · %@", "%@ · Day %lld"}
FORMAT = re.compile(r"%(?:(\d+)\$)?(@|lld|lf|d|%)")


def slots(text):
    result, count = {}, 0
    for position, kind in FORMAT.findall(text):
        if kind == "%":
            continue
        count += 1
        slot = int(position) if position else count
        assert result.setdefault(slot, kind) == kind, f"Conflicting argument type in {text}"
    return result


def table(name):
    source = json.loads((ROOT / "Resources" / (name + ".xcstrings")).read_text())
    assert source["sourceLanguage"] == "zh-Hans"
    rows = source["strings"]
    for key, entry in rows.items():
        local = entry["localizations"]
        assert set(local) == LANGUAGES, key
        zh, en = [local[tag]["stringUnit"] for tag in ("zh-Hans", "en")]
        assert zh["state"] == en["state"] == "translated" and zh["value"] and en["value"], key
        assert "\ufffd" not in en["value"] and not re.search(r"[\u3400-\u9fff]", en["value"]), key
        assert slots(zh["value"]) == slots(en["value"]), key
    return rows


def compiled(bundle, name, rows):
    for lang in sorted(LANGUAGES):
        path = bundle / (lang + ".lproj") / (name + ".strings")
        with path.open("rb") as f:
            values = plistlib.load(f)
        for key, row in rows.items():
            assert values.get(key) == row["localizations"][lang]["stringUnit"]["value"], (path, key)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, help="An already built Xiaobao.app")
    parser.add_argument("--derived-data", type=Path, help="Release build with SWIFT_EMIT_LOC_STRINGS=YES")
    args = parser.parse_args()
    ui, usage = table("Localizable"), table("InfoPlist")
    if args.app:
        compiled(args.app, "Localizable", ui)
        compiled(args.app, "InfoPlist", usage)
        compiled(args.app/"PlugIns"/"LessonActivityWidget.appex", "Localizable", ui)
    if args.derived_data:
        checked = set()
        # Personal-device releases and simulator releases both emit the Swift catalog.
        files = (f for sdk in ("iphoneos", "iphonesimulator") for f in args.derived_data.glob(
            f"Build/Intermediates.noindex/*/Release-{sdk}/*/Objects-normal/*/*.stringsdata"))
        for f in files:
            if f.stem in checked:
                continue
            checked.add(f.stem)
            for item in json.loads(f.read_text()).get("tables", {}).get("Localizable", []):
                key = item["key"]
                if re.search(r"[\u3400-\u9fffA-Za-z]", FORMAT.sub("", key)):
                    assert key in ui or key in NEUTRAL, f"Missing translation in {f.stem}: {key}"
        assert "LessonActivityCard" in checked and "XiaobaoApp" in checked, "Missing app/extension extraction"
    print(f"PASS: {len(ui)} interface keys and {len(usage)} permission key(s) in both languages.")


if __name__ == "__main__":
    main()
