"""Dubber SQLite Database & Storage layer.

Handles schema creation, connections, seeding, and all CRUD operations
for users, tokens, projects, queue items, chunked uploads, logos,
styles, and presets.
"""

from __future__ import annotations

import datetime
import hashlib
import json
import os
import sqlite3
import uuid
from contextlib import contextmanager
from typing import Any, Generator

HERE = os.path.dirname(os.path.abspath(__file__))
# DUBBER_DATA_DIR moves all mutable state (db, uploads, engine config) to a
# shared persistent location, e.g. a Modal Volume at /root/data.
DEFAULT_DATA_DIR = os.environ.get("DUBBER_DATA_DIR") or os.path.join(HERE, "data")
DEFAULT_DB_PATH = os.path.join(DEFAULT_DATA_DIR, "dubber.db")
DEFAULT_UPLOAD_DIR = os.path.join(HERE, "uploads")
MAX_QUEUE_PER_USER = 20


def now_iso() -> str:
    """Return current UTC time formatted as ISO 8601 string."""
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def hash_password(password: str) -> str:
    """Hash password using SHA-256."""
    return hashlib.sha256(password.encode("utf-8")).hexdigest()


def verify_password(password: str, password_hash: str) -> bool:
    """Verify password against stored SHA-256 hash or plain-text fallback."""
    return (
        hashlib.sha256(password.encode("utf-8")).hexdigest() == password_hash
        or password == password_hash
    )


def get_connection(db_path: str | None = None) -> sqlite3.Connection:
    """Create and return a configured sqlite3 connection."""
    target_path = db_path or DEFAULT_DB_PATH
    dir_name = os.path.dirname(os.path.abspath(target_path))
    if dir_name:
        os.makedirs(dir_name, exist_ok=True)

    conn = sqlite3.connect(target_path, timeout=30.0, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON;")
    conn.execute("PRAGMA journal_mode = WAL;")
    return conn


@contextmanager
def get_db(db_path: str | None = None) -> Generator[sqlite3.Connection, None, None]:
    """Context manager for database operations with auto commit/rollback."""
    conn = get_connection(db_path)
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def _row_to_dict(row: sqlite3.Row | None) -> dict[str, Any] | None:
    """Convert an sqlite3.Row to a standard Python dictionary."""
    if row is None:
        return None
    return dict(row)


# ── Initialization and Seeding ────────────────────────────────────────────────


def init_db(db_path: str | None = None) -> None:
    """Initialize database tables and seed demo data if absent."""
    with get_db(db_path) as conn:
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS users (
                email TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                password_hash TEXT NOT NULL,
                credits INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS tokens (
                access_token TEXT PRIMARY KEY,
                refresh_token TEXT NOT NULL,
                email TEXT NOT NULL,
                expires_at TEXT NOT NULL,
                FOREIGN KEY (email) REFERENCES users (email) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS idx_tokens_refresh ON tokens (refresh_token);
            CREATE INDEX IF NOT EXISTS idx_tokens_email ON tokens (email);

            CREATE TABLE IF NOT EXISTS projects (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                status TEXT NOT NULL,
                percent INTEGER NOT NULL DEFAULT 0,
                step TEXT,
                source_language TEXT,
                target_language TEXT,
                format TEXT,
                voice TEXT,
                mix_json TEXT,
                dubbed_url TEXT,
                original_url TEXT,
                owner TEXT NOT NULL,
                created_at TEXT NOT NULL,
                started_at TEXT,
                completed_at TEXT,
                upload_id TEXT,
                FOREIGN KEY (owner) REFERENCES users (email) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS idx_projects_owner ON projects (owner);
            CREATE INDEX IF NOT EXISTS idx_projects_status ON projects (status);

            CREATE TABLE IF NOT EXISTS queue_items (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                position INTEGER NOT NULL,
                status TEXT NOT NULL,
                owner TEXT NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY (project_id) REFERENCES projects (id) ON DELETE CASCADE,
                FOREIGN KEY (owner) REFERENCES users (email) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS idx_queue_owner ON queue_items (owner);
            CREATE INDEX IF NOT EXISTS idx_queue_project ON queue_items (project_id);

            CREATE TABLE IF NOT EXISTS uploads (
                id TEXT PRIMARY KEY,
                file_name TEXT NOT NULL,
                size INTEGER NOT NULL DEFAULT 0,
                received INTEGER NOT NULL DEFAULT 0,
                complete INTEGER NOT NULL DEFAULT 0,
                path TEXT,
                owner TEXT NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY (owner) REFERENCES users (email) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS idx_uploads_owner ON uploads (owner);

            CREATE TABLE IF NOT EXISTS logos (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                url TEXT NOT NULL,
                owner TEXT NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY (owner) REFERENCES users (email) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS idx_logos_owner ON logos (owner);

            CREATE TABLE IF NOT EXISTS styles (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                kind TEXT NOT NULL,
                size INTEGER NOT NULL DEFAULT 16,
                color TEXT,
                subtitle_style TEXT,
                owner TEXT NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY (owner) REFERENCES users (email) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS idx_styles_owner ON styles (owner);

            CREATE TABLE IF NOT EXISTS presets (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                description TEXT,
                settings_json TEXT NOT NULL,
                owner TEXT NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY (owner) REFERENCES users (email) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS idx_presets_owner ON presets (owner);
            """
        )

        # Migration: ensure upload_id exists on projects
        try:
            conn.execute("ALTER TABLE projects ADD COLUMN upload_id TEXT;")
        except Exception:
            pass

        # Seed demo user if missing
        cur = conn.cursor()
        cur.execute("SELECT email FROM users WHERE email = ?", ("demo@dubber.app",))
        if cur.fetchone() is None:
            demo_email = "demo@dubber.app"
            demo_created = now_iso()
            cur.execute(
                """
                INSERT INTO users (email, name, password_hash, credits, created_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                (
                    demo_email,
                    "Demo User",
                    hash_password("password123"),
                    120,
                    demo_created,
                ),
            )

            # 2 finished demo projects
            demo_projects = [
                (
                    "p_demo1",
                    "Product demo.mp4",
                    "done",
                    100,
                    "mix_export",
                    "en",
                    "km",
                    "landscape",
                    "female",
                    json.dumps({"dubbed_voice": 100, "original_voice": 15, "music": 80}),
                    "/media/dubbed.mp4",
                    "/media/original.mp4",
                    demo_email,
                    demo_created,
                    demo_created,
                    demo_created,
                ),
                (
                    "p_demo2",
                    "Travel vlog.mp4",
                    "done",
                    100,
                    "mix_export",
                    "en",
                    "es",
                    "landscape",
                    "female",
                    json.dumps({"dubbed_voice": 100, "original_voice": 15, "music": 80}),
                    "/media/dubbed.mp4",
                    "/media/original.mp4",
                    demo_email,
                    demo_created,
                    demo_created,
                    demo_created,
                ),
            ]
            cur.executemany(
                """
                INSERT INTO projects (
                    id, title, status, percent, step, source_language, target_language,
                    format, voice, mix_json, dubbed_url, original_url, owner,
                    created_at, started_at, completed_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                demo_projects,
            )

            # 1 demo logo
            cur.execute(
                """
                INSERT INTO logos (id, name, url, owner, created_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                ("l_demo1", "Acme Brand", "/media/logo.png", demo_email, demo_created),
            )

            # 2 demo styles
            cur.executemany(
                """
                INSERT INTO styles (id, name, kind, size, color, subtitle_style, owner, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    ("s_demo1", "Bold subtitle", "subtitle", 55, "#FFFFFF", "bold", demo_email, demo_created),
                    ("s_demo2", "Yellow headline", "text", 60, "#FFD700", "classic", demo_email, demo_created),
                ],
            )

            # 1 demo preset
            preset_settings = {
                "format": "portrait",
                "subtitles": {"show": True, "style": "bold"},
                "mix": {"dubbed_voice": 100, "original_voice": 0, "music": 75},
                "fit": {"mode": "blur", "blur_strength": 60},
                "logo_position": "top_right",
            }
            cur.execute(
                """
                INSERT INTO presets (id, name, description, settings_json, owner, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    "pr_demo1",
                    "My Shorts Preset",
                    "Your preset",
                    json.dumps(preset_settings),
                    demo_email,
                    demo_created,
                ),
            )


# ── Users CRUD ────────────────────────────────────────────────────────────────


def get_user(email: str, db_path: str | None = None) -> dict[str, Any] | None:
    """Retrieve user dictionary by email."""
    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute("SELECT * FROM users WHERE email = ?", (email,))
        return _row_to_dict(cur.fetchone())


def create_user(
    email: str,
    password: str,
    name: str = "User",
    credits: int = 0,
    db_path: str | None = None,
) -> dict[str, Any]:
    """Create a new user with hashed password."""
    created = now_iso()
    p_hash = hash_password(password)
    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO users (email, name, password_hash, credits, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            (email, name, p_hash, credits, created),
        )
    return {
        "email": email,
        "name": name,
        "password_hash": p_hash,
        "credits": credits,
        "created_at": created,
    }


def update_user_credits(
    email: str, delta: int, db_path: str | None = None
) -> dict[str, Any] | None:
    """Add delta credits to user account (can be negative). Returns updated user."""
    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute(
            "UPDATE users SET credits = credits + ? WHERE email = ?", (delta, email)
        )
        cur.execute("SELECT * FROM users WHERE email = ?", (email,))
        return _row_to_dict(cur.fetchone())


def authenticate_user(
    email: str, password: str, db_path: str | None = None
) -> dict[str, Any] | None:
    """Verify email and password and return newly issued token pair if valid."""
    user = get_user(email, db_path=db_path)
    if not user:
        return None
    if not verify_password(password, user["password_hash"]):
        return None
    tokens = create_token(email, db_path=db_path)
    return {
        "access_token": tokens["access_token"],
        "refresh_token": tokens["refresh_token"],
        "expires_in": 86400 * 30,
        "token_type": "Bearer",
    }


def register_user(
    email: str, password: str, name: str = "User", credits: int = 30, db_path: str | None = None
) -> dict[str, Any]:
    """Create user and return newly issued token pair."""
    create_user(email, password, name=name, credits=credits, db_path=db_path)
    tokens = create_token(email, db_path=db_path)
    return {
        "access_token": tokens["access_token"],
        "refresh_token": tokens["refresh_token"],
        "expires_in": 86400 * 30,
        "token_type": "Bearer",
    }


# ── Tokens CRUD ───────────────────────────────────────────────────────────────


def create_token(
    email: str, expires_in_seconds: int = 86400 * 30, db_path: str | None = None
) -> dict[str, Any]:
    """Generate access and refresh tokens for user and save in DB."""
    access_token = "at_" + uuid.uuid4().hex
    refresh_token = "rt_" + uuid.uuid4().hex
    expires_dt = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(
        seconds=expires_in_seconds
    )
    expires_at = expires_dt.strftime("%Y-%m-%dT%H:%M:%SZ")

    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO tokens (access_token, refresh_token, email, expires_at)
            VALUES (?, ?, ?, ?)
            """,
            (access_token, refresh_token, email, expires_at),
        )

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "email": email,
        "expires_at": expires_at,
    }


def verify_token(token: str, db_path: str | None = None) -> str | None:
    """Verify access token and return associated email if valid and not expired."""
    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute("SELECT * FROM tokens WHERE access_token = ?", (token,))
        row = cur.fetchone()
        if row is None:
            return None
        expires_at_str = row["expires_at"]
        try:
            exp = datetime.datetime.strptime(expires_at_str, "%Y-%m-%dT%H:%M:%SZ").replace(
                tzinfo=datetime.timezone.utc
            )
            if datetime.datetime.now(datetime.timezone.utc) > exp:
                return None
        except Exception:
            pass
        return row["email"]


def refresh_token(
    refresh: str, expires_in_seconds: int = 86400 * 30, db_path: str | None = None
) -> dict[str, Any] | None:
    """Exchange valid refresh token for a newly issued access/refresh token pair."""
    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute("SELECT * FROM tokens WHERE refresh_token = ?", (refresh,))
        row = cur.fetchone()
        if row is None:
            return None

        expires_at_str = row["expires_at"]
        try:
            exp = datetime.datetime.strptime(expires_at_str, "%Y-%m-%dT%H:%M:%SZ").replace(
                tzinfo=datetime.timezone.utc
            )
            if datetime.datetime.now(datetime.timezone.utc) > exp:
                return None
        except Exception:
            pass

        email = row["email"]
        # Delete old token pair
        cur.execute("DELETE FROM tokens WHERE refresh_token = ?", (refresh,))

    return create_token(email, expires_in_seconds=expires_in_seconds, db_path=db_path)


# Alias
refresh_token_pair = refresh_token


# ── Projects CRUD ─────────────────────────────────────────────────────────────


def _format_project(p: dict[str, Any] | None) -> dict[str, Any] | None:
    """Parse JSON fields into structured dicts for app consumption."""
    if p is None:
        return None
    if "mix_json" in p and p["mix_json"]:
        try:
            p["mix"] = json.loads(p["mix_json"])
        except Exception:
            p["mix"] = {}
    elif "mix" not in p:
        p["mix"] = {}
    return p


def list_projects(email: str, db_path: str | None = None) -> list[dict[str, Any]]:
    """List all projects for a specific owner, sorted newest first."""
    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute(
            "SELECT * FROM projects WHERE owner = ? ORDER BY created_at DESC", (email,)
        )
        return [_format_project(dict(row)) for row in cur.fetchall()]


def get_project(project_id: str, db_path: str | None = None) -> dict[str, Any] | None:
    """Retrieve project by ID."""
    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute("SELECT * FROM projects WHERE id = ?", (project_id,))
        row = cur.fetchone()
        return _format_project(_row_to_dict(row))


def create_project(
    project_data: dict[str, Any], db_path: str | None = None
) -> dict[str, Any]:
    """Insert a new project and return the created record."""
    pid = project_data.get("id") or ("p_" + uuid.uuid4().hex[:10])
    title = project_data.get("title") or "Untitled"
    status = project_data.get("status") or "queued"
    percent = int(project_data.get("percent") or 0)
    step = project_data.get("step")
    source_language = project_data.get("source_language") or "en"
    target_language = project_data.get("target_language") or "km"
    fmt = project_data.get("format") or "landscape"
    voice = project_data.get("voice") or "female"

    mix_json = project_data.get("mix_json")
    if mix_json is None and "mix" in project_data:
        mix_json = json.dumps(project_data["mix"])

    dubbed_url = project_data.get("dubbed_url")
    original_url = project_data.get("original_url")
    owner = project_data.get("owner")
    created_at = project_data.get("created_at") or now_iso()
    started_at = project_data.get("started_at")
    completed_at = project_data.get("completed_at")
    upload_id = project_data.get("upload_id")

    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO projects (
                id, title, status, percent, step, source_language, target_language,
                format, voice, mix_json, dubbed_url, original_url, owner,
                created_at, started_at, completed_at, upload_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                pid,
                title,
                status,
                percent,
                step,
                source_language,
                target_language,
                fmt,
                voice,
                mix_json,
                dubbed_url,
                original_url,
                owner,
                created_at,
                started_at,
                completed_at,
                upload_id,
            ),
        )

    return get_project(pid, db_path=db_path)  # type: ignore


def update_project(
    project_id: str, db_path: str | None = None, **fields: Any
) -> dict[str, Any] | None:
    """Update fields for a project dynamically."""
    if not fields:
        return get_project(project_id, db_path=db_path)

    if "mix" in fields:
        fields["mix_json"] = json.dumps(fields.pop("mix"))

    keys = list(fields.keys())
    values = [fields[k] for k in keys]
    set_clause = ", ".join(f"{k} = ?" for k in keys)
    values.append(project_id)

    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute(f"UPDATE projects SET {set_clause} WHERE id = ?", tuple(values))

    return get_project(project_id, db_path=db_path)


def delete_project(project_id: str, db_path: str | None = None) -> bool:
    """Delete a project and its associated queue items."""
    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute("DELETE FROM queue_items WHERE project_id = ?", (project_id,))
        cur.execute("DELETE FROM projects WHERE id = ?", (project_id,))
        return cur.rowcount > 0


# ── Queue CRUD ────────────────────────────────────────────────────────────────


def get_queue(
    email: str, db_path: str | None = None
) -> tuple[dict[str, Any] | None, list[dict[str, Any]], list[dict[str, Any]], int]:
    """Retrieve the user's active dubbing job, waiting jobs, failed jobs, and remaining slots."""
    with get_db(db_path) as conn:
        cur = conn.cursor()

        # 1. Active now (processing or uploading)
        cur.execute(
            """
            SELECT p.*, q.id as queue_item_id, q.position as queue_position
            FROM projects p
            LEFT JOIN queue_items q ON p.id = q.project_id
            WHERE p.owner = ? AND p.status IN ('processing', 'uploading')
            ORDER BY p.started_at ASC, p.created_at ASC
            LIMIT 1
            """,
            (email,),
        )
        now_row = cur.fetchone()
        now = _format_project(_row_to_dict(now_row)) if now_row else None
        if now:
            now["position"] = None

        # 2. Waiting (queued)
        cur.execute(
            """
            SELECT p.*, q.id as queue_item_id, q.position as queue_position
            FROM queue_items q
            JOIN projects p ON q.project_id = p.id
            WHERE q.owner = ? AND (q.status = 'queued' OR p.status = 'queued')
            ORDER BY q.position ASC, q.created_at ASC
            """,
            (email,),
        )
        waiting_rows = cur.fetchall()

        if not waiting_rows:
            cur.execute(
                """
                SELECT p.*, NULL as queue_item_id, NULL as queue_position
                FROM projects p
                WHERE p.owner = ? AND p.status = 'queued'
                ORDER BY p.created_at ASC
                """,
                (email,),
            )
            waiting_rows = cur.fetchall()

        waiting = [_format_project(_row_to_dict(r)) for r in waiting_rows]
        for idx, p in enumerate(waiting, start=1):
            p["position"] = idx

        # 3. Failed
        cur.execute(
            """
            SELECT p.*, NULL as queue_item_id, NULL as queue_position
            FROM projects p
            WHERE p.owner = ? AND p.status = 'failed'
            ORDER BY p.created_at DESC
            """,
            (email,),
        )
        failed = [_format_project(_row_to_dict(r)) for r in cur.fetchall()]

        slots_left = max(0, MAX_QUEUE_PER_USER - (1 if now else 0) - len(waiting))

    return now, waiting, failed, slots_left


def add_queue_item(
    item_data: dict[str, Any], db_path: str | None = None
) -> dict[str, Any]:
    """Add an item to the queue_items table and ensure position is sequential."""
    item_id = item_data.get("id") or ("qi_" + uuid.uuid4().hex[:10])
    project_id = item_data["project_id"]
    owner = item_data["owner"]
    status = item_data.get("status") or "queued"
    created_at = item_data.get("created_at") or now_iso()

    with get_db(db_path) as conn:
        cur = conn.cursor()

        # Ensure project exists
        cur.execute("SELECT id FROM projects WHERE id = ?", (project_id,))
        if cur.fetchone() is None:
            cur.execute(
                """
                INSERT INTO projects (
                    id, title, status, percent, step, source_language, target_language,
                    format, voice, owner, created_at
                ) VALUES (?, ?, ?, 0, 'upload', 'en', 'km', 'landscape', 'female', ?, ?)
                """,
                (
                    project_id,
                    item_data.get("title") or "Video",
                    status,
                    owner,
                    created_at,
                ),
            )
        else:
            cur.execute(
                "UPDATE projects SET status = ? WHERE id = ?", (status, project_id)
            )

        pos = item_data.get("position")
        if pos is None:
            cur.execute(
                "SELECT COALESCE(MAX(position), 0) + 1 FROM queue_items WHERE owner = ?",
                (owner,),
            )
            pos = cur.fetchone()[0]

        cur.execute(
            """
            INSERT INTO queue_items (id, project_id, position, status, owner, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (item_id, project_id, pos, status, owner, created_at),
        )

    return {
        "id": item_id,
        "project_id": project_id,
        "position": pos,
        "status": status,
        "owner": owner,
        "created_at": created_at,
    }


def move_queue_item(
    item_id: str, to: int | str = 1, db_path: str | None = None
) -> bool:
    """Move a queue item (identified by queue_item.id or project_id) to target position."""
    target_pos = 1 if to in ("top", 1, 0, "1") else int(to)

    with get_db(db_path) as conn:
        cur = conn.cursor()
        # Find item
        cur.execute(
            "SELECT * FROM queue_items WHERE id = ? OR project_id = ?",
            (item_id, item_id),
        )
        target = cur.fetchone()
        if target is None:
            return False

        owner = target["owner"]
        actual_id = target["id"]

        # Get all queue items for owner ordered by position
        cur.execute(
            "SELECT id FROM queue_items WHERE owner = ? ORDER BY position ASC, created_at ASC",
            (owner,),
        )
        item_ids = [r[0] for r in cur.fetchall()]

        if actual_id in item_ids:
            item_ids.remove(actual_id)
            insert_idx = max(0, min(target_pos - 1, len(item_ids)))
            item_ids.insert(insert_idx, actual_id)

            for new_pos, qid in enumerate(item_ids, start=1):
                cur.execute(
                    "UPDATE queue_items SET position = ? WHERE id = ?", (new_pos, qid)
                )

        return True


def reorder_queue(
    email: str, id_list: list[str], db_path: str | None = None
) -> bool:
    """Reorder queue items for owner according to id_list (handles item or project IDs)."""
    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute(
            "SELECT id, project_id FROM queue_items WHERE owner = ? ORDER BY position ASC",
            (email,),
        )
        rows = cur.fetchall()
        id_map = {r["id"]: r["id"] for r in rows}
        proj_map = {r["project_id"]: r["id"] for r in rows}

        ordered_qids = []
        for x in id_list:
            if x in id_map:
                ordered_qids.append(x)
            elif x in proj_map:
                ordered_qids.append(proj_map[x])

        all_qids = [r["id"] for r in rows]
        for qid in all_qids:
            if qid not in ordered_qids:
                ordered_qids.append(qid)

        for pos, qid in enumerate(ordered_qids, start=1):
            cur.execute(
                "UPDATE queue_items SET position = ? WHERE id = ?", (pos, qid)
            )

        return True


def remove_queue_item(item_id: str, db_path: str | None = None) -> bool:
    """Remove a queue item by queue_item.id or project_id and re-sequence positions."""
    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute(
            "SELECT id, project_id, owner FROM queue_items WHERE id = ? OR project_id = ?",
            (item_id, item_id),
        )
        row = cur.fetchone()
        if row is None:
            cur.execute("SELECT id, owner, status FROM projects WHERE id = ?", (item_id,))
            prow = cur.fetchone()
            if prow and prow["status"] in ("queued", "uploading", "processing", "failed"):
                cur.execute("DELETE FROM projects WHERE id = ?", (item_id,))
                return True
            return False

        owner = row["owner"]
        actual_id = row["id"]
        proj_id = row["project_id"]

        cur.execute("DELETE FROM queue_items WHERE id = ?", (actual_id,))
        cur.execute(
            "DELETE FROM projects WHERE id = ? AND status IN ('queued', 'uploading', 'processing', 'failed')",
            (proj_id,),
        )

        # Re-sequence remaining
        cur.execute(
            "SELECT id FROM queue_items WHERE owner = ? ORDER BY position ASC, created_at ASC",
            (owner,),
        )
        remaining = [r[0] for r in cur.fetchall()]
        for pos, qid in enumerate(remaining, start=1):
            cur.execute(
                "UPDATE queue_items SET position = ? WHERE id = ?", (pos, qid)
            )

        return True


# ── Uploads CRUD ──────────────────────────────────────────────────────────────


def _format_upload(u: dict[str, Any] | None) -> dict[str, Any] | None:
    if u is None:
        return None
    u["complete"] = bool(u.get("complete", 0))
    return u


def create_upload(
    upload_data: dict[str, Any], db_path: str | None = None
) -> dict[str, Any]:
    """Register a new chunked upload record."""
    uid = upload_data.get("id") or ("up_" + uuid.uuid4().hex[:10])
    file_name = upload_data.get("file_name") or "upload.mp4"
    size = int(upload_data.get("size") or 0)
    received = int(upload_data.get("received") or 0)
    complete = 1 if upload_data.get("complete") else 0
    owner = upload_data["owner"]
    created_at = upload_data.get("created_at") or now_iso()

    path = upload_data.get("path")
    if not path:
        upload_dir = (
            os.path.join(os.path.dirname(os.path.abspath(db_path)), "uploads")
            if db_path and db_path != ":memory:"
            else DEFAULT_UPLOAD_DIR
        )
        os.makedirs(upload_dir, exist_ok=True)
        path = os.path.join(upload_dir, f"{uid}.bin")

    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO uploads (id, file_name, size, received, complete, path, owner, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (uid, file_name, size, received, complete, path, owner, created_at),
        )

    return get_upload(uid, db_path=db_path)  # type: ignore


def get_upload(upload_id: str, db_path: str | None = None) -> dict[str, Any] | None:
    """Retrieve upload record by ID."""
    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute("SELECT * FROM uploads WHERE id = ?", (upload_id,))
        return _format_upload(_row_to_dict(cur.fetchone()))


def append_upload_part(
    upload_id: str, data: bytes, db_path: str | None = None
) -> dict[str, Any] | None:
    """Append byte chunks to the upload target file on disk and increment received counter."""
    upload = get_upload(upload_id, db_path=db_path)
    if upload is None:
        return None

    path = upload["path"]
    if path:
        dir_name = os.path.dirname(os.path.abspath(path))
        if dir_name:
            os.makedirs(dir_name, exist_ok=True)
        with open(path, "ab") as f:
            f.write(data)

    new_received = upload["received"] + len(data)
    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute(
            "UPDATE uploads SET received = ? WHERE id = ?", (new_received, upload_id)
        )

    return get_upload(upload_id, db_path=db_path)


def complete_upload(
    upload_id: str, db_path: str | None = None
) -> dict[str, Any] | None:
    """Mark an upload as complete."""
    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute("UPDATE uploads SET complete = 1 WHERE id = ?", (upload_id,))

    return get_upload(upload_id, db_path=db_path)


# ── Logos CRUD ────────────────────────────────────────────────────────────────


def list_logos(email: str, db_path: str | None = None) -> list[dict[str, Any]]:
    """List all logos owned by email, newest first."""
    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute(
            "SELECT * FROM logos WHERE owner = ? ORDER BY created_at DESC", (email,)
        )
        return [_row_to_dict(r) for r in cur.fetchall()]  # type: ignore


def create_logo(
    logo_data: dict[str, Any], db_path: str | None = None
) -> dict[str, Any]:
    """Create a new logo record."""
    lid = logo_data.get("id") or ("logo_" + uuid.uuid4().hex[:10])
    name = (logo_data.get("name") or "Logo").strip()
    url = logo_data.get("url") or ""
    owner = logo_data["owner"]
    created_at = logo_data.get("created_at") or now_iso()

    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO logos (id, name, url, owner, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            (lid, name, url, owner, created_at),
        )

    return {
        "id": lid,
        "name": name,
        "url": url,
        "owner": owner,
        "created_at": created_at,
    }


def update_logo(
    logo_id: str,
    name: str | None = None,
    url: str | None = None,
    db_path: str | None = None,
    **fields: Any,
) -> dict[str, Any] | None:
    """Update name and/or url of a logo."""
    updates: dict[str, Any] = {}
    if name is not None:
        updates["name"] = name
    if url is not None:
        updates["url"] = url
    updates.update(fields)

    if not updates:
        with get_db(db_path) as conn:
            cur = conn.cursor()
            cur.execute("SELECT * FROM logos WHERE id = ?", (logo_id,))
            return _row_to_dict(cur.fetchone())

    keys = list(updates.keys())
    values = [updates[k] for k in keys]
    set_clause = ", ".join(f"{k} = ?" for k in keys)
    values.append(logo_id)

    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute(f"UPDATE logos SET {set_clause} WHERE id = ?", tuple(values))
        cur.execute("SELECT * FROM logos WHERE id = ?", (logo_id,))
        return _row_to_dict(cur.fetchone())


def delete_logo(logo_id: str, db_path: str | None = None) -> bool:
    """Delete logo by ID."""
    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute("DELETE FROM logos WHERE id = ?", (logo_id,))
        return cur.rowcount > 0


# ── Styles CRUD ───────────────────────────────────────────────────────────────


def list_styles(email: str, db_path: str | None = None) -> list[dict[str, Any]]:
    """List all custom styles owned by email, newest first."""
    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute(
            "SELECT * FROM styles WHERE owner = ? ORDER BY created_at DESC", (email,)
        )
        return [_row_to_dict(r) for r in cur.fetchall()]  # type: ignore


def create_style(
    style_data: dict[str, Any], db_path: str | None = None
) -> dict[str, Any]:
    """Create a new style record."""
    sid = style_data.get("id") or ("sty_" + uuid.uuid4().hex[:10])
    name = (style_data.get("name") or "Style").strip()
    kind = style_data.get("kind") or "subtitle"
    size = int(style_data.get("size") or 16)
    color = style_data.get("color") or "#FFFFFF"
    subtitle_style = style_data.get("subtitle_style") or "classic"
    owner = style_data["owner"]
    created_at = style_data.get("created_at") or now_iso()

    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO styles (id, name, kind, size, color, subtitle_style, owner, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (sid, name, kind, size, color, subtitle_style, owner, created_at),
        )

    return {
        "id": sid,
        "name": name,
        "kind": kind,
        "size": size,
        "color": color,
        "subtitle_style": subtitle_style,
        "owner": owner,
        "created_at": created_at,
    }


def update_style(
    style_id: str, db_path: str | None = None, **fields: Any
) -> dict[str, Any] | None:
    """Update fields for a style."""
    if not fields:
        with get_db(db_path) as conn:
            cur = conn.cursor()
            cur.execute("SELECT * FROM styles WHERE id = ?", (style_id,))
            return _row_to_dict(cur.fetchone())

    keys = list(fields.keys())
    values = [fields[k] for k in keys]
    set_clause = ", ".join(f"{k} = ?" for k in keys)
    values.append(style_id)

    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute(f"UPDATE styles SET {set_clause} WHERE id = ?", tuple(values))
        cur.execute("SELECT * FROM styles WHERE id = ?", (style_id,))
        return _row_to_dict(cur.fetchone())


def delete_style(style_id: str, db_path: str | None = None) -> bool:
    """Delete a style by ID."""
    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute("DELETE FROM styles WHERE id = ?", (style_id,))
        return cur.rowcount > 0


# ── Presets CRUD ──────────────────────────────────────────────────────────────


def _format_preset(p: dict[str, Any] | None) -> dict[str, Any] | None:
    if p is None:
        return None
    if "settings_json" in p and p["settings_json"]:
        try:
            p["settings"] = json.loads(p["settings_json"])
        except Exception:
            p["settings"] = {}
    elif "settings" not in p:
        p["settings"] = {}
    return p


def list_presets(email: str, db_path: str | None = None) -> list[dict[str, Any]]:
    """List all presets owned by email, newest first."""
    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute(
            "SELECT * FROM presets WHERE owner = ? ORDER BY created_at DESC", (email,)
        )
        return [_format_preset(_row_to_dict(r)) for r in cur.fetchall()]  # type: ignore


def create_preset(
    preset_data: dict[str, Any], db_path: str | None = None
) -> dict[str, Any]:
    """Create a new preset record."""
    pid = preset_data.get("id") or ("pre_" + uuid.uuid4().hex[:10])
    name = (preset_data.get("name") or "Preset").strip()
    description = preset_data.get("description") or ""
    settings_json = preset_data.get("settings_json")
    if settings_json is None and "settings" in preset_data:
        settings_json = json.dumps(preset_data["settings"])
    elif settings_json is None:
        settings_json = "{}"

    owner = preset_data["owner"]
    created_at = preset_data.get("created_at") or now_iso()

    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO presets (id, name, description, settings_json, owner, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (pid, name, description, settings_json, owner, created_at),
        )

    return _format_preset(
        {
            "id": pid,
            "name": name,
            "description": description,
            "settings_json": settings_json,
            "owner": owner,
            "created_at": created_at,
        }
    )  # type: ignore


def update_preset(
    preset_id: str, db_path: str | None = None, **fields: Any
) -> dict[str, Any] | None:
    """Update fields for a preset."""
    if not fields:
        with get_db(db_path) as conn:
            cur = conn.cursor()
            cur.execute("SELECT * FROM presets WHERE id = ?", (preset_id,))
            return _format_preset(_row_to_dict(cur.fetchone()))

    if "settings" in fields:
        fields["settings_json"] = json.dumps(fields.pop("settings"))

    keys = list(fields.keys())
    values = [fields[k] for k in keys]
    set_clause = ", ".join(f"{k} = ?" for k in keys)
    values.append(preset_id)

    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute(f"UPDATE presets SET {set_clause} WHERE id = ?", tuple(values))
        cur.execute("SELECT * FROM presets WHERE id = ?", (preset_id,))
        return _format_preset(_row_to_dict(cur.fetchone()))


def delete_preset(preset_id: str, db_path: str | None = None) -> bool:
    """Delete a preset by ID."""
    with get_db(db_path) as conn:
        cur = conn.cursor()
        cur.execute("DELETE FROM presets WHERE id = ?", (preset_id,))
        return cur.rowcount > 0


if __name__ == "__main__":
    init_db()
    print(f"Database initialized successfully at {DEFAULT_DB_PATH}")
