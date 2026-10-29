"""Dubber Video Export Rendering Engine.

Processes edit settings (trim, format/fit, texts, logos, subtitles, blurs, filters, audio mix)
and renders final export videos using FFmpeg.
"""

from __future__ import annotations

import os
import subprocess
import tempfile
from typing import Any, Callable, Dict, Optional


def render_video_export(
    input_video: str,
    output_video: str,
    settings: Dict[str, Any],
    srt_subtitles_path: Optional[str] = None,
    progress_callback: Optional[Callable[[int], None]] = None,
) -> str:
    """Renders a final edited MP4 from input_video using export settings."""
    if progress_callback:
        progress_callback(10)

    os.makedirs(os.path.dirname(os.path.abspath(output_video)), exist_ok=True)

    # 1. Parsing settings
    trim = settings.get("trim") or {}
    start_s = float(trim.get("start") or 0.0)
    end_s = float(trim.get("end") or 0.0)

    fmt = (settings.get("format") or "landscape").lower()
    fit = settings.get("fit") or {}
    fit_mode = (fit.get("mode") or "blur").lower()
    fit_blur = int(fit.get("blur_strength") or 60)

    texts = settings.get("texts") or []
    subtitles = settings.get("subtitles") or {}
    show_subtitles = bool(subtitles.get("show", True))
    filter_data = settings.get("filter") or {}
    filter_name = (filter_data.get("name") or "none").lower()

    # 2. Build Video Filter Graph
    v_filters = []

    # Aspect ratio & Fit (landscape 16:9 = 1280x720, portrait 9:16 = 720x1280)
    if fmt == "portrait":
        out_w, out_h = 720, 1280
        if fit_mode == "blur":
            # Scale background to fill & blur, scale foreground to fit, overlay
            v_filters.append(
                f"split=2[fg][bg];[bg]scale={out_w}:{out_h}:force_original_aspect_ratio=increase,crop={out_w}:{out_h},boxblur={max(1, fit_blur // 4)}[blurred];[fg]scale={out_w}:{out_h}:force_original_aspect_ratio=decrease[scaled];[blurred][scaled]overlay=(W-w)/2:(H-h)/2"
            )
        else:
            # Black bars / pad
            v_filters.append(
                f"scale={out_w}:{out_h}:force_original_aspect_ratio=decrease,pad={out_w}:{out_h}:(ow-iw)/2:(oh-ih)/2:black"
            )
    else:
        out_w, out_h = 1280, 720
        v_filters.append(
            f"scale={out_w}:{out_h}:force_original_aspect_ratio=decrease,pad={out_w}:{out_h}:(ow-iw)/2:(oh-ih)/2:black"
        )

    # Color filter
    if filter_name == "warm":
        v_filters.append("colorbalance=rs=0.15:gs=0.05:bs=-0.1")
    elif filter_name == "cool":
        v_filters.append("colorbalance=rs=-0.1:gs=0.0:bs=0.15")
    elif filter_name == "mono":
        v_filters.append("hue=s=0")
    elif filter_name == "vivid":
        v_filters.append("eq=saturation=1.4:contrast=1.1")
    elif filter_name == "soft":
        v_filters.append("eq=gamma=1.15:contrast=0.92")

    # Burn subtitles if available and requested
    if show_subtitles and srt_subtitles_path and os.path.exists(srt_subtitles_path):
        # Escape path for ffmpeg subtitles filter
        escaped_srt = srt_subtitles_path.replace("\\", "/").replace(":", "\\:")
        sub_size = int(subtitles.get("size") or 55) // 3
        v_filters.append(f"subtitles='{escaped_srt}':force_style='FontSize={sub_size},PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,BorderStyle=1'")

    # Draw text overlays
    for t in texts:
        txt = (t.get("text") or "").replace("'", "").replace(":", "")
        if not txt:
            continue
        frac_x = float(t.get("x") or 0.5)
        frac_y = float(t.get("y") or 0.85)
        font_sz = max(16, int(t.get("size") or 60) // 2)
        v_filters.append(
            f"drawtext=text='{txt}':fontsize={font_sz}:fontcolor=white:borderw=2:bordercolor=black:x='w*{frac_x}-tw/2':y='h*{frac_y}-th/2'"
        )

    vf_chain = ",".join(v_filters) if v_filters else "null"

    if progress_callback:
        progress_callback(40)

    # Audio mix: the exported file is the already-dubbed video, so only the
    # dub track volume is meaningful here. The original/music sliders were
    # applied when the dub was rendered; re-applying them would double-scale.
    mix = settings.get("mix") or {}
    from server.engine.gemini_dubber import normalize_mix_settings

    mix_vol = normalize_mix_settings(mix)["dubbed_voice_vol"]
    af_chain = f"volume={mix_vol:.3f}" if mix_vol < 0.999 else None

    # 3. Assemble FFmpeg Command
    cmd = ["ffmpeg", "-y", "-loglevel", "error"]

    # Trim range
    if start_s > 0:
        cmd.extend(["-ss", f"{start_s:.2f}"])
    if end_s > start_s:
        cmd.extend(["-to", f"{end_s:.2f}"])

    cmd.extend([
        "-i", input_video,
        "-vf", vf_chain,
    ])
    if af_chain:
        cmd.extend(["-af", af_chain])
    cmd.extend([
        "-c:v", "libx264",
        "-preset", "veryfast",
        "-crf", "23",
        "-c:a", "aac",
        "-b:a", "192k",
        "-movflags", "+faststart",
        output_video,
    ])

    if progress_callback:
        progress_callback(60)

    try:
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError:
        # Fallback to simple copy if complex filter failed
        fallback_cmd = [
            "ffmpeg", "-y", "-loglevel", "error",
            "-i", input_video,
            "-c:v", "copy",
            "-c:a", "copy",
            output_video,
        ]
        subprocess.run(fallback_cmd, check=True)

    if progress_callback:
        progress_callback(100)

    return output_video
