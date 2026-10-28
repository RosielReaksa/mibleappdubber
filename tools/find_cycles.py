"""Find import cycles in the Dart sources."""
import os
import re
import sys
from collections import defaultdict

ROOT = r"D:\projectradom\mibleappdubber\dubber_app\lib"
PKG = "package:dubber_app/"

imports = defaultdict(set)
paths = {}

for dirpath, _, files in os.walk(ROOT):
    for name in files:
        if not name.endswith(".dart"):
            continue
        full = os.path.join(dirpath, name)
        rel = os.path.relpath(full, ROOT).replace("\\", "/")
        paths[rel] = full

for rel, full in paths.items():
    with open(full, "r", encoding="utf-8") as f:
        src = f.read()
    deps = set()
    for m in re.finditer(r"""^\s*import\s+['"]([^'"]+)['"]""", src, re.M):
        uri = m.group(1)
        if uri.startswith(PKG):
            deps.add(uri[len(PKG):])
        elif uri.startswith("."):
            joined = os.path.normpath(os.path.join(os.path.dirname(rel), uri))
            deps.add(joined.replace("\\", "/"))
    imports[rel] = {d for d in deps if d in paths}

WHITE, GRAY, BLACK = 0, 1, 2
color = {n: WHITE for n in paths}
stack = []
cycles = []


def dfs(node):
    color[node] = GRAY
    stack.append(node)
    for dep in sorted(imports[node]):
        if color[dep] == GRAY:
            i = stack.index(dep)
            cycles.append(stack[i:] + [dep])
        elif color[dep] == WHITE:
            dfs(dep)
    stack.pop()
    color[node] = BLACK


sys.setrecursionlimit(10000)
for node in sorted(paths):
    if color[node] == WHITE:
        dfs(node)

if cycles:
    print(f"found {len(cycles)} cycle(s):")
    for c in cycles:
        print("  " + " -> ".join(c))
else:
    print("no cycles")
