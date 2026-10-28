"""Comprehensive test suite for server/db.py.

Verifies:
1. Database initialization and schema creation.
2. Seed data (demo user, projects, logo, styles, preset).
3. User CRUD and credits operations.
4. Token creation, verification, and refresh lifecycle.
5. Project CRUD and status workflows.
6. Queue item addition, retrieval, move, reordering, and removal.
7. Chunked upload creation, binary chunk appending, and completion.
8. Logo CRUD.
9. Style CRUD.
10. Preset CRUD.
"""

from __future__ import annotations

import os
import shutil
import sys
import tempfile
import unittest

# Ensure server module is importable
HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import db


class TestDubberDB(unittest.TestCase):
    def setUp(self) -> None:
        self.test_dir = tempfile.mkdtemp(prefix="dubber_test_")
        self.db_path = os.path.join(self.test_dir, "test_dubber.db")
        db.init_db(self.db_path)

    def tearDown(self) -> None:
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_01_init_and_seed(self) -> None:
        """Verify initialization creates all tables and seeds demo account."""
        with db.get_db(self.db_path) as conn:
            cur = conn.cursor()
            cur.execute(
                "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
            )
            tables = {r[0] for r in cur.fetchall()}

        required_tables = {
            "users",
            "tokens",
            "projects",
            "queue_items",
            "uploads",
            "logos",
            "styles",
            "presets",
        }
        self.assertTrue(
            required_tables.issubset(tables),
            f"Missing tables: {required_tables - tables}",
        )

        # Check demo user
        demo_user = db.get_user("demo@dubber.app", self.db_path)
        self.assertIsNotNone(demo_user)
        self.assertEqual(demo_user["email"], "demo@dubber.app")
        self.assertEqual(demo_user["name"], "Demo User")
        self.assertEqual(demo_user["credits"], 120)
        self.assertTrue(db.verify_password("password123", demo_user["password_hash"]))

        # Check seeded projects
        projects = db.list_projects("demo@dubber.app", self.db_path)
        self.assertEqual(len(projects), 2)
        p1 = db.get_project("p_demo1", self.db_path)
        self.assertIsNotNone(p1)
        self.assertEqual(p1["status"], "done")
        self.assertEqual(p1["percent"], 100)
        self.assertIn("dubbed_voice", p1.get("mix", {}))

        # Check seeded logo
        logos = db.list_logos("demo@dubber.app", self.db_path)
        self.assertEqual(len(logos), 1)
        self.assertEqual(logos[0]["name"], "Acme Brand")

        # Check seeded styles
        styles = db.list_styles("demo@dubber.app", self.db_path)
        self.assertEqual(len(styles), 2)

        # Check seeded preset
        presets = db.list_presets("demo@dubber.app", self.db_path)
        self.assertEqual(len(presets), 1)
        self.assertEqual(presets[0]["name"], "My Shorts Preset")
        self.assertIn("format", presets[0].get("settings", {}))

    def test_02_user_crud(self) -> None:
        """Test user creation, credit updates, and retrieval."""
        user = db.create_user(
            "alice@example.com", "secretpass", "Alice", 50, self.db_path
        )
        self.assertEqual(user["email"], "alice@example.com")
        self.assertEqual(user["credits"], 50)

        fetched = db.get_user("alice@example.com", self.db_path)
        self.assertIsNotNone(fetched)
        self.assertEqual(fetched["name"], "Alice")
        self.assertTrue(db.verify_password("secretpass", fetched["password_hash"]))

        # Credits update
        updated = db.update_user_credits("alice@example.com", -12, self.db_path)
        self.assertEqual(updated["credits"], 38)
        updated2 = db.update_user_credits("alice@example.com", 20, self.db_path)
        self.assertEqual(updated2["credits"], 58)

    def test_03_tokens_lifecycle(self) -> None:
        """Test token creation, verification, and refresh."""
        tok = db.create_token("demo@dubber.app", db_path=self.db_path)
        self.assertTrue(tok["access_token"].startswith("at_"))
        self.assertTrue(tok["refresh_token"].startswith("rt_"))

        # Verification
        verified_email = db.verify_token(tok["access_token"], self.db_path)
        self.assertEqual(verified_email, "demo@dubber.app")

        # Non-existent token
        self.assertIsNone(db.verify_token("invalid_token", self.db_path))

        # Expired token test
        expired_tok = db.create_token(
            "demo@dubber.app", expires_in_seconds=-10, db_path=self.db_path
        )
        self.assertIsNone(db.verify_token(expired_tok["access_token"], self.db_path))
        self.assertIsNone(db.refresh_token(expired_tok["refresh_token"], db_path=self.db_path))

        # Refresh
        refreshed = db.refresh_token(tok["refresh_token"], db_path=self.db_path)
        self.assertIsNotNone(refreshed)
        self.assertNotEqual(refreshed["access_token"], tok["access_token"])

        # Old access token remains or is invalidated, old refresh is invalidated
        self.assertIsNone(db.refresh_token(tok["refresh_token"], db_path=self.db_path))
        self.assertEqual(
            db.verify_token(refreshed["access_token"], self.db_path),
            "demo@dubber.app",
        )

    def test_04_projects_crud(self) -> None:
        """Test creating, reading, updating, and deleting projects."""
        p_data = {
            "title": "New Podcast.mp4",
            "status": "queued",
            "source_language": "en",
            "target_language": "fr",
            "format": "landscape",
            "voice": "male",
            "mix": {"dubbed_voice": 90, "music": 50},
            "owner": "demo@dubber.app",
        }
        proj = db.create_project(p_data, self.db_path)
        self.assertIsNotNone(proj)
        self.assertTrue(proj["id"].startswith("p_"))
        self.assertEqual(proj["title"], "New Podcast.mp4")
        self.assertEqual(proj["status"], "queued")
        self.assertEqual(proj["mix"]["music"], 50)

        # Update
        updated = db.update_project(
            proj["id"],
            status="processing",
            percent=45,
            step="translate",
            db_path=self.db_path,
        )
        self.assertEqual(updated["status"], "processing")
        self.assertEqual(updated["percent"], 45)
        self.assertEqual(updated["step"], "translate")

        # Delete
        deleted = db.delete_project(proj["id"], self.db_path)
        self.assertTrue(deleted)
        self.assertIsNone(db.get_project(proj["id"], self.db_path))

    def test_05_queue_operations(self) -> None:
        """Test queue item addition, get_queue states, move, reorder, and removal."""
        email = "demo@dubber.app"
        # Create 3 projects: one processing, two queued
        p_proc = db.create_project(
            {
                "id": "p_running",
                "title": "Running video",
                "status": "processing",
                "owner": email,
            },
            self.db_path,
        )
        p_q1 = db.create_project(
            {"id": "p_wait1", "title": "Wait 1", "status": "queued", "owner": email},
            self.db_path,
        )
        p_q2 = db.create_project(
            {"id": "p_wait2", "title": "Wait 2", "status": "queued", "owner": email},
            self.db_path,
        )

        q1 = db.add_queue_item(
            {"project_id": "p_wait1", "owner": email, "position": 1}, self.db_path
        )
        q2 = db.add_queue_item(
            {"project_id": "p_wait2", "owner": email, "position": 2}, self.db_path
        )
        self.assertEqual(q1["position"], 1)
        self.assertEqual(q2["position"], 2)

        # get_queue -> (now, waiting, failed, slots_left)
        now, waiting, failed, slots_left = db.get_queue(email, self.db_path)
        self.assertIsNotNone(now)
        self.assertEqual(now["id"], "p_running")
        self.assertEqual(len(waiting), 2)
        self.assertEqual(waiting[0]["id"], "p_wait1")
        self.assertEqual(waiting[1]["id"], "p_wait2")
        # MAX_QUEUE_PER_USER is 20: 1 now + 2 waiting = 3 => 17 slots left
        self.assertEqual(slots_left, 17)

        # Move item 2 to top
        db.move_queue_item(p_q2["id"], to=1, db_path=self.db_path)
        now, waiting, failed, slots_left = db.get_queue(email, self.db_path)
        self.assertEqual(waiting[0]["id"], "p_wait2")
        self.assertEqual(waiting[1]["id"], "p_wait1")

        # Reorder queue
        db.reorder_queue(email, ["p_wait1", "p_wait2"], self.db_path)
        now, waiting, failed, slots_left = db.get_queue(email, self.db_path)
        self.assertEqual(waiting[0]["id"], "p_wait1")
        self.assertEqual(waiting[1]["id"], "p_wait2")

        # Remove queue item
        removed = db.remove_queue_item("p_wait1", self.db_path)
        self.assertTrue(removed)
        now, waiting, failed, slots_left = db.get_queue(email, self.db_path)
        self.assertEqual(len(waiting), 1)
        self.assertEqual(waiting[0]["id"], "p_wait2")

    def test_06_chunked_uploads(self) -> None:
        """Test upload registration, chunk appending, and completion."""
        upload_path = os.path.join(self.test_dir, "test_file.bin")
        upload = db.create_upload(
            {
                "file_name": "source.mp4",
                "size": 1000,
                "owner": "demo@dubber.app",
                "path": upload_path,
            },
            self.db_path,
        )
        self.assertTrue(upload["id"].startswith("up_"))
        self.assertEqual(upload["received"], 0)
        self.assertFalse(upload["complete"])

        # Append parts
        chunk1 = b"ABCDEFGHIJ"
        u1 = db.append_upload_part(upload["id"], chunk1, self.db_path)
        self.assertEqual(u1["received"], 10)
        self.assertTrue(os.path.exists(upload_path))

        chunk2 = b"KLMNOPQRST"
        u2 = db.append_upload_part(upload["id"], chunk2, self.db_path)
        self.assertEqual(u2["received"], 20)

        with open(upload_path, "rb") as f:
            self.assertEqual(f.read(), b"ABCDEFGHIJKLMNOPQRST")

        # Complete
        comp = db.complete_upload(upload["id"], self.db_path)
        self.assertTrue(comp["complete"])

    def test_07_logos_crud(self) -> None:
        """Test logos CRUD."""
        email = "demo@dubber.app"
        logo = db.create_logo(
            {"name": "Watermark", "url": "/media/watermark.png", "owner": email},
            self.db_path,
        )
        self.assertTrue(logo["id"].startswith("logo_"))
        self.assertEqual(logo["name"], "Watermark")

        updated = db.update_logo(
            logo["id"], name="New Watermark", db_path=self.db_path
        )
        self.assertEqual(updated["name"], "New Watermark")

        logos = db.list_logos(email, self.db_path)
        self.assertTrue(any(l["id"] == logo["id"] for l in logos))

        deleted = db.delete_logo(logo["id"], self.db_path)
        self.assertTrue(deleted)
        self.assertFalse(any(l["id"] == logo["id"] for l in db.list_logos(email, self.db_path)))

    def test_08_styles_crud(self) -> None:
        """Test styles CRUD."""
        email = "demo@dubber.app"
        style = db.create_style(
            {
                "name": "Red title",
                "kind": "text",
                "size": 48,
                "color": "#FF0000",
                "subtitle_style": "box",
                "owner": email,
            },
            self.db_path,
        )
        self.assertTrue(style["id"].startswith("sty_"))
        self.assertEqual(style["size"], 48)

        updated = db.update_style(
            style["id"], size=52, color="#00FF00", db_path=self.db_path
        )
        self.assertEqual(updated["size"], 52)
        self.assertEqual(updated["color"], "#00FF00")

        deleted = db.delete_style(style["id"], self.db_path)
        self.assertTrue(deleted)

    def test_09_presets_crud(self) -> None:
        """Test presets CRUD."""
        email = "demo@dubber.app"
        preset = db.create_preset(
            {
                "name": "Social Landscape",
                "description": "Landscape 16:9 preset",
                "settings": {"format": "landscape", "mix": {"dubbed_voice": 95}},
                "owner": email,
            },
            self.db_path,
        )
        self.assertTrue(preset["id"].startswith("pre_"))
        self.assertEqual(preset["settings"]["format"], "landscape")

        updated = db.update_preset(
            preset["id"],
            description="Updated description",
            settings={"format": "portrait"},
            db_path=self.db_path,
        )
        self.assertEqual(updated["description"], "Updated description")
        self.assertEqual(updated["settings"]["format"], "portrait")

        deleted = db.delete_preset(preset["id"], self.db_path)
        self.assertTrue(deleted)


if __name__ == "__main__":
    unittest.main()
