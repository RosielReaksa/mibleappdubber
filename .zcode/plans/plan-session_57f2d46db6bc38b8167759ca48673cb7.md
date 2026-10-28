# Implementation Plan: Real Video Editor & Server Export Pipeline

## 1. Problem Summary & Objectives
Currently, the Video Editor (`/projects/:id/editor`) runs in **demo mode**:
1. **Frontend Editor Stage:** Displays a static colored gradient box (`LinearGradient`) rather than playing the actual dubbed video.
2. **Frontend Timeline:** Has hardcoded progress (`value: 0.14`) and non-functional play/pause controls.
3. **Backend Export Engine:** `POST /v1/projects/{id}/exports` and `GET /v1/exports/{id}` are missing in `server/main.py`. Tapping "Export" fails with a 404 error, and no real FFmpeg rendering takes place for edit settings.

**Goal:** Turn the editor into a **real working editor** that loads and plays the actual dubbed video, displays live overlays, and renders the edited output on the server via FFmpeg upon export.

---

## 2. Proposed Changes

### A. Frontend (Flutter Mobile App)
1. **Real Video Playback in `EditorScreen` (`dubber_app/lib/features/editor/editor_screen.dart`):**
   - Initialize a `VideoPlayerController` loading `resolveMediaUrl(project.dubbedUrl)`.
   - Update `EditorController` to initialize `trimEnd` to the video's actual duration.
   - Cleanly dispose of the controller on exit.

2. **Live Video Stage in `EditorPreview` (`dubber_app/lib/features/editor/widgets/editor_preview.dart`):**
   - Replace the static gradient placeholder in `_stage` with the live playing video (`vp.VideoPlayer`).
   - If `fitMode == FitMode.blur`, display the live blurred video in the background behind the scaled video.
   - Keep all interactive overlays (text, logo, subtitle sample, blur rectangles, color tint filters) composited over the live video.

3. **Interactive Timeline & Playback Controls in `_Timeline`:**
   - Connect the play/pause button to `_videoController.play()` / `pause()`.
   - Bind the timeline progress bar to `position / duration`.
   - Keep playback clamped to `[trimStart, trimEnd]`.

### B. Backend (Local Python/FastAPI Server)
1. **Database Schema (`server/db.py`):**
   - Add `exports` table: `(id, project_id, status, percent, download_url, settings_json, owner, created_at)`.
   - Add CRUD methods: `create_export()`, `get_export()`, `update_export()`.

2. **Export Endpoints (`server/main.py`):**
   - `POST /v1/projects/{pid}/exports`: Accepts the full `ExportSettings` payload (format, mix, trim, texts, logos, subtitles, blurs, fit, filter), stores the export, and launches an asynchronous background rendering worker.
   - `GET /v1/exports/{eid}`: Returns `{id, status, percent, download_url, reason}` for client polling on the `ExportScreen`.

3. **FFmpeg Export Renderer (`server/engine/export_renderer.py` or within `server/engine/gemini_dubber.py`):**
   - Reads the project's dubbed video file (`dubbed_{pid}.mp4`).
   - **Trim:** Applies `-ss <trimStart> -to <trimEnd>`.
   - **Audio Mix:** Adjusts dubbed voice, original voice, and background music volume levels.
   - **Aspect Ratio & Fit:** Handles conversion between 16:9 Landscape and 9:16 Portrait (generating blurred background or black letterbox bars).
   - **Subtitles:** Burns subtitles using FFmpeg's `subtitles` filter with the project's generated `.srt` file.
   - **Text Overlays:** Draws text with `drawtext` using specified coordinates, font sizes, and colors.
   - **Filters:** Applies color adjustments (warm, cool, mono, vivid, soft).
   - Saves final rendered output to `server/media/export_{export_id}.mp4` and marks export as `done`.

---

## 3. Verification Plan
1. **Unit & Integration Tests:** Run `flutter test` to ensure all 128 tests pass with no regressions.
2. **Server API Test:** Test `POST /v1/projects/{id}/exports` and `GET /v1/exports/{id}` end-to-end using a test video script.
3. **App Verification on Phone:**
   - Open Dubber app on phone.
   - Go to a completed project and tap **Edit video**.
   - Verify the real video plays on the stage.
   - Add text overlay or toggle subtitles.
   - Tap **Export** and verify it progresses to **Video ready** with the download link.