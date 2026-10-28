# -*- coding: utf-8 -*-
"""
test_gemini_engine.py — Comprehensive verification for Gemini Dubber Engine.
Tests:
1. Audio extraction & duration probing.
2. analyze_and_translate (with Gemini / fallback mock lines).
3. synthesize_speech_and_mix (Edge-TTS neural voices, atempo, and ffmpeg mixing).
4. Full end-to-end dub_video_pipeline with progress tracking.
"""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

# Ensure server package is importable
SERVER_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SERVER_DIR)
if PROJECT_DIR not in sys.path:
    sys.path.insert(0, PROJECT_DIR)

from server.engine.gemini_dubber import (
    analyze_and_translate,
    synthesize_speech_and_mix,
    dub_video_pipeline,
    get_duration,
    extract_audio_16k,
    format_srt_time,
)


class TestGeminiDubberEngine(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.test_dir = tempfile.mkdtemp(prefix="gemini_dubber_test_")
        cls.sample_video = os.path.join(cls.test_dir, "sample_clip.mp4")

        # Generate a 5-second synthetic test video with color bars and a tone
        cmd = [
            "ffmpeg", "-y", "-loglevel", "error",
            "-f", "lavfi", "-i", "testsrc=duration=5:size=640x360:rate=24",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=5",
            "-c:v", "libx264", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "128k",
            "-shortest",
            cls.sample_video
        ]
        subprocess.run(cmd, check=True)
        print(f"\n[SETUP] Created test synthetic video: {cls.sample_video}")

    @classmethod
    def tearDownClass(cls):
        try:
            shutil.rmtree(cls.test_dir)
            print(f"[TEARDOWN] Cleaned up test folder: {cls.test_dir}")
        except Exception:
            pass

    def test_01_duration_and_audio_extraction(self):
        print("\n--- Test 1: Duration and Audio Extraction ---")
        dur = get_duration(self.sample_video)
        print(f"Detected duration: {dur:.2f}s")
        self.assertAlmostEqual(dur, 5.0, delta=0.5)

        wav_path = os.path.join(self.test_dir, "extracted_audio.mp3")
        extract_audio_16k(self.sample_video, wav_path)
        self.assertTrue(os.path.exists(wav_path))
        self.assertGreater(os.path.getsize(wav_path), 1000)
        print(f"Extracted 16kHz audio: {wav_path} ({os.path.getsize(wav_path)} bytes)")

    def test_02_analyze_and_translate(self):
        print("\n--- Test 2: Simultaneous Transcribe & Translate (Gemini) ---")
        lines = analyze_and_translate(
            media_path=self.sample_video,
            target_language="Khmer",
            source_language="English"
        )
        self.assertIsInstance(lines, list)
        self.assertGreater(len(lines), 0)
        first = lines[0]
        print(f"Transcribed lines count: {len(lines)}")
        print(f"First line: {first}")

        # Check required schema keys
        for key in ["start", "end", "character", "gender", "emotion", "text_original", "text_target"]:
            self.assertIn(key, first)
        self.assertIsInstance(first["start"], (int, float))
        self.assertIsInstance(first["end"], (int, float))
        self.assertGreater(len(first["text_target"]), 0)

    def test_03_srt_timestamp_formatting(self):
        print("\n--- Test 3: SRT Timestamp Formatting ---")
        t_str = format_srt_time(65.432)
        print(f"65.432s -> {t_str}")
        self.assertEqual(t_str, "00:01:05,432")

    def test_04_synthesize_speech_and_mix(self):
        print("\n--- Test 4: Edge-TTS Speech Synthesis and Video Mixing ---")
        lines = [
            {
                "start": 0.5,
                "end": 2.2,
                "character": "Host",
                "gender": "female",
                "emotion": "happy",
                "text_original": "Welcome to Dubber.",
                "text_target": "សូមស្វាគមន៍មកកាន់ Dubber។",
            },
            {
                "start": 2.5,
                "end": 4.5,
                "character": "Guest",
                "gender": "male",
                "emotion": "neutral",
                "text_original": "It is great to be here.",
                "text_target": "ពិតជារីករាយណាស់ដែលបានមកទីនេះ។",
            }
        ]
        out_media = os.path.join(self.test_dir, "test_mixed_output.mp4")
        video_path, srt_path = synthesize_speech_and_mix(
            lines=lines,
            original_media=self.sample_video,
            output_media=out_media,
            target_language="Khmer",
            voice="female",
            mix_settings={"dubbed_voice_vol": 1.0, "original_voice_vol": 0.15}
        )

        self.assertTrue(os.path.exists(video_path))
        self.assertTrue(os.path.exists(srt_path))
        self.assertGreater(os.path.getsize(video_path), 5000)
        self.assertGreater(os.path.getsize(srt_path), 20)

        # Verify output duration
        out_dur = get_duration(video_path)
        print(f"Mixed video output: {video_path} (Duration: {out_dur:.2f}s)")
        print(f"Subtitles file: {srt_path}")
        with open(srt_path, "r", encoding="utf-8") as f:
            print("SRT Preview:\n" + f.read())

    def test_05_end_to_end_dub_pipeline(self):
        print("\n--- Test 5: End-to-End dub_video_pipeline ---")
        progress_log = []

        def on_progress(percent, step):
            progress_log.append((percent, step))
            print(f"  [PIPELINE PROGRESS] {percent}%: {step}")

        out_dir = os.path.join(self.test_dir, "dubbed_export")
        result = dub_video_pipeline(
            media_path=self.sample_video,
            output_dir=out_dir,
            target_language="Khmer",
            source_language="English",
            voice="female",
            progress_callback=on_progress
        )

        print("\nPipeline Result Summary:")
        for k, v in result.items():
            if k != "lines":
                print(f"  {k}: {v}")

        self.assertEqual(result["status"], "success")
        self.assertTrue(os.path.exists(result["video_path"]))
        self.assertTrue(os.path.exists(result["srt_path"]))
        self.assertGreater(len(progress_log), 3)
        self.assertEqual(progress_log[-1][0], 100)


if __name__ == "__main__":
    unittest.main()
