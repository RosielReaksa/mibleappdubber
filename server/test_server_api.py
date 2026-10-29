#!/usr/bin/env python3
"""Integration tests for Dubber Real Production Backend API."""

import os
import sys
import unittest
from fastapi.testclient import TestClient

# Ensure workspace root is in python path
WORKSPACE_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if WORKSPACE_ROOT not in sys.path:
    sys.path.insert(0, WORKSPACE_ROOT)

from server.main import app
from server import db

class TestServerAPI(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)

    def test_01_health_and_phone(self):
        r = self.client.get("/health")
        self.assertEqual(r.status_code, 200)
        data = r.json()
        self.assertTrue(data.get("ok"))
        self.assertIn("Dubber Real Production Backend", data.get("server"))

        # Phone viewer HTML
        r_phone = self.client.get("/phone")
        self.assertEqual(r_phone.status_code, 200)
        self.assertIn("Dubber Production Mobile Server", r_phone.text)
        self.assertIn("phone-wrapper", r_phone.text)

    def test_02_auth_and_user(self):
        # Login demo user
        r = self.client.post("/v1/auth/login", json={"email": "demo@dubber.app", "password": "password123"})
        self.assertEqual(r.status_code, 200)
        tokens = r.json()
        self.assertIn("access_token", tokens)
        self.assertIn("refresh_token", tokens)
        token = tokens["access_token"]

        # /v1/me
        r_me = self.client.get("/v1/me", headers={"Authorization": f"Bearer {token}"})
        self.assertEqual(r_me.status_code, 200)
        me = r_me.json()
        self.assertEqual(me["email"], "demo@dubber.app")

        # Static metadata
        r_lang = self.client.get("/v1/languages")
        self.assertEqual(r_lang.status_code, 200)
        self.assertTrue(len(r_lang.json()) >= 10)

        r_voices = self.client.get("/v1/voices")
        self.assertEqual(r_voices.status_code, 200)
        self.assertTrue(len(r_voices.json()) >= 2)

    def test_03_library_crud(self):
        r_login = self.client.post("/v1/auth/login", json={"email": "demo@dubber.app", "password": "password123"})
        token = r_login.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        # 1. Logos
        r_logos = self.client.get("/v1/assets/logos", headers=headers)
        self.assertEqual(r_logos.status_code, 200)
        initial_logos_count = len(r_logos.json())

        r_add_logo = self.client.post("/v1/assets/logos", headers=headers, json={"name": "Brand X", "url": "/media/brand.png"})
        self.assertEqual(r_add_logo.status_code, 201)
        lid = r_add_logo.json()["id"]

        r_up_logo = self.client.put(f"/v1/assets/logos/{lid}", headers=headers, json={"name": "Brand Y"})
        self.assertEqual(r_up_logo.status_code, 200)
        self.assertEqual(r_up_logo.json()["name"], "Brand Y")

        r_del_logo = self.client.delete(f"/v1/assets/logos/{lid}", headers=headers)
        self.assertEqual(r_del_logo.status_code, 200)

        # 2. Styles
        r_add_style = self.client.post("/v1/styles", headers=headers, json={
            "name": "Super Sub",
            "kind": "subtitle",
            "size": 45,
            "color": "#FFCC00",
            "subtitle_style": "bold"
        })
        self.assertEqual(r_add_style.status_code, 201)
        sid = r_add_style.json()["id"]

        r_up_style = self.client.put(f"/v1/styles/{sid}", headers=headers, json={"name": "Mega Sub", "size": 52})
        self.assertEqual(r_up_style.status_code, 200)
        self.assertEqual(r_up_style.json()["name"], "Mega Sub")
        self.assertEqual(r_up_style.json()["size"], 52)

        r_del_style = self.client.delete(f"/v1/styles/{sid}", headers=headers)
        self.assertEqual(r_del_style.status_code, 200)

        # 3. Presets
        r_add_preset = self.client.post("/v1/presets", headers=headers, json={
            "name": "Gaming Reel",
            "settings": {"format": "portrait", "mix": {"dubbed_voice": 100, "original_voice": 10}}
        })
        self.assertEqual(r_add_preset.status_code, 201)
        prid = r_add_preset.json()["id"]

        r_up_preset = self.client.put(f"/v1/presets/{prid}", headers=headers, json={"name": "Gaming Reel Pro"})
        self.assertEqual(r_up_preset.status_code, 200)
        self.assertEqual(r_up_preset.json()["name"], "Gaming Reel Pro")

        r_del_preset = self.client.delete(f"/v1/presets/{prid}", headers=headers)
        self.assertEqual(r_del_preset.status_code, 200)

    def test_04_uploads_flow(self):
        r_login = self.client.post("/v1/auth/login", json={"email": "demo@dubber.app", "password": "password123"})
        token = r_login.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        # Initiate upload
        r_init = self.client.post("/v1/uploads", headers=headers, json={"file_name": "sample_clip.mp4", "size": 1024})
        self.assertEqual(r_init.status_code, 200)
        uid = r_init.json()["id"]

        # Upload part 1
        dummy_chunk = b"X" * 1024
        r_part = self.client.put(f"/v1/uploads/{uid}/parts/1", headers=headers, content=dummy_chunk)
        self.assertEqual(r_part.status_code, 200)
        self.assertEqual(r_part.json()["received"], 1024)

        # Complete upload
        r_comp = self.client.post(f"/v1/uploads/{uid}/complete", headers=headers)
        self.assertEqual(r_comp.status_code, 200)
        self.assertTrue(r_comp.json()["complete"])

    def test_05_queue_and_projects(self):
        r_login = self.client.post("/v1/auth/login", json={"email": "demo@dubber.app", "password": "password123"})
        token = r_login.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        # Top up credits so the add is not rejected for balance.
        db.update_user_credits("demo@dubber.app", 100)

        # Check queue
        r_queue = self.client.get("/v1/queue", headers=headers)
        self.assertEqual(r_queue.status_code, 200)
        q_data = r_queue.json()
        self.assertIn("now_dubbing", q_data)
        self.assertIn("up_next", q_data)
        self.assertIn("slots_left", q_data)

        # List projects
        r_projs = self.client.get("/v1/projects", headers=headers)
        self.assertEqual(r_projs.status_code, 200)
        self.assertTrue(isinstance(r_projs.json(), list))

        # Add queue item
        r_add_items = self.client.post("/v1/queue/items", headers=headers, json={
            "items": [
                {
                    "file_name": "TestQueue1.mp4",
                    "source_language": "en",
                    "target_language": "km",
                    "voice": "female"
                }
            ]
        })
        self.assertEqual(r_add_items.status_code, 200)
        items_res = r_add_items.json()
        self.assertTrue(len(items_res["up_next"]) > 0 or items_res["now_dubbing"] is not None)
        self.assertEqual(items_res["reserved_credits"], 12)

        # Check active item
        r_active = self.client.get("/v1/queue/active", headers=headers)
        self.assertEqual(r_active.status_code, 200)

if __name__ == "__main__":
    unittest.main()
