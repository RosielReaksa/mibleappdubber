"""Reduce extracted screens to just their layout markup + non-font styles."""
import glob
import os
import re

SRC = r"D:\projectradom\mibleappdubber\mockup-clean"
OUT = r"D:\projectradom\mibleappdubber\mockup-layout"

os.makedirs(OUT, exist_ok=True)

for path in sorted(glob.glob(os.path.join(SRC, "*.html"))):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        doc = f.read()

    # Keep only the first <helmet> style block that is NOT all @font-face,
    # then the body markup. Drop the huge font-face stylesheet entirely.
    doc = re.sub(r"<style>.*?</style>", lambda m: "" if "@font-face" in m.group(0) else m.group(0), doc, flags=re.S)
    doc = re.sub(r"<script.*?</script>", "", doc, flags=re.S)
    doc = doc.replace("<x-dc>", "").replace("</x-dc>", "")
    doc = re.sub(r"<helmet>|</helmet>", "", doc)
    doc = re.sub(r"\n{3,}", "\n\n", doc)

    name = os.path.basename(path)
    with open(os.path.join(OUT, name), "w", encoding="utf-8") as f:
        f.write(doc)
    print(f"{name}\t{len(doc)}")
