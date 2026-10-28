#!/usr/bin/env python3
"""Dubber demo server — a fake backend for the mobile app.

Implements the API from the build spec with in-memory data and simulated
dubbing jobs. No dependencies: Python standard library only.

    python server.py --port 8080

Then point the app at it. On the Android emulator, the host machine is
10.0.2.2, so use:

    flutter run --dart-define=API_BASE=http://10.0.2.2:8080/v1

Demo account: demo@dubber.app / password123
"""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
import re
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
MEDIA_DIR = os.path.join(HERE, "media")
UPLOAD_DIR = os.path.join(HERE, "uploads")

# Simulated job pace: total seconds for a dubbing job to reach 100%.
JOB_SECONDS = 24
EXPORT_SECONDS = 10

# Queue rules, mirroring the app's queue_rules.dart.
MAX_QUEUE_PER_USER = 20
MAX_FILES_PER_ADD = 10
CREDITS_PER_VIDEO = 12

STEPS = ["upload", "transcribe", "translate", "generate_voice", "mix_export"]
STEP_LABELS = {
    "upload": "Upload",
    "transcribe": "Transcribe",
    "translate": "Translate",
    "generate_voice": "Generate voice",
    "mix_export": "Mix and export",
}

LANGUAGES = [
    {"code": "en", "name": "English"},
    {"code": "km", "name": "Khmer"},
    {"code": "es", "name": "Spanish"},
    {"code": "th", "name": "Thai"},
    {"code": "fr", "name": "French"},
    {"code": "ja", "name": "Japanese"},
    {"code": "vi", "name": "Vietnamese"},
    {"code": "pt", "name": "Portuguese"},
    {"code": "de", "name": "German"},
    {"code": "ko", "name": "Korean"},
]

VOICES = [
    {"id": "female", "name": "Natural female", "gender": "female"},
    {"id": "male", "name": "Natural male", "gender": "male"},
]

TEMPLATES = [
    {
        "id": "tpl_news",
        "name": "News",
        "description": "For reports, updates and explainers.",
        "settings": {
            "format": "landscape",
            "subtitles": {"show": True, "style": "box"},
            "mix": {"dubbed_voice": 100, "original_voice": 0, "music": 80},
            "fit": {"mode": "blur", "blur_strength": 60},
            "logo_position": "bottom_left",
        },
    },
    {
        "id": "tpl_short",
        "name": "Short video",
        "description": "For Reels, Shorts and TikTok.",
        "settings": {
            "format": "portrait",
            "subtitles": {"show": True, "style": "bold"},
            "mix": {"dubbed_voice": 100, "original_voice": 15, "music": 80},
            "fit": {"mode": "blur", "blur_strength": 60},
            "logo_position": "top_right",
        },
    },
    {
        "id": "tpl_tutorial",
        "name": "Tutorial",
        "description": "For lessons and how-to videos.",
        "settings": {
            "format": "landscape",
            "subtitles": {"show": True, "style": "classic"},
            "mix": {"dubbed_voice": 100, "original_voice": 25, "music": 60},
            "fit": {"mode": "bars", "blur_strength": 0},
            "logo_position": "top_left",
        },
    },
    {
        "id": "tpl_business",
        "name": "Business ad",
        "description": "For promos and product spots.",
        "settings": {
            "format": "landscape",
            "subtitles": {"show": False, "style": "classic"},
            "mix": {"dubbed_voice": 100, "original_voice": 0, "music": 90},
            "fit": {"mode": "blur", "blur_strength": 50},
            "logo_position": "top_right",
        },
    },
]

CREDIT_PACKS = [
    {"id": "pack_50", "credits": 50, "price": "5.00", "currency": "$"},
    {"id": "pack_150", "credits": 150, "price": "12.00", "currency": "$"},
    {"id": "pack_500", "credits": 500, "price": "35.00", "currency": "$"},
]

TUTORIALS = [
    {
        "id": "g1",
        "title": "Upload your first video",
        "steps": ["Open New project", "Tap Choose video or audio", "Pick a file under 2 GB", "Tap Start dubbing"],
    },
    {
        "id": "g2",
        "title": "Pick a language and voice",
        "steps": ["Choose From and To", "Pick a voice", "Or use Auto-detect", "Tap Start dubbing"],
    },
    {
        "id": "g3",
        "title": "Add text and a logo",
        "steps": ["Open the editor", "Tap Text", "Type and drag", "Tap Logo and pick a corner"],
    },
    {
        "id": "g4",
        "title": "Blur an old subtitle",
        "steps": ["Open the editor", "Tap Blur", "Choose Bottom", "Raise Thickness"],
    },
    {
        "id": "g5",
        "title": "Balance the audio mix",
        "steps": ["Open the editor", "Tap Audio", "Pick a preset", "Fine-tune the sliders"],
    },
    {
        "id": "g6",
        "title": "Export and share",
        "steps": ["Tap Export", "Wait for the render", "Download or Share"],
    },
]

# ── State ────────────────────────────────────────────────────────────────────

_lock = threading.Lock()
USERS: dict[str, dict] = {}
TOKENS: dict[str, str] = {}          # access token -> email
REFRESH: dict[str, str] = {}         # refresh token -> email
PROJECTS: dict[str, dict] = {}       # project id -> project
JOBS: dict[str, dict] = {}           # job id -> job
EXPORTS: dict[str, dict] = {}        # export id -> export
UPLOADS: dict[str, dict] = {}        # upload id -> upload
LOGOS: dict[str, dict] = {}          # logo id -> logo
STYLES: dict[str, dict] = {}         # style id -> style
PRESETS: dict[str, dict] = {}        # preset id -> preset
TUTORIAL_PROGRESS: dict[str, set] = {}

# Set by `X-Fail-Next: 1` on a request: that video fails partway through, so
# the Failed state and Retry can be seen without a real broken file.
FAIL_NEXT = False


def seed() -> None:
    """Create the demo account and two finished projects."""
    email = "demo@dubber.app"
    USERS[email] = {"name": "Demo User", "email": email, "credits": 120}

    for pid, title, status, src, tgt in [
        ("p_demo1", "Product demo.mp4", "done", "en", "km"),
        ("p_demo2", "Travel vlog.mp4", "done", "en", "es"),
    ]:
        PROJECTS[pid] = {
            "id": pid,
            "title": title,
            "status": status,
            "percent": 100,
            "step": "mix_export",
            "source_language": src,
            "target_language": tgt,
            "format": "landscape",
            "mix": {"dubbed_voice": 100, "original_voice": 15, "music": 80},
            "voice": "female",
            "dubbed_url": f"/media/dubbed.mp4",
            "original_url": f"/media/original.mp4",
            "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "owner": email,
            "job_id": None,
            "credits": None,
            "position": None,
            "started_at": None,
        }

    now_t = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    LOGOS["l_demo1"] = {
        "id": "l_demo1",
        "name": "Acme Brand",
        "url": "/media/logo.png",
        "owner": email,
        "created_at": now_t,
    }
    STYLES["s_demo1"] = {
        "id": "s_demo1",
        "name": "Bold subtitle",
        "kind": "subtitle",
        "size": 55,
        "color": "#FFFFFF",
        "subtitle_style": "bold",
        "owner": email,
        "created_at": now_t,
    }
    STYLES["s_demo2"] = {
        "id": "s_demo2",
        "name": "Yellow headline",
        "kind": "text",
        "size": 60,
        "color": "#FFD700",
        "subtitle_style": "classic",
        "owner": email,
        "created_at": now_t,
    }
    PRESETS["pr_demo1"] = {
        "id": "pr_demo1",
        "name": "My Shorts Preset",
        "description": "Your preset",
        "settings": {
            "format": "portrait",
            "subtitles": {"show": True, "style": "bold"},
            "mix": {"dubbed_voice": 100, "original_voice": 0, "music": 75},
            "fit": {"mode": "blur", "blur_strength": 60},
            "logo_position": "top_right",
        },
        "owner": email,
        "created_at": now_t,
    }


# ── Queue ────────────────────────────────────────────────────────────────────


def owner_projects(email: str) -> list[dict]:
    """Every project owned by [email], oldest first."""
    items = [p for p in PROJECTS.values() if p.get("owner") == email]
    items.sort(key=lambda p: p.get("created_at") or "")
    return items


def is_active(project: dict) -> bool:
    return project.get("status") in ("queued", "uploading", "processing")


def queue_of(email: str) -> tuple[dict | None, list[dict], list[dict]]:
    """The user's now-dubbing job, the waiting list, and failed jobs."""
    items = owner_projects(email)
    active = [p for p in items if is_active(p)]
    active.sort(key=lambda p: (p.get("position") is None, p.get("position") or 0))

    now = next((p for p in active if p.get("status") in ("processing", "uploading")), None)
    waiting = [p for p in active if p is not now]
    for i, p in enumerate(waiting, start=1):
        p["position"] = i
    if now is not None:
        now["position"] = None

    failed = [p for p in items if p.get("status") == "failed"]
    return now, waiting, failed


def advance_queue(email: str) -> None:
    """Start the next waiting job when nothing is dubbing."""
    now, waiting, _ = queue_of(email)
    if now is not None or not waiting:
        return
    nxt = waiting[0]
    nxt["status"] = "processing"
    nxt["percent"] = 0
    nxt["step"] = "upload"
    nxt["position"] = None
    nxt["started_at"] = now_iso()
    job_id = nxt.get("job_id")
    # A fresh job clock: a waiting job's timer must not count the wait.
    previous = JOBS.get(job_id) or {}
    JOBS[job_id] = {
        "id": job_id,
        "project_id": nxt["id"],
        "status": "processing",
        "percent": 0,
        "step": "upload",
        "started": time.time(),
        # A failure injected when the video was added survives the wait.
        "fail": previous.get("fail", False),
    }


# ── Helpers ──────────────────────────────────────────────────────────────────


def now_iso() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def step_for(percent: int) -> str:
    idx = min(int(percent / 20), len(STEPS) - 1)
    return STEPS[idx]


def advance_jobs() -> None:
    """Move every running job forward based on elapsed wall time.

    Only the job at the head of each user's queue runs; when it finishes the
    next waiting job starts, so videos dub one after another.
    """
    now = time.time()
    for job in JOBS.values():
        if job["status"] in ("done", "failed"):
            continue
        project = PROJECTS.get(job["project_id"])
        if project is None:
            continue
        # A job that is still waiting for its turn does not move.
        if project.get("position") is not None:
            continue
        elapsed = now - job["started"]
        pct = min(100, int(elapsed / JOB_SECONDS * 100))

        # Failure injection: `fail` on the job, or X-Fail-Next on an add.
        if job.get("fail") and pct >= 40:
            job["status"] = "failed"
            project["status"] = "failed"
            project["position"] = None
            project["reason"] = "unsupported_file"
            project["credits"] = 0  # already refunded below
            user = USERS.get(project.get("owner"))
            if user is not None:
                user["credits"] += CREDITS_PER_VIDEO
            advance_queue(project["owner"])
            continue

        job["percent"] = pct
        if pct >= 100:
            job["status"] = "done"
            job["step"] = "mix_export"
            project["status"] = "done"
            project["percent"] = 100
            project["step"] = "mix_export"
            project["position"] = None
            project["dubbed_url"] = "/media/dubbed.mp4"
            project["original_url"] = "/media/original.mp4"
            advance_queue(project["owner"])
        else:
            job["status"] = "processing"
            job["step"] = step_for(pct)
            project["status"] = "processing"
            project["percent"] = pct
            project["step"] = job["step"]


def advance_exports() -> None:
    now = time.time()
    for export in EXPORTS.values():
        if export["status"] in ("done", "failed"):
            continue
        elapsed = now - export["started"]
        pct = min(100, int(elapsed / EXPORT_SECONDS * 100))
        export["percent"] = pct
        if pct >= 100:
            export["status"] = "done"
            export["download_url"] = "/media/dubbed.mp4"
        else:
            export["status"] = "processing"


def public_project(project: dict) -> dict:
    """Strip internal fields and make media URLs absolute."""
    out = {k: v for k, v in project.items() if k not in ("owner",)}
    return out


class Handler(BaseHTTPRequestHandler):
    server_version = "DubberDemo/1.0"

    # ── Plumbing ────────────────────────────────────────────────────────────

    def log_message(self, fmt: str, *args) -> None:
        print(f"  {self.command:6} {self.path.split('?')[0]:45} {fmt % args}", flush=True)

    def _cors(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS")
        self.send_header(
            "Access-Control-Allow-Headers",
            "Authorization,Content-Type,Idempotency-Key,X-Fail-Next",
        )

    def send_json(self, status: int, payload) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self._cors()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_error_json(self, status: int, code: str, message: str) -> None:
        self.send_json(status, {"code": code, "message": message})

    def read_json(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return {}
        try:
            return json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            return {}

    def current_user(self) -> dict | None:
        header = self.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            return None
        email = TOKENS.get(header[7:])
        return USERS.get(email) if email else None

    def require_user(self) -> dict | None:
        user = self.current_user()
        if user is None:
            self.send_error_json(401, "unauthorized", "Your session has expired. Please log in again.")
        return user

    def serve_file(self, path: str, content_type: str | None = None) -> None:
        if not os.path.isfile(path):
            self.send_error_json(404, "not_found", "File not found.")
            return
        size = os.path.getsize(path)
        ctype = content_type or mimetypes.guess_type(path)[0] or "application/octet-stream"

        # Range support so the video player can seek.
        start, end = 0, size - 1
        partial = False
        rng = self.headers.get("Range")
        if rng:
            m = re.match(r"bytes=(\d*)-(\d*)", rng)
            if m and (m.group(1) or m.group(2)):
                if m.group(1):
                    start = int(m.group(1))
                    end = int(m.group(2)) if m.group(2) else size - 1
                else:  # suffix form: bytes=-500
                    start = max(0, size - int(m.group(2)))
                end = min(end, size - 1)
                if start > end or start >= size:
                    self.send_response(416)
                    self.send_header("Content-Range", f"bytes */{size}")
                    self._cors()
                    self.end_headers()
                    return
                partial = True

        length = end - start + 1
        self.send_response(206 if partial else 200)
        self._cors()
        self.send_header("Content-Type", ctype)
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(length))
        if partial:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()

        with open(path, "rb") as f:
            f.seek(start)
            remaining = length
            while remaining > 0:
                chunk = f.read(min(64 * 1024, remaining))
                if not chunk:
                    break
                self.wfile.write(chunk)
                remaining -= len(chunk)

    # ── Routing ─────────────────────────────────────────────────────────────

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self) -> None:
        self.route("GET")

    def do_POST(self) -> None:
        self.route("POST")

    def do_PUT(self) -> None:
        self.route("PUT")

    def do_DELETE(self) -> None:
        self.route("DELETE")

    def route(self, method: str) -> None:
        path = urlparse(self.path).path
        with _lock:
            advance_jobs()
            advance_exports()
        try:
            if path.startswith("/media/"):
                self.serve_file(os.path.join(MEDIA_DIR, os.path.basename(path)))
                return
            if path.startswith("/uploads/") and path.endswith("/parts/"):
                pass
            self.dispatch(method, path)
        except BrokenPipeError:
            pass
        except Exception as exc:  # keep the demo server alive
            print(f"  !! {type(exc).__name__}: {exc}", flush=True)
            try:
                self.send_error_json(500, "server_error", "The demo server hit an error.")
            except Exception:
                pass

    def dispatch(self, method: str, path: str) -> None:
        # Normalise /v1 prefix
        if path.startswith("/v1"):
            path = path[3:]
        path = path.rstrip("/") or "/"

        # ── Public ──────────────────────────────────────────────────────────
        if method == "GET" and path == "/health":
            return self.send_json(200, {"ok": True, "time": now_iso()})

        if method == "POST" and path == "/auth/login":
            return self.login()
        if method == "POST" and path == "/auth/register":
            return self.register()
        if method == "POST" and path == "/auth/forgot-password":
            return self.send_json(200, {"ok": True})
        if method == "POST" and path == "/auth/refresh":
            return self.refresh()

        # ── Everything below needs a token ──────────────────────────────────
        user = self.require_user()
        if user is None:
            return

        if method == "GET" and path == "/me":
            return self.send_json(200, {
                "name": user["name"],
                "email": user["email"],
                "credits": user["credits"],
            })

        if method == "GET" and path == "/languages":
            return self.send_json(200, LANGUAGES)
        if method == "GET" and path == "/voices":
            return self.send_json(200, VOICES)
        if method == "GET" and path == "/templates":
            return self.send_json(200, TEMPLATES)
        if method == "GET" and path == "/tutorials":
            done = TUTORIAL_PROGRESS.get(user["email"], set())
            groups = [{"title": "Getting started", "guides": []},
                      {"title": "Editing", "guides": []},
                      {"title": "Sound and export", "guides": []}]
            for i, t in enumerate(TUTORIALS):
                groups[min(i // 2, 2)]["guides"].append({**t, "done": t["id"] in done})
            return self.send_json(200, {"groups": groups})

        if method == "POST" and re.fullmatch(r"/tutorials/[^/]+/progress", path):
            tid = path.split("/")[2]
            TUTORIAL_PROGRESS.setdefault(user["email"], set()).add(tid)
            return self.send_json(200, {"ok": True})

        if method == "GET" and path == "/credits":
            return self.send_json(200, {"balance": user["credits"], "packs": CREDIT_PACKS})

        if method == "GET" and path == "/credits/history":
            return self.send_json(200, {"items": [
                {"date": now_iso(), "description": "Dubbing · Product demo.mp4", "credits": -12},
                {"date": now_iso(), "description": "Purchase · 150 credits", "credits": 150},
            ]})

        if method == "POST" and path == "/credits/purchase":
            body = self.read_json()
            pack = next((p for p in CREDIT_PACKS if p["id"] == body.get("pack_id")), None)
            if pack is None:
                return self.send_error_json(400, "bad_pack", "Unknown credit pack.")
            user["credits"] += pack["credits"]
            return self.send_json(200, {"balance": user["credits"]})

        # ── Projects ────────────────────────────────────────────────────────
        if method == "GET" and path == "/projects":
            with _lock:
                advance_jobs()
                items = [public_project(p) for p in owner_projects(user["email"])]
            items.sort(key=lambda p: p.get("created_at") or "", reverse=True)
            return self.send_json(200, items)

        if method == "POST" and path == "/projects/estimate":
            return self.send_json(200, {"credits": CREDITS_PER_VIDEO})

        if method == "POST" and path == "/projects":
            return self.create_project(user)

        # ── Queue ───────────────────────────────────────────────────────────
        if method == "GET" and path == "/queue":
            with _lock:
                advance_jobs()
                now, waiting, failed = queue_of(user["email"])
                slots = MAX_QUEUE_PER_USER - (0 if now is None else 1) - len(waiting)
                return self.send_json(200, {
                    "now_dubbing": public_project(now) if now else None,
                    "up_next": [public_project(p) for p in waiting],
                    "failed": [public_project(p) for p in failed],
                    "slots_left": max(0, slots),
                })

        if method == "GET" and path == "/queue/active":
            with _lock:
                advance_jobs()
                now, waiting, _ = queue_of(user["email"])
                head = now or (waiting[0] if waiting else None)
            return self.send_json(200, {
                "project": public_project(head) if head else None,
            })

        if method == "POST" and path == "/queue/items":
            return self.add_queue_items(user)

        if method == "PUT" and path == "/queue/order":
            return self.reorder_queue(user)

        m = re.fullmatch(r"/queue/items/([^/]+)", path)
        if m and method == "DELETE":
            return self.remove_queue_item(user, m.group(1))

        m = re.fullmatch(r"/queue/items/([^/]+)/move", path)
        if m and method == "POST":
            return self.move_queue_item(user, m.group(1))

        m = re.fullmatch(r"/queue/items/([^/]+)/retry", path)
        if m and method == "POST":
            return self.retry_queue_item(user, m.group(1))

        m = re.fullmatch(r"/projects/([^/]+)", path)
        if m:
            project = PROJECTS.get(m.group(1))
            if project is None or project.get("owner") != user["email"]:
                return self.send_error_json(404, "not_found", "Project not found.")
            if method == "GET":
                return self.send_json(200, public_project(project))
            if method == "DELETE":
                PROJECTS.pop(project["id"], None)
                return self.send_json(200, {"ok": True})

        m = re.fullmatch(r"/projects/([^/]+)/mix", path)
        if m and method == "PUT":
            project = PROJECTS.get(m.group(1))
            if project is None:
                return self.send_error_json(404, "not_found", "Project not found.")
            body = self.read_json()
            project["mix"] = body.get("mix", project.get("mix"))
            return self.send_json(200, {"ok": True, "mix": project["mix"]})

        m = re.fullmatch(r"/projects/([^/]+)/exports", path)
        if m and method == "POST":
            project = PROJECTS.get(m.group(1))
            if project is None:
                return self.send_error_json(404, "not_found", "Project not found.")
            export_id = "exp_" + uuid.uuid4().hex[:10]
            EXPORTS[export_id] = {
                "id": export_id,
                "project_id": project["id"],
                "status": "processing",
                "percent": 0,
                "started": time.time(),
                "download_url": None,
                "settings": self.read_json(),
            }
            return self.send_json(200, {"id": export_id, "status": "processing", "percent": 0})

        m = re.fullmatch(r"/exports/([^/]+)", path)
        if m and method == "GET":
            export = EXPORTS.get(m.group(1))
            if export is None:
                return self.send_error_json(404, "not_found", "Export not found.")
            return self.send_json(200, {
                "id": export["id"],
                "status": export["status"],
                "percent": export["percent"],
                "download_url": export["download_url"],
            })

        # ── Jobs ────────────────────────────────────────────────────────────
        m = re.fullmatch(r"/jobs/([^/]+)", path)
        if m and method == "GET":
            job = JOBS.get(m.group(1))
            if job is None:
                return self.send_error_json(404, "not_found", "Job not found.")
            return self.send_json(200, {
                "id": job["id"],
                "status": job["status"],
                "step": job["step"],
                "percent": job["percent"],
                "steps": STEPS,
            })

        # ── Uploads (chunked) ───────────────────────────────────────────────
        if method == "POST" and path == "/uploads":
            body = self.read_json()
            upload_id = "up_" + uuid.uuid4().hex[:10]
            UPLOADS[upload_id] = {
                "id": upload_id,
                "file_name": body.get("file_name", "upload.mp4"),
                "size": body.get("size", 0),
                "received": 0,
                "owner": user["email"],
                "path": os.path.join(UPLOAD_DIR, upload_id + ".bin"),
            }
            part_size = 8 * 1024 * 1024
            parts = max(1, -(-int(body.get("size", 0)) // part_size))
            return self.send_json(200, {
                "id": upload_id, "part_size": part_size, "parts": parts,
            })

        m = re.fullmatch(r"/uploads/([^/]+)/parts/(\d+)", path)
        if m and method == "PUT":
            upload = UPLOADS.get(m.group(1))
            if upload is None:
                return self.send_error_json(404, "not_found", "Upload not found.")
            length = int(self.headers.get("Content-Length") or 0)
            data = self.rfile.read(length)
            with open(upload["path"], "ab") as f:
                f.write(data)
            upload["received"] += len(data)
            return self.send_json(200, {"ok": True, "received": upload["received"]})

        m = re.fullmatch(r"/uploads/([^/]+)/complete", path)
        if m and method == "POST":
            upload = UPLOADS.get(m.group(1))
            if upload is None:
                return self.send_error_json(404, "not_found", "Upload not found.")
            upload["complete"] = True
            return self.send_json(200, {"upload_id": upload["id"]})

        # ── Library: Logos ──────────────────────────────────────────────────
        if method == "GET" and path == "/assets/logos":
            items = [l for l in LOGOS.values() if l.get("owner") == user["email"]]
            items.sort(key=lambda x: x.get("created_at") or "", reverse=True)
            return self.send_json(200, items)

        if method == "POST" and path == "/assets/logos":
            body = self.read_json()
            logo_id = "logo_" + uuid.uuid4().hex[:10]
            name = (body.get("name") or "Logo").strip()
            url = body.get("url") or "/media/logo.png"
            row = {
                "id": logo_id,
                "name": name,
                "url": url,
                "owner": user["email"],
                "created_at": now_iso(),
            }
            LOGOS[logo_id] = row
            return self.send_json(201, row)

        m = re.fullmatch(r"/assets/logos/([^/]+)", path)
        if m:
            lid = m.group(1)
            row = LOGOS.get(lid)
            if row is None or row.get("owner") != user["email"]:
                return self.send_error_json(404, "not_found", "Logo not found.")
            if method == "GET":
                return self.send_json(200, row)
            if method == "PUT":
                body = self.read_json()
                if "name" in body:
                    row["name"] = body["name"]
                if "url" in body:
                    row["url"] = body["url"]
                return self.send_json(200, row)
            if method == "DELETE":
                LOGOS.pop(lid, None)
                return self.send_json(200, {"ok": True})

        # ── Library: Styles ─────────────────────────────────────────────────
        if method == "GET" and path == "/styles":
            items = [s for s in STYLES.values() if s.get("owner") == user["email"]]
            items.sort(key=lambda x: x.get("created_at") or "", reverse=True)
            return self.send_json(200, items)

        if method == "POST" and path == "/styles":
            body = self.read_json()
            style_id = "sty_" + uuid.uuid4().hex[:10]
            name = (body.get("name") or "Style").strip()
            kind = body.get("kind") or ("subtitle" if "subtitle" in name.lower() else "text")
            row = {
                "id": style_id,
                "name": name,
                "kind": kind,
                "size": int(body.get("size") or (55 if kind == "subtitle" else 60)),
                "color": body.get("color") or "#FFFFFF",
                "subtitle_style": body.get("subtitle_style") or "classic",
                "owner": user["email"],
                "created_at": now_iso(),
            }
            STYLES[style_id] = row
            return self.send_json(201, row)

        m = re.fullmatch(r"/styles/([^/]+)", path)
        if m:
            sid = m.group(1)
            row = STYLES.get(sid)
            if row is None or row.get("owner") != user["email"]:
                return self.send_error_json(404, "not_found", "Style not found.")
            if method == "GET":
                return self.send_json(200, row)
            if method == "PUT":
                body = self.read_json()
                if "name" in body:
                    row["name"] = body["name"]
                if "size" in body:
                    row["size"] = int(body["size"])
                if "color" in body:
                    row["color"] = body["color"]
                if "subtitle_style" in body:
                    row["subtitle_style"] = body["subtitle_style"]
                return self.send_json(200, row)
            if method == "DELETE":
                STYLES.pop(sid, None)
                return self.send_json(200, {"ok": True})

        # ── Library: Presets ────────────────────────────────────────────────
        if method == "GET" and path == "/presets":
            items = [p for p in PRESETS.values() if p.get("owner") == user["email"]]
            items.sort(key=lambda x: x.get("created_at") or "", reverse=True)
            return self.send_json(200, items)

        if method == "POST" and path == "/presets":
            body = self.read_json()
            preset_id = "pre_" + uuid.uuid4().hex[:10]
            name = (body.get("name") or "Preset").strip()
            row = {
                "id": preset_id,
                "name": name,
                "description": body.get("description") or "Your preset",
                "settings": body.get("settings") or {},
                "owner": user["email"],
                "created_at": now_iso(),
            }
            PRESETS[preset_id] = row
            return self.send_json(201, row)

        m = re.fullmatch(r"/presets/([^/]+)", path)
        if m:
            pid = m.group(1)
            row = PRESETS.get(pid)
            if row is None or row.get("owner") != user["email"]:
                return self.send_error_json(404, "not_found", "Preset not found.")
            if method == "GET":
                return self.send_json(200, row)
            if method == "PUT":
                body = self.read_json()
                if "name" in body:
                    row["name"] = body["name"]
                if "settings" in body:
                    row["settings"] = body["settings"]
                return self.send_json(200, row)
            if method == "DELETE":
                PRESETS.pop(pid, None)
                return self.send_json(200, {"ok": True})

        return self.send_error_json(404, "not_found", f"No route for {method} {path}")

    # ── Handlers ────────────────────────────────────────────────────────────

    def login(self) -> None:
        body = self.read_json()
        email = (body.get("email") or "").strip().lower()
        password = body.get("password") or ""
        user = USERS.get(email)
        if user is None or password != "password123":
            return self.send_error_json(401, "invalid_credentials", "Wrong email or password.")
        return self.send_json(200, self.issue_tokens(email))

    def register(self) -> None:
        body = self.read_json()
        email = (body.get("email") or "").strip().lower()
        if not email:
            return self.send_error_json(400, "bad_email", "Enter a valid email.")
        if email in USERS:
            return self.send_error_json(409, "email_taken", "That email is already registered.")
        USERS[email] = {
            "name": body.get("name") or "New User",
            "email": email,
            "credits": 30,
        }
        return self.send_json(200, self.issue_tokens(email))

    def refresh(self) -> None:
        body = self.read_json()
        email = REFRESH.get(body.get("refresh_token") or "")
        if email is None:
            return self.send_error_json(401, "unauthorized", "Session expired.")
        return self.send_json(200, self.issue_tokens(email))

    def issue_tokens(self, email: str) -> dict:
        access = "at_" + uuid.uuid4().hex
        refresh = "rt_" + uuid.uuid4().hex
        TOKENS[access] = email
        REFRESH[refresh] = email
        return {"access_token": access, "refresh_token": refresh}

    def add_queue_items(self, user: dict) -> None:
        """Add many uploaded videos at once, in order, checking each one."""
        global FAIL_NEXT
        body = self.read_json()
        items = body.get("items") or []
        if self.headers.get("X-Fail-Next") == "1":
            FAIL_NEXT = True
        if len(items) > MAX_FILES_PER_ADD:
            return self.send_error_json(
                400, "too_many_files",
                f"You can add up to {MAX_FILES_PER_ADD} videos at once.",
            )

        added: list[dict] = []
        rejected: list[dict] = []
        stopped: str | None = None
        reserved = 0

        with _lock:
            advance_jobs()
            now, waiting, _ = queue_of(user["email"])
            slots = MAX_QUEUE_PER_USER - (0 if now is None else 1) - len(waiting)

            for item in items:
                name = item.get("file_name") or "video.mp4"

                if slots <= 0:
                    stopped = stopped or "max_queue_per_user"
                    rejected.append({
                        "file_name": name,
                        "code": "max_queue_per_user",
                        "message": "Your queue is full.",
                    })
                    continue

                if user["credits"] < CREDITS_PER_VIDEO:
                    stopped = stopped or "not_enough_credits"
                    rejected.append({
                        "file_name": name,
                        "code": "not_enough_credits",
                        "message": f"You need {CREDITS_PER_VIDEO} credits.",
                    })
                    continue

                upload = UPLOADS.get(item.get("upload_id") or "")
                if upload is None or not upload.get("complete"):
                    rejected.append({
                        "file_name": name,
                        "code": "upload_missing",
                        "message": "This file was not fully uploaded.",
                    })
                    continue

                user["credits"] -= CREDITS_PER_VIDEO
                reserved += CREDITS_PER_VIDEO
                slots -= 1
                added.append(self._make_project(user, item, upload))

            # The first added video starts at once if nothing is running.
            advance_queue(user["email"])
            now, waiting, _ = queue_of(user["email"])

        return self.send_json(200, {
            "now_dubbing": public_project(now) if now else None,
            "up_next": [public_project(p) for p in waiting],
            "rejected": rejected,
            "reserved_credits": reserved,
            "balance": user["credits"],
            "stopped_reason": stopped,
        })

    def _make_project(self, user: dict, item: dict, upload: dict) -> dict:
        global FAIL_NEXT
        project_id = "p_" + uuid.uuid4().hex[:10]
        job_id = "job_" + uuid.uuid4().hex[:10]
        fail = FAIL_NEXT
        FAIL_NEXT = False
        project = {
            "id": project_id,
            "title": upload.get("file_name") or item.get("file_name") or "video.mp4",
            "status": "queued",
            "percent": 0,
            "step": None,
            "source_language": item.get("source_language", "en"),
            "target_language": item.get("target_language", "km"),
            "format": item.get("format", "landscape"),
            "mix": item.get("mix", {"dubbed_voice": 100, "original_voice": 15, "music": 80}),
            "voice": item.get("voice", "female"),
            "dubbed_url": None,
            "original_url": None,
            "created_at": now_iso(),
            "owner": user["email"],
            "job_id": job_id,
            "credits": CREDITS_PER_VIDEO,
            "position": None,
            "started_at": None,
        }
        PROJECTS[project_id] = project
        JOBS[job_id] = {
            "id": job_id,
            "project_id": project_id,
            "status": "queued",
            "percent": 0,
            "step": None,
            "started": time.time(),
            "fail": fail,
        }
        return project

    def _own_project(self, user: dict, project_id: str) -> dict | None:
        project = PROJECTS.get(project_id)
        if project is None or project.get("owner") != user["email"]:
            return None
        return project

    def remove_queue_item(self, user: dict, project_id: str) -> None:
        with _lock:
            project = self._own_project(user, project_id)
            if project is None:
                return self.send_error_json(404, "not_found", "Item not found.")
            if not is_active(project) and project.get("status") != "failed":
                return self.send_error_json(
                    409, "not_in_queue", "This video is not in the queue."
                )
            # Credits come back when a job is removed or cancelled. A failed
            # job already had its credits returned, so it has none left to
            # refund; removing it just dismisses the row.
            refund = project.get("credits") or 0
            user["credits"] += refund
            was_head = project.get("status") in ("processing", "uploading")
            PROJECTS.pop(project_id, None)
            job_id = project.get("job_id")
            if job_id:
                JOBS.pop(job_id, None)
            if was_head:
                advance_queue(user["email"])
        return self.send_json(200, {"ok": True, "balance": user["credits"]})

    def move_queue_item(self, user: dict, project_id: str) -> None:
        with _lock:
            project = self._own_project(user, project_id)
            if project is None:
                return self.send_error_json(404, "not_found", "Item not found.")
            now, waiting, _ = queue_of(user["email"])
            if project not in waiting:
                return self.send_error_json(
                    409, "not_waiting", "Only waiting videos can be moved."
                )
            waiting.remove(project)
            waiting.insert(0, project)
            for i, p in enumerate(waiting, start=1):
                p["position"] = i
        return self.send_json(200, {"ok": True})

    def reorder_queue(self, user: dict) -> None:
        body = self.read_json()
        order = body.get("order") or []
        with _lock:
            now, waiting, _ = queue_of(user["email"])
            by_id = {p["id"]: p for p in waiting}
            if set(by_id) != {pid for pid in order if pid in by_id}:
                return self.send_error_json(
                    409, "stale_order",
                    "The queue changed. Please look again.",
                )
            reordered = [by_id[pid] for pid in order if pid in by_id]
            # Anything the client left out keeps its place at the end.
            reordered += [p for p in waiting if p["id"] not in set(order)]
            for i, p in enumerate(reordered, start=1):
                p["position"] = i
        return self.send_json(200, {"ok": True})

    def retry_queue_item(self, user: dict, project_id: str) -> None:
        with _lock:
            project = self._own_project(user, project_id)
            if project is None:
                return self.send_error_json(404, "not_found", "Item not found.")
            if project.get("status") != "failed":
                return self.send_error_json(
                    409, "not_failed", "Only failed videos can be retried."
                )
            if user["credits"] < CREDITS_PER_VIDEO:
                return self.send_error_json(
                    402, "not_enough_credits",
                    f"You need {CREDITS_PER_VIDEO} credits.",
                )
            user["credits"] -= CREDITS_PER_VIDEO
            project["credits"] = CREDITS_PER_VIDEO
            project["status"] = "queued"
            project["percent"] = 0
            project["reason"] = None
            job_id = project.get("job_id") or ("job_" + uuid.uuid4().hex[:10])
            project["job_id"] = job_id
            JOBS[job_id] = {
                "id": job_id,
                "project_id": project["id"],
                "status": "queued",
                "percent": 0,
                "step": None,
                "started": time.time(),
            }
            advance_queue(user["email"])
            return self.send_json(200, public_project(project))

    def create_project(self, user: dict) -> None:
        """Start one video from the New screen.

        Refused when the user already has something dubbing or waiting: New
        must never add a job behind other jobs. The lock is held across the
        check and the insert, so two devices racing here create one job.
        """
        body = self.read_json()

        with _lock:
            advance_jobs()
            now, waiting, _ = queue_of(user["email"])
            if now is not None or waiting:
                blocking = now or waiting[0]
                return self.send_error_json(
                    409, "already_dubbing",
                    '"%s" is already dubbing. Add more videos from the Queue tab.'
                    % blocking["title"],
                )

            if user["credits"] < CREDITS_PER_VIDEO:
                return self.send_error_json(
                    402, "not_enough_credits",
                    f"You need {CREDITS_PER_VIDEO} credits.",
                )

            upload = UPLOADS.get(body.get("upload_id") or "")
            item = {
                "file_name": (upload or {}).get("file_name") or "New project.mp4",
                "source_language": body.get("source_language", "en"),
                "target_language": body.get("target_language", "km"),
                "format": body.get("format", "landscape"),
                "voice": body.get("voice", "female"),
                "mix": body.get("mix", {"dubbed_voice": 100, "original_voice": 15, "music": 80}),
            }
            user["credits"] -= CREDITS_PER_VIDEO
            project = self._make_project(user, item, upload or {"file_name": item["file_name"]})
            advance_queue(user["email"])
            return self.send_json(200, public_project(project))


def main() -> None:
    global JOB_SECONDS
    parser = argparse.ArgumentParser(description="Dubber demo server")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument(
        "--job-seconds", type=int, default=JOB_SECONDS,
        help="How long one dubbing job takes (default %(default)s).",
    )
    args = parser.parse_args()

    JOB_SECONDS = args.job_seconds

    os.makedirs(MEDIA_DIR, exist_ok=True)
    os.makedirs(UPLOAD_DIR, exist_ok=True)
    seed()

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print("=" * 60)
    print("  Dubber demo server")
    print("=" * 60)
    print(f"  Listening on   http://{args.host}:{args.port}/v1")
    print(f"  Android emu    http://10.0.2.2:{args.port}/v1")
    print(f"  Demo login     demo@dubber.app / password123")
    print(f"  Job duration   {JOB_SECONDS}s   Export duration {EXPORT_SECONDS}s")
    print("=" * 60)
    print("  Press Ctrl+C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
