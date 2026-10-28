"""Strip embedded font data from extracted mockup screens, keeping layout/CSS."""
import glob
import os
import re

OUT = r"D:\projectradom\mibleappdubber\mockup-screens"
CLEAN = r"D:\projectradom\mibleappdubber\mockup-clean"

TITLES = [
    "Login", "Projects", "New project", "Progress", "Result",
    "Editor landscape", "Logo tool", "Editor portrait", "Loading animated",
    "Exporting", "Video ready", "Account and credits", "Templates",
    "Subtitles tool", "Trim tool", "Audio tool", "No projects yet",
    "Upload failed", "Not enough credits", "Sign up", "Forgot password",
    "Blur tool", "Tutorials", "Guide", "Quick guide 1", "Quick guide 2",
    "Quick guide 3", "Quick guide 4",
]

os.makedirs(CLEAN, exist_ok=True)
files = sorted(glob.glob(os.path.join(OUT, "*.html")))

for i, path in enumerate(files):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        doc = f.read()

    # Drop base64 @font-face payloads and <style> font blocks.
    doc = re.sub(r"data:font/[^)\"']{200,}", "data:font/REMOVED", doc)
    doc = re.sub(r"data:application/font[^)\"']{200,}", "data:font/REMOVED", doc)
    doc = re.sub(r"base64,[A-Za-z0-9+/=]{500,}", "base64,REMOVED", doc)

    title = TITLES[i] if i < len(TITLES) else f"screen-{i + 1}"
    safe = re.sub(r"[^A-Za-z0-9]+", "-", title).strip("-")
    name = f"{i + 1:02d}-{safe}.html"
    with open(os.path.join(CLEAN, name), "w", encoding="utf-8") as f:
        f.write(doc)
    print(f"{name}\t{len(doc)} bytes")
