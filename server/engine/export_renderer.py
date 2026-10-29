"""FFmpeg renderer for the mobile editor's video export settings."""

from __future__ import annotations

import os
import subprocess
from typing import Any, Callable, Dict, Optional


def _between(start: Any, end: Any) -> str:
    start_s = max(0.0, float(start or 0.0))
    end_s = max(start_s, float(end or 0.0))
    return f"between(t\\,{start_s:g}\\,{end_s:g})"


def _text_filter(text: str) -> str:
    return (text.replace("\\", "\\\\").replace(":", "\\:")
            .replace("'", "\\'").replace("%", "\\%"))


def _audio_stream_exists(path: str) -> bool:
    try:
        result = subprocess.run(
            ["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
             "stream=index", "-of", "csv=p=0", path],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        return bool(result.stdout.strip())
    except (OSError, subprocess.CalledProcessError):
        return False


def render_video_export(
    input_video: str,
    output_video: str,
    settings: Dict[str, Any],
    srt_subtitles_path: Optional[str] = None,
    progress_callback: Optional[Callable[[int], None]] = None,
    *,
    source_media_path: Optional[str] = None,
    dub_track_path: Optional[str] = None,
    legacy_music_volume: Optional[float] = None,
) -> str:
    """Render trim, fit, filters, text, logos, blur regions, subtitles and mix."""
    if progress_callback:
        progress_callback(10)
    os.makedirs(os.path.dirname(os.path.abspath(output_video)), exist_ok=True)

    trim = settings.get("trim") or {}
    start_s = max(0.0, float(trim.get("start") or 0.0))
    end_s = max(0.0, float(trim.get("end") or 0.0))
    fmt = (settings.get("format") or "landscape").lower()
    fit = settings.get("fit") or {}
    fit_mode = (fit.get("mode") or "blur").lower()
    fit_blur = max(1, int(fit.get("blur_strength") or 60))
    texts = settings.get("texts") or []
    logos = settings.get("logos") or []
    blurs = settings.get("blurs") or []
    subtitles = settings.get("subtitles") or {}
    filter_name = ((settings.get("filter") or {}).get("name") or "none").lower()

    out_w, out_h = (720, 1280) if fmt == "portrait" else (1280, 720)
    graph: list[str] = []
    if fmt == "portrait" and fit_mode == "blur":
        graph.extend([
            "[0:v]split=2[fitfg][fitbg]",
            f"[fitbg]scale={out_w}:{out_h}:force_original_aspect_ratio=increase,"
            f"crop={out_w}:{out_h},boxblur={max(1, fit_blur // 4)}[fitbackground]",
            f"[fitfg]scale={out_w}:{out_h}:force_original_aspect_ratio=decrease[fitforeground]",
            "[fitbackground][fitforeground]overlay=(W-w)/2:(H-h)/2[v0]",
        ])
    elif fmt == "portrait" and fit_mode == "fill":
        graph.append(
            f"[0:v]scale={out_w}:{out_h}:force_original_aspect_ratio=increase,"
            f"crop={out_w}:{out_h}[v0]"
        )
    else:
        graph.append(
            f"[0:v]scale={out_w}:{out_h}:force_original_aspect_ratio=decrease,"
            f"pad={out_w}:{out_h}:(ow-iw)/2:(oh-ih)/2:black[v0]"
        )

    v_label = "v0"
    label_index = 1

    def append_video_filter(filter_text: str) -> None:
        nonlocal v_label, label_index
        next_label = f"v{label_index}"
        label_index += 1
        graph.append(f"[{v_label}]{filter_text}[{next_label}]")
        v_label = next_label

    color_filters = {
        "warm": "colorbalance=rs=0.15:gs=0.05:bs=-0.1",
        "cool": "colorbalance=rs=-0.1:gs=0.0:bs=0.15",
        "mono": "hue=s=0",
        "vivid": "eq=saturation=1.4:contrast=1.1",
        "soft": "eq=gamma=1.15:contrast=0.92",
    }
    if filter_name in color_filters:
        append_video_filter(color_filters[filter_name])

    if subtitles.get("show", True) and srt_subtitles_path and os.path.exists(srt_subtitles_path):
        sub_path = os.path.abspath(srt_subtitles_path).replace("\\", "/").replace(":", "\\:").replace("'", "\\'")
        sub_style = (subtitles.get("style") or "classic").lower()
        size = max(12, int(subtitles.get("size") or 55) // 3)
        style = f"FontSize={size},PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000,BorderStyle=1"
        if sub_style == "bold":
            style += ",Bold=1"
        elif sub_style == "box":
            style += ",BorderStyle=3,BackColour=&H80000000,Outline=0"
        append_video_filter(f"subtitles='{sub_path}':force_style='{style}'")

    for item in texts:
        value = (item.get("text") or "").strip()
        if not value:
            continue
        text_value = _text_filter(value)
        x = min(max(float(item.get("x", 0.5)), 0.0), 1.0)
        y = min(max(float(item.get("y", 0.85)), 0.0), 1.0)
        font_size = max(16, int(item.get("size") or 60) // 2)
        color = (item.get("color") or "#FFFFFF").lstrip("#")
        if len(color) != 6 or any(c not in "0123456789abcdefABCDEF" for c in color):
            color = "FFFFFF"
        end = _between(item.get("from", 0), item.get("to", 90))
        append_video_filter(
            f"drawtext=text='{text_value}':fontsize={font_size}:fontcolor=0x{color}"
            f":borderw=2:bordercolor=black:x='w*{x:g}-tw/2':y='h*{y:g}-th/2':enable='{end}'"
        )

    for blur in blurs:
        thickness = min(max(float(blur.get("thickness") or 30), 1.0), 100.0) / 100.0
        strength = min(max(int(blur.get("strength") or 60), 1), 100)
        style = (blur.get("style") or "blur").lower()
        enabled = _between(blur.get("from", 0), blur.get("to", 90))
        for side in blur.get("sides") or []:
            if side == "top":
                width, height, x, y = out_w, max(1, int(out_h * thickness)), 0, 0
            elif side == "bottom":
                width, height, x, y = out_w, max(1, int(out_h * thickness)), 0, out_h - max(1, int(out_h * thickness))
            elif side == "left":
                width, height, x, y = max(1, int(out_w * thickness)), out_h, 0, 0
            elif side == "right":
                width, height, x, y = max(1, int(out_w * thickness)), out_h, out_w - max(1, int(out_w * thickness)), 0
            else:
                continue
            keep_label = f"blur_keep_{label_index}"
            crop_label = f"blur_source_{label_index}"
            effect_label = f"blur_effect_{label_index}"
            next_label = f"v{label_index}"
            label_index += 1
            graph.append(f"[{v_label}]split=2[{keep_label}][{crop_label}]")
            effect = f"[{crop_label}]crop={width}:{height}:{x}:{y}"
            if style == "pixelate":
                small_w, small_h = max(1, width // 16), max(1, height // 16)
                effect += f",scale={small_w}:{small_h}:flags=neighbor,scale={width}:{height}:flags=neighbor"
            else:
                radius = max(1, round(strength / 8))
                effect += f",boxblur={radius}:2"
            graph.append(effect + f"[{effect_label}]")
            graph.append(
                f"[{keep_label}][{effect_label}]overlay={x}:{y}:enable='{enabled}'[{next_label}]"
            )
            v_label = next_label

    stems_available = bool(
        source_media_path and dub_track_path
        and os.path.isfile(source_media_path) and os.path.isfile(dub_track_path)
    )
    audio_source_has_audio = stems_available and _audio_stream_exists(source_media_path or "")
    mix = dict(settings.get("mix") or {})
    remove_legacy_music = bool(
        not stems_available
        and settings.get("keep_background_music") is False
        and source_media_path
        and os.path.isfile(source_media_path)
        and _audio_stream_exists(source_media_path)
        and _audio_stream_exists(input_video)
    )
    if settings.get("keep_background_music") is False:
        mix["music"] = 0
    elif settings.get("keep_background_music") is True and "music" not in mix:
        mix["music"] = 80
    if settings.get("keep_background_music") is False and not stems_available and not remove_legacy_music:
        raise RuntimeError(
            "The original audio is unavailable, so background music cannot be removed from this video."
        )

    cmd = ["ffmpeg", "-y", "-loglevel", "error"]

    def add_input(path: str) -> None:
        if start_s > 0:
            cmd.extend(["-ss", f"{start_s:.3f}"])
        if end_s > start_s:
            cmd.extend(["-t", f"{end_s - start_s:.3f}"])
        cmd.extend(["-i", path])

    add_input(input_video)
    if stems_available:
        add_input(source_media_path or "")
        add_input(dub_track_path or "")
    elif remove_legacy_music:
        add_input(source_media_path or "")

    logo_input_start = 3 if stems_available else (2 if remove_legacy_music else 1)
    logo_labels: list[tuple[dict[str, Any], int, str]] = []
    for offset, logo in enumerate(logos):
        path = logo.get("path")
        if not path or not os.path.isfile(path):
            raise RuntimeError("A selected logo image is unavailable on the server. Upload it again and retry the export.")
        input_index = logo_input_start + offset
        add_input(path)
        logo_label = f"logo_image_{offset}"
        size = min(max(int(logo.get("size") or 40), 16), 100)
        pixel_size = min(out_w, max(24, round(size * out_w / 350)))
        opacity = min(max(int(logo.get("opacity") or 90), 0), 100) / 100
        graph.append(
            f"[{input_index}:v]scale={pixel_size}:{pixel_size}:force_original_aspect_ratio=decrease,"
            f"format=rgba,colorchannelmixer=aa={opacity:.3f}[{logo_label}]"
        )
        logo_labels.append((logo, input_index, logo_label))

    for offset, (logo, _, logo_label) in enumerate(logo_labels):
        next_label = f"v{label_index}"
        label_index += 1
        position = (logo.get("position") or "top_right").lower()
        margin = max(8, round(out_w * 0.035))
        x = f"{margin}" if position.endswith("left") else f"W-w-{margin}"
        y = f"{margin}" if position.startswith("top") else f"H-h-{margin}"
        enabled = _between(logo.get("from", 0), logo.get("to", 90))
        graph.append(f"[{v_label}][{logo_label}]overlay={x}:{y}:enable='{enabled}'[{next_label}]")
        v_label = next_label

    if stems_available:
        from server.engine.gemini_dubber import normalize_mix_settings
        levels = normalize_mix_settings(mix)
        dubbed = levels["dubbed_voice_vol"]
        original_voice = levels["original_voice_vol"]
        music = levels["bg_music_vol"]
        if audio_source_has_audio:
            graph.extend([
                "[1:a]aresample=44100,asplit=2[src_voice][src_music]",
                (f"[src_voice]highpass=f=220,volume={original_voice:.4f}[bg_voice]"
                 if original_voice > 0.001 else "[src_voice]volume=0[bg_voice]"),
                f"[src_music]lowpass=f=220,volume={music:.4f}[bg_music]",
                f"[2:a]volume={dubbed:.4f},aresample=44100[dub]",
                "[bg_voice][bg_music][dub]amix=inputs=3:duration=first:normalize=0,"
                "alimiter=limit=0.95,aresample=44100[aout]",
            ])
        else:
            graph.append(f"[2:a]volume={dubbed:.4f},aresample=44100[aout]")
        audio_label = "aout"
    elif remove_legacy_music:
        music_level = min(max(float(legacy_music_volume if legacy_music_volume is not None else mix.get("music", 80)), 0.0), 100.0) / 100.0
        graph.extend([
            "[0:a]aresample=44100[mixed_audio]",
            f"[1:a]aresample=44100,lowpass=f=220,volume=-{music_level:.4f}[music_to_remove]",
            "[mixed_audio][music_to_remove]amix=inputs=2:duration=first:normalize=0[aout]",
        ])
        audio_label = "aout"
    else:
        audio_label = None

    if progress_callback:
        progress_callback(40)
    cmd.extend(["-filter_complex", ";".join(graph), "-map", f"[{v_label}]"])
    if audio_label:
        cmd.extend(["-map", f"[{audio_label}]"])
    else:
        cmd.extend(["-map", "0:a?"])
        dubbed_volume = float(mix.get("dubbed_voice", 100))
        if dubbed_volume < 100:
            cmd.extend(["-af", f"volume={max(0.0, dubbed_volume) / 100:.3f}"])
    cmd.extend([
        "-c:v", "libx264", "-preset", "veryfast", "-crf", "23",
        "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", output_video,
    ])
    if progress_callback:
        progress_callback(60)
    try:
        subprocess.run(cmd, check=True)
    except (OSError, subprocess.CalledProcessError) as exc:
        raise RuntimeError(
            "The edit render failed (a filter or media asset could not be applied). "
            "Check the selected logo and blur settings, then retry the export."
        ) from exc
    if progress_callback:
        progress_callback(100)
    return output_video
