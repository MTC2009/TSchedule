#!/usr/bin/env python3
"""Make the shared Main Campus HS publication from the reviewed calendar, not a student roster."""

import argparse
from datetime import date
import json
from pathlib import Path


def publication(review):
    source, = (
        item for item in review["calendars"]
        if item["academic_year"] == "2026-2027" and item.get("campus") == "Main Campus"
    )
    applicable = []
    for notice in source["notices"]:
        if notice["kind"] == "division_exception":
            if "HS" in notice["no_class_divisions"]:
                applicable.append((notice, "高中部家长会 · 不上课", True))
        elif (not notice.get("divisions") or "HS" in notice["divisions"]) and (
            not notice.get("grades") or any(9 <= grade <= 12 for grade in notice["grades"])
        ):
            applicable.append((notice, notice["title_zh"], notice.get("all_students_no_class", False)))

    days = []
    for record in source["days"]:
        key = record["date"]
        printed_day = record.get("day_number")
        entries = [
            (title, no_class) for item, title, no_class in applicable
            if item["from"] <= key <= item["through"]
        ]
        # The colored or blank dates on the image do not, by themselves, declare a holiday.
        if any(no_class for _, no_class in entries):
            status = "no_class"
        elif printed_day is not None:
            status = "teaching"
        elif date.fromisoformat(key).weekday() >= 5:
            status = "weekend"
        else:
            status = "unpublished"
        row = {"date": key}
        if printed_day is not None:
            row["day"] = printed_day
        row["status"] = status
        titles = sorted(entries, key=lambda entry: not entry[1])
        row["notices"] = list(dict.fromkeys(title for title, _ in titles))
        days.append(row)

    coverage = source["coverage"]
    assert [days[0]["date"], days[-1]["date"]] == [coverage["from"], coverage["through"]]
    assert all(
        (date.fromisoformat(b["date"]) - date.fromisoformat(a["date"])).days == 1
        for a, b in zip(days, days[1:])
    )
    return {
        "campus": "main",
        "academic_year": source["academic_year"],
        "division": "HS",
        **coverage,
        "source_sha256": source["source_sha256"],
        "days": days,
    }


def render(data):
    rows = data["days"]
    head = json.dumps({k: v for k, v in data.items() if k != "days"}, indent=2)
    return head[:-2] + ',\n  "days": [\n' + ",\n".join(
        "    " + json.dumps(row, ensure_ascii=False) for row in rows
    ) + "\n  ]\n}\n"


def main():
    base = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="Write to a new file instead of checking the published resource.")
    args = parser.parse_args()
    review = base.parent / "docs" / "verification" / "school-calendar-extraction-20261120.json"
    result = render(publication(json.loads(review.read_text(encoding="utf-8"))))
    if args.output is not None:
        with args.output.open("x", encoding="utf-8") as handle:
            handle.write(result)
    elif (base / "src" / "provider" / "academic-calendar-hs-2026-2027.json").read_text(encoding="utf-8") != result:
        parser.exit(1, "The published HS calendar is different from the reviewed source.\n")


if __name__ == "__main__":
    main()
