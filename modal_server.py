#!/usr/bin/env python3
"""Modal Production Server for Dubber Mobile App & Web Viewer.

Deploys the full real Dubber backend on Modal Cloud:
- Audio-first Gemini Multimodal simultaneous transcription & translation pipeline.
- Edge-TTS neural voice synthesis with gender/emotion matching and silenceremove/atempo audio fitting.
- Cloud Tesla T4 GPU acceleration.
- Persistent SQLite storage for users, tokens, projects, queue, uploads, library.
- Interactive Cloud Phone Viewer at `/phone` and `/`.
- Flutter Web Mobile Client at `/app/`.
- Full REST API at `/v1/*`.

Deploy with:
    modal deploy modal_server.py
"""

from __future__ import annotations

import os
import sys
import modal

# ── Modal Container Configuration ────────────────────────────────────────────

image = (
    modal.Image.debian_slim()
    .apt_install("ffmpeg")
    .pip_install(
        "fastapi",
        "uvicorn[standard]",
        "pydantic",
        "python-multipart",
        "edge-tts",
        "aiohttp",
        "requests",
    )
    .add_local_dir("server", remote_path="/root/server")
    .add_local_dir("dubber_app/build/web", remote_path="/root/web_app")
)

app = modal.App("dubber-real-server", image=image)

# Shared persistent state (db, uploads, dubbed outputs, engine config).
# Without this, every container gets its own copy of server/ and nothing
# persists across requests.
volume = modal.Volume.from_name("dubber-data", create_if_missing=True)
DATA_ENV = {"DUBBER_DATA_DIR": "/root/data"}

# ── GPU Function for Accelerated AI Dubbing ──────────────────────────────────

@app.function(gpu="T4", timeout=600, volumes={"/root/data": volume}, env=DATA_ENV)
def process_gpu_dubbing(
    media_bytes: bytes,
    file_name: str,
    target_language: str = "km",
    source_language: str = "en",
    voice: str = "female",
    mix: dict = None,
) -> dict:
    """NVIDIA Tesla T4 GPU-accelerated dubbing worker on Modal Cloud."""
    import tempfile
    import subprocess
    import sys
    if "/root" not in sys.path:
        sys.path.insert(0, "/root")
    
    from server.engine.gemini_dubber import dub_video_pipeline

    with tempfile.TemporaryDirectory() as tmpdir:
        input_file = os.path.join(tmpdir, file_name)
        with open(input_file, "wb") as f:
            f.write(media_bytes)

        mix_settings = mix or {"dubbed_voice": 100, "original_voice": 15, "music": 80}
        
        result = dub_video_pipeline(
            media_path=input_file,
            output_dir=tmpdir,
            target_language=target_language,
            source_language=source_language,
            voice=voice,
            mix_settings=mix_settings,
        )

        dubbed_bytes = None
        if result.get("dubbed_media") and os.path.exists(result["dubbed_media"]):
            with open(result["dubbed_media"], "rb") as f:
                dubbed_bytes = f.read()

        return {
            "success": True,
            "segments_count": result.get("segments_count", 0),
            "output_format": result.get("output_format", "video"),
            "dubbed_bytes_len": len(dubbed_bytes) if dubbed_bytes else 0,
        }

# ── Production ASGI Application Mount ────────────────────────────────────────

# ponytail: max_containers=1 — one web container sees its own volume writes
# immediately (config saves, db); multiple containers would read stale volume
# snapshots. Raise only together with a real shared-config store.
@app.function(volumes={"/root/data": volume}, env=DATA_ENV, timeout=3600, max_containers=1)
@modal.asgi_app()
def web_app():
    import sys
    import os

    if "/root" not in sys.path:
        sys.path.insert(0, "/root")

    os.environ["WEB_APP_DIR"] = "/root/web_app"
    
    from server.main import app as fastapi_app
    return fastapi_app

if __name__ == "__main__":
    print("Run: modal deploy modal_server.py")
