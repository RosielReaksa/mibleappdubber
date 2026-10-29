"""Regression tests for the queue lifecycle fixes.

A job that is done or failed must leave the waiting list and free its queue
slot, and only the owner can remove an item.
"""

import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import db  # noqa: E402


class QueueLifecycleTests(unittest.TestCase):
    def setUp(self) -> None:
        self.test_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.test_dir, "test.db")
        db.init_db(self.db_path)
        self.email = "lifecycle@dubber.app"
        self.other = "other@dubber.app"
        db.create_user(self.email, "pw", name="Owner", credits=100, db_path=self.db_path)
        db.create_user(self.other, "pw", name="Other", credits=100, db_path=self.db_path)

    def tearDown(self) -> None:
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def _add_project(self, pid: str, email: str) -> None:
        db.create_project(
            {
                "id": pid,
                "title": f"{pid}.mp4",
                "status": "queued",
                "owner": email,
                "mix_json": "{}",
            },
            db_path=self.db_path,
        )
        db.add_queue_item(
            {"project_id": pid, "owner": email}, db_path=self.db_path
        )

    def test_done_project_leaves_waiting_and_frees_slot(self) -> None:
        self._add_project("p_one", self.email)
        now, waiting, failed, slots = db.get_queue(self.email, self.db_path)
        self.assertEqual(len(waiting), 1)
        self.assertEqual(slots, db.MAX_QUEUE_PER_USER - 1)

        db.update_project("p_one", status="processing", db_path=self.db_path)
        now, waiting, failed, slots = db.get_queue(self.email, self.db_path)
        self.assertIsNotNone(now)
        self.assertEqual(len(waiting), 0, "processing job must not also sit in waiting")

        db.update_project(
            "p_one", status="done", percent=100, dubbed_url="/media/x.mp4",
            db_path=self.db_path,
        )
        now, waiting, failed, slots = db.get_queue(self.email, self.db_path)
        self.assertIsNone(now)
        self.assertEqual(len(waiting), 0, "done job must leave the queue")
        self.assertEqual(len(failed), 0)
        self.assertEqual(slots, db.MAX_QUEUE_PER_USER, "slot must be freed")

    def test_failed_project_leaves_queue(self) -> None:
        self._add_project("p_two", self.email)
        db.update_project("p_two", status="failed", failure_reason="boom", db_path=self.db_path)
        now, waiting, failed, slots = db.get_queue(self.email, self.db_path)
        self.assertEqual(len(waiting), 0)
        self.assertEqual(len(failed), 1)
        self.assertEqual(failed[0].get("reason"), "boom", "failure reason must reach the client")

    def test_retry_reenters_waiting_list(self) -> None:
        self._add_project("p_three", self.email)
        db.update_project("p_three", status="failed", db_path=self.db_path)
        db.update_project("p_three", status="queued", db_path=self.db_path)
        _, waiting, _, _ = db.get_queue(self.email, self.db_path)
        self.assertEqual(len(waiting), 1, "retried job must wait again")

    def test_remove_requires_owner(self) -> None:
        self._add_project("p_four", self.email)
        self.assertFalse(db.remove_queue_item("p_four", db_path=self.db_path, owner=self.other))
        self.assertTrue(db.remove_queue_item("p_four", db_path=self.db_path, owner=self.email))
        p = db.get_project("p_four", db_path=self.db_path)
        self.assertIsNone(p)

    def test_done_project_cannot_be_removed_for_refund(self) -> None:
        self._add_project("p_five", self.email)
        db.update_project("p_five", status="done", db_path=self.db_path)
        self.assertFalse(
            db.remove_queue_item("p_five", db_path=self.db_path, owner=self.email),
            "removing a delivered job must be refused so credits cannot be stolen",
        )
        self.assertIsNotNone(db.get_project("p_five", db_path=self.db_path))


if __name__ == "__main__":
    unittest.main()
