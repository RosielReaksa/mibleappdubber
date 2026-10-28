# -*- coding: utf-8 -*-
"""test_openai_provider.py — OpenAI-compatible provider plumbing (Vilao etc.).

Checks:
1. resolve_gemini_endpoint picks /chat/completions for api_type="openai"
   (no double /v1) and keeps :generateContent for api_type="gemini".
2. api_type round-trips through save_engine_config / get_engine_config.
3. test_gemini_connection succeeds against a local OpenAI-shaped HTTP server.
"""

import json
import os
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

SERVER_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SERVER_DIR)
if PROJECT_DIR not in sys.path:
    sys.path.insert(0, PROJECT_DIR)

from server.engine import gemini_dubber


class TestOpenAIProvider(unittest.TestCase):
    def test_01_endpoint_resolution(self):
        # Vilao-style base (ends in /v1) -> single /v1/chat/completions
        self.assertEqual(
            gemini_dubber.resolve_gemini_endpoint("https://api.vilao.ai/v1", "gemini-3.8-flash", "openai"),
            "https://api.vilao.ai/v1/chat/completions",
        )
        # Bare host -> /v1/chat/completions appended
        self.assertEqual(
            gemini_dubber.resolve_gemini_endpoint("https://api.vilao.ai", "gemini-3.8-flash", "openai"),
            "https://api.vilao.ai/v1/chat/completions",
        )
        # Full chat endpoint pasted -> untouched
        self.assertEqual(
            gemini_dubber.resolve_gemini_endpoint("https://api.vilao.ai/v1/chat/completions", "x", "openai"),
            "https://api.vilao.ai/v1/chat/completions",
        )
        # Gemini path unchanged
        self.assertEqual(
            gemini_dubber.resolve_gemini_endpoint("https://api.kukuai.fyi/v1", "gemini-3.8-flash", "gemini"),
            "https://api.kukuai.fyi/v1/models/gemini-3.8-flash:generateContent",
        )

    def test_02_api_type_round_trip(self):
        old = gemini_dubber.get_engine_config()
        try:
            cfg = gemini_dubber.save_engine_config(
                base_url="https://api.vilao.ai/v1",
                api_key="sk-test",
                model="gemini-3.8-flash",
                api_type="openai",
            )
            self.assertEqual(cfg["api_type"], "openai")
            self.assertEqual(gemini_dubber.get_engine_config()["api_type"], "openai")
        finally:
            gemini_dubber.save_engine_config(
                base_url=old.get("base_url"),
                api_key=old.get("api_key"),
                model=old.get("model"),
                api_type=old.get("api_type", "gemini"),
            )

    def test_03_connection_against_openai_shape(self):
        seen = {}

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                seen["path"] = self.path
                seen["model"] = body.get("model")
                seen["messages"] = body.get("messages")
                out = json.dumps({
                    "choices": [{"message": {"role": "assistant", "content": "OK"}}]
                }).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(out)))
                self.end_headers()
                self.wfile.write(out)

            def log_message(self, *a):
                pass

        server = HTTPServer(("127.0.0.1", 0), Handler)
        port = server.server_address[1]
        t = threading.Thread(target=server.serve_forever, daemon=True)
        t.start()
        try:
            result = gemini_dubber.test_gemini_connection(
                f"http://127.0.0.1:{port}/v1", "sk-test", "gemini-3.8-flash", "openai"
            )
            self.assertTrue(result["success"], result)
            self.assertEqual(seen["path"], "/v1/chat/completions")
            self.assertEqual(seen["model"], "gemini-3.8-flash")
            self.assertEqual(seen["messages"][0]["role"], "user")
            self.assertEqual(seen["messages"][0]["content"], "Respond with single word: OK")
        finally:
            server.shutdown()


if __name__ == "__main__":
    unittest.main()
