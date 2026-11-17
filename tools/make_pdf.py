#!/usr/bin/env python3
"""Render a Markdown document to a styled A4 PDF with headless Chrome.

Usage: tools/.venv/bin/python tools/make_pdf.py REPORT.md docs/REPORT.pdf \
           --subtitle "..." --author "..." --date "17 November 2026"
The first H1 becomes the title; the first paragraph becomes the lead.
"""
import argparse
import pathlib
import subprocess
import tempfile

import markdown

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
CSS = pathlib.Path(__file__).with_name("report.css")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("source", type=pathlib.Path)
    p.add_argument("output", type=pathlib.Path)
    p.add_argument("--title")
    p.add_argument("--subtitle", default="")
    p.add_argument("--author", default="")
    p.add_argument("--date", default="")
    p.add_argument("--html", type=pathlib.Path, help="also write the intermediate HTML here")
    a = p.parse_args()

    lines = a.source.read_text().splitlines()
    title = a.title or (lines[0][2:] if lines and lines[0].startswith("# ") else a.source.stem)
    body = "\n".join(lines[1:] if lines[0].startswith("# ") else lines).strip()
    lead, rest = (body.split("\n\n", 1) + [""])[:2]
    html_body = markdown.markdown(rest, extensions=["tables", "fenced_code", "sane_lists"])
    lead_html = markdown.markdown(lead)
    page = f"""<!doctype html><html><head><meta charset="utf-8"><title>{title}</title>
<style>{CSS.read_text()}</style></head><body>
<header id="title-block-header"><h1 class="title">{title}</h1>
<p class="subtitle">{a.subtitle}</p><p class="author">{a.author}</p><p class="date">{a.date}</p></header>
{lead_html}
{html_body}
</body></html>"""
    if a.html:
        a.html.write_text(page)
    with tempfile.TemporaryDirectory() as tmp:
        html_path = pathlib.Path(tmp) / "doc.html"
        html_path.write_text(page)
        a.output.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
                        f"--print-to-pdf={a.output.resolve()}", html_path.as_uri()],
                       check=True, capture_output=True)
    print(f"wrote {a.output} ({a.output.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
