"""Recursively unpack nested bundler pages down to the real screen HTML."""
import base64
import gzip
import json
import os
import re

SRC = r"D:\projectradom\mibleappdubber\Dubber Mobile App Mockup.html"
OUT = r"D:\projectradom\mibleappdubber\mockup-clean"

TITLES = [
    "Login", "Projects", "New project", "Progress", "Result",
    "Editor landscape", "Logo tool", "Editor portrait", "Loading animated",
    "Exporting", "Video ready", "Account and credits", "Templates",
    "Subtitles tool", "Trim tool", "Audio tool", "No projects yet",
    "Upload failed", "Not enough credits", "Sign up", "Forgot password",
    "Blur tool", "Tutorials", "Guide", "Quick guide 1", "Quick guide 2",
    "Quick guide 3", "Quick guide 4",
]

TAG = r'<script type="__bundler/%s">(.*?)</script>'


def script_tag(doc, kind):
    m = re.search(TAG % kind, doc, re.S)
    return m.group(1) if m else None


def unpack(entry_data):
    raw = base64.b64decode(entry_data)
    try:
        raw = gzip.decompress(raw)
    except OSError:
        pass
    return raw.decode("utf-8", errors="replace")


def extract_page(doc):
    """Return the innermost real HTML for a bundler page."""
    template = script_tag(doc, "template")
    if template is None:
        return doc
    page = json.loads(template)
    # Recurse while the page is itself a bundler document.
    if '<script type="__bundler/manifest">' in page:
        return extract_page(page)
    return page


os.makedirs(OUT, exist_ok=True)

with open(SRC, "r", encoding="utf-8", errors="replace") as f:
    root = f.read()

manifest = json.loads(script_tag(root, "manifest"))
page_order = json.loads(script_tag(root, "page_order"))

for i, uid in enumerate(page_order, start=1):
    doc = unpack(manifest[uid]["data"])
    real = extract_page(doc)
    title = TITLES[i - 1] if i - 1 < len(TITLES) else f"screen-{i}"
    safe = re.sub(r"[^A-Za-z0-9]+", "-", title).strip("-")
    name = f"{i:02d}-{safe}.html"
    with open(os.path.join(OUT, name), "w", encoding="utf-8") as f:
        f.write(real)
    print(f"{name}\t{len(real)} bytes")
