"""Check (default) or render the two static pages from the iPad's offline policy copy."""
import argparse
from datetime import date
from html import escape
import json
from pathlib import Path

WEB = Path(__file__).resolve().parent
SOURCE = WEB.parents[2] / "Xiaobao-iPadOS/Resources/PolicyCopy.json"
PAGES = {"privacy": "terms", "terms": "privacy"}


def load_copy():
    copy = json.loads(SOURCE.read_text(encoding="utf-8"))
    date.fromisoformat(copy["revised"])
    if bool(copy["effectiveDate"]) != bool(copy["publisher"]):
        raise ValueError("Publisher and effectiveDate must be set together.")
    if copy["effectiveDate"]:
        date.fromisoformat(copy["effectiveDate"])
    if any(c.isspace() for c in copy["contact"]) or copy["contact"].count("@") != 1:
        raise ValueError("Expected one plain contact email address.")
    wording = [copy["draftNotice"]]
    for key in PAGES:
        doc = copy[key]
        if not doc["sections"]:
            raise ValueError(f"{key} has no sections")
        wording.extend([doc["title"], doc["intro"]])
        for section in doc["sections"]:
            wording.extend([section["heading"], section["body"]])
    if not all(isinstance(w.get(lang), str) and w[lang].strip() for w in wording for lang in ("zh", "en")):
        raise ValueError("A Chinese or English paragraph is missing.")
    return copy


def article(copy, key, lang):
    zh = lang == "zh"
    anchor = "zh-hans" if zh else "en"
    doc = copy[key]
    other = PAGES[key]
    title = escape(doc["title"][lang])
    address = escape(copy["contact"])
    if copy["publisher"] and copy["effectiveDate"]:
        publisher, effective = escape(copy["publisher"]), escape(copy["effectiveDate"])
        status = f"发布者：{publisher} · 生效日期：{effective}" if zh else f"Publisher: {publisher} · Effective: {effective}"
    else:
        status = escape(copy["draftNotice"][lang])
    heading, sub = ("h1", "h2") if zh else ("h2", "h3")
    parts = [
        f'<section id="{anchor}" lang="{"zh-Hans" if zh else "en"}" aria-labelledby="{lang}-title">',
        f'<{heading} id="{lang}-title" class="policy-title">TSchedule {title}</{heading}>',
        f'<p><strong>{status}</strong><br>{"最近修订：" if zh else "Last revised: "}{escape(copy["revised"])}</p>',
        f'<p>{escape(doc["intro"][lang])}</p>',
    ]
    for item in doc["sections"]:
        parts.extend([f'<{sub}>{escape(item["heading"][lang])}</{sub}>', f'<p>{escape(item["body"][lang])}</p>'])
    links = [f'<a href="../{other}/index.html#{anchor}">{escape(copy[other]["title"][lang])}</a>',
             f'<a href="../support/index.html#{anchor}">{"应用支持" if zh else "App Support"}</a>']
    if key == "privacy":
        links.append('<a href="https://open-meteo.com/en/terms">Open-Meteo</a>')
    parts.extend([f'<p>{"联系维护者：" if zh else "Contact: "}<a href="mailto:{address}">{address}</a></p>',
                  f'<nav aria-label="{"相关文档" if zh else "Related documents"}">{" ".join(links)}</nav>', '</section>'])
    return "\n".join(parts)


def page(copy, key):
    title = copy[key]["title"]
    return f'''<!doctype html>
<html lang="zh-Hans">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>TSchedule {escape(title["zh"])} · {escape(title["en"])}</title>
  <link rel="stylesheet" href="../policy.css">
</head>
<body>
  <!-- Generated from the bundled PolicyCopy.json; see ../README.md for the check. -->
  <header>
    <strong>TSchedule</strong>
    <nav aria-label="页面语言 / Languages">
      <a href="#zh-hans">简体中文</a><a href="#en" lang="en">English</a>
    </nav>
  </header>
  <main>
{article(copy, key, "zh")}
{article(copy, key, "en")}
  </main>
</body>
</html>
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--write", action="store_true", help="Update only privacy/index.html and terms/index.html.")
    mode.add_argument("--check", action="store_true", help="Check both generated files without writing (default).")
    args = parser.parse_args()
    copy = load_copy()
    stale = []
    for key in PAGES:
        target = WEB / key / "index.html"
        html = page(copy, key)
        if args.write:
            target.parent.mkdir(exist_ok=True)
            target.write_text(html, encoding="utf-8")
        elif not target.is_file() or target.read_text(encoding="utf-8") != html:
            stale.append(key)
    if stale:
        raise SystemExit(f"Pages out of sync: {', '.join(stale)}. Run render_policies.py --write.")
    print("Updated both policy pages." if args.write else "Both policy pages match the bundled copy.")


if __name__ == "__main__":
    main()
