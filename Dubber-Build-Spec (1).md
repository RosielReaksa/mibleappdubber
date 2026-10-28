# Dubber Mobile App: Build Spec for the Coding Agent

Version 1.1 · Build phase · October 26, 2026

You are building the **Dubber mobile app** (Android + iPhone). Read this whole file before writing code. Build in the phase order in section 14. Finish and test each phase before the next.

---

## 1. Product in one paragraph

Dubber dubs a video into another language. The user uploads a video or audio file, picks languages, format (Landscape/Portrait), voice, and audio mix. The **server** does all heavy work (speech to text, translation, text to speech, mixing, rendering). The app is a light client: it shows screens, uploads files, polls job status, shows a light preview, and sends edit settings to the server. The Dubber website and server **already exist** and are still in development.

## 2. Hard rules

1. **No heavy work on the phone.** No FFmpeg, no AI models, no video rendering on device. The editor preview is only an overlay on top of a `video_player`.
2. **Server decides, app displays.** Voices, languages, templates, tutorials and credit packs all come from the API. Never hardcode them (except safe fallbacks, section 9).
3. **Editing = send a settings object** to `POST /projects/{id}/exports`. The server renders with FFmpeg.
4. **Changing the audio mix never costs credits** (`PUT /projects/{id}/mix`).
5. **All positions are fractions 0 to 1** of video width/height, never pixels.
6. Every screen that loads data has four states: **loading, empty, error, offline**.
7. Respect **reduce motion**. Contrast at least 4.5:1. Every icon button has a semantic label. Touch targets at least 44 px. Never use color alone to show a state.
8. **Do not invent API fields.** If the server differs from section 7, adapt the data layer only (section 4) and tell the user what changed.
9. All user-facing text lives in `intl` ARB files (English first). No strings inside widgets.

## 3. Tech stack (fixed)

| Part | Choice |
|---|---|
| Framework | **Flutter** (stable), Dart null-safe |
| HTTP | `dio` with interceptors (auth, refresh, retry, logging) |
| State | `flutter_riverpod` (+ `riverpod_generator`) |
| Navigation | `go_router` (ShellRoute for tabs) |
| Models | `freezed` + `json_serializable` |
| Secure storage | `flutter_secure_storage` (tokens) |
| Local cache | `drift` (projects list, offline) |
| File pick | `file_picker`, `image_picker` |
| Video / audio | `video_player`, `just_audio` |
| Push | `firebase_messaging` + `flutter_local_notifications` |
| Purchases | `in_app_purchase` (RevenueCat is an allowed swap) |
| Crash | `sentry_flutter` (or Crashlytics) |
| i18n | `flutter_localizations` + `intl` |
| Animation | `rive` or `lottie` for the character (fallback: Flutter `CustomPainter`) |
| Fonts | Newsreader (500) for headings, Inter for body. Bundle both as assets. |
| Tests | `flutter_test`, `mocktail`, `integration_test` |

Min versions: Android 8.0 (API 26), iOS 15.

## 4. Architecture

Feature-first folders, clean layers: **data → domain → presentation**.

```
lib/
  main.dart
  app/                 # app widget, router, theme, l10n
  core/
    api/               # dio client, interceptors, api_error.dart
    storage/           # secure storage, drift db
    utils/             # formatters, debouncer, result type
    widgets/           # shared UI: PrimaryButton, StatusChip, Character, ErrorView, EmptyView
  features/
    auth/              # login, signup, forgot, session
    onboarding/        # quick guide
    projects/          # list, detail, delete
    new_project/       # form, upload, estimate, create
    jobs/              # progress, loading, polling
    result/            # player, dubbed/original switch
    editor/            # tools, preview overlay, export settings
    export/            # exporting, video ready, download, share
    credits/           # balance, packs, purchase, not-enough
    account/
    templates/
    tutorials/         # learn page, guide page
    notifications/
  l10n/
test/
integration_test/
```

Rules:
- Widgets never call `dio` directly. Widget → Riverpod controller → repository → API client.
- Repositories return typed models or a typed `ApiError`. No raw maps in UI.
- One `ApiError` type: `code`, `message`, `httpStatus`, `retryable`.

## 5. Design system (tokens)

Create `app/theme/tokens.dart`. Do not use any other colors.

| Token | Value | Use |
|---|---|---|
| ivory | `#FAF9F5` | Screen background |
| ink | `#141413` | Main text, video background |
| muted | `#66655E` | Second text |
| clay | `#D97757` | Highlights, progress fill, decoration |
| clayButton | `#B5502D` | Buttons, active tab (white text) |
| softClay | `#F6E7DF` | Selected items |
| oat | `#F0EEE6` | Light areas, thumbnails |
| border | `#E8E5DA` / `#D9D6CB` | Lines, inputs |
| white | `#FFFFFF` | Cards |
| doneText / doneBg | `#3F5B2A` / `#E3EBD9` | Done status |
| workingText / workingBg | `#7A4A12` / `#F6E7C6` | In-progress status |

Type: headings Newsreader w500; body/buttons Inter. Body min 14 sp. Buttons 16 sp w600.
Shape: cards radius 20, buttons/inputs radius 14, chips fully round. Main button: 52 high, full width. Side padding 20. Design frame 390 x 844.

Status chips (always icon + text, not only color): `queued`, `working`, `done`, `failed`.

### The character
A small clay character with headphones at a mixing desk. It bobs, blinks, moves hands, with a spinning spark. Used on: Loading, Exporting, Video ready, empty states, errors (worried face).
- Loading messages rotate every 3 s: "Listening to your video…", "Translating the words…", "Teaching the voice to talk…", "Mixing the sound…".
- If `MediaQuery.disableAnimations` is true: no animation, show one static message.

## 6. Navigation

Bottom tabs (icon + label): **Projects, New, Templates, Account**.

```
/splash                     # decide: onboarding | login | home
/onboarding                 # Quick guide, 4 pages
/login  /signup  /forgot
/projects                   # tab 1
/projects/:id               # opens Progress, Result, or Failed by status
/projects/:id/result
/projects/:id/editor        # tool state is local, not a route
/projects/:id/export/:exportId
/new                        # tab 2   (accepts ?template=<id>)
/templates                  # tab 3
/account                    # tab 4
/account/credits
/learn   /learn/:guideId
```

- First launch: Quick guide, then Sign up/Login. Save a `seenOnboarding` flag. Quick guide is reachable again from Templates.
- Auth guard: no valid refresh token → `/login`.
- Deep link from push notification → `/projects/:id`.

## 7. API contract

Base: `https://<server>/v1`. JSON. Header `Authorization: Bearer <access>` on everything except login/register/forgot/reset. Make the base URL a build-time config (`--dart-define=API_BASE`).

### 7.1 Auth and account
| Method | Path | Notes |
|---|---|---|
| POST | `/auth/register` | name, email, password |
| POST | `/auth/login` | returns `access_token`, `refresh_token` |
| POST | `/auth/refresh` | on 401, once, then retry the request |
| POST | `/auth/forgot-password` | email |
| POST | `/auth/reset-password` | token, new password |
| GET | `/me` | name, email, credits |
| POST | `/devices` | FCM token + platform |

Token rule: the dio interceptor refreshes once on 401, queues parallel requests during the refresh, and logs the user out if refresh fails.

### 7.2 Upload (chunked, resumable)
1. `POST /uploads` `{file_name, size, mime}` → `{id, part_size, parts}`
2. `PUT /uploads/{id}/parts/{n}` raw bytes, retry up to 5 times with backoff
3. `POST /uploads/{id}/complete` → `{upload_id}`

Persist `{upload id, last completed part}` locally so an interrupted upload **continues from where it stopped** (Upload failed screen → "Try again").
Pre-check on device: type is video/audio, size ≤ server limit (default 2 GB until the server says otherwise). The server checks again.

### 7.3 Projects and jobs
| Method | Path | Notes |
|---|---|---|
| GET | `/projects` | list with status |
| POST | `/projects` | create and start dubbing |
| GET | `/projects/{id}` | links to dubbed and original video |
| DELETE | `/projects/{id}` | deletes files too |
| GET | `/jobs/{id}` | status, percent, step |
| GET | `/voices` | now `female`, `male` (+ `auto` option in UI) |
| GET | `/languages` | |
| POST | `/projects/estimate` | credits price before start |

`POST /projects` body:
```json
{
  "upload_id": "up_123",
  "source_language": "en",
  "target_language": "km",
  "format": "landscape",
  "voice": "female",
  "mix": { "dubbed_voice": 100, "original_voice": 15, "music": 80 },
  "template_id": null,
  "fit": { "mode": "blur", "blur_strength": 60 },
  "filter": { "name": "none", "strength": 0 },
  "idempotency_key": "<uuid>"
}
```
- `voice`: `female` | `male` | `auto`. `format`: `landscape` | `portrait`.
- Send `idempotency_key` (UUID created when the user opens the form) as a header or body field so a double tap never starts two jobs. If the server lacks it, disable the button after the first tap until the response.

`GET /jobs/{id}`:
```json
{ "id": "job_456", "status": "processing", "step": "generate_voice", "percent": 64,
  "steps": ["upload","transcribe","translate","generate_voice","mix_export"] }
```
Status values: `queued` → `uploading` → `processing` (with `step`) → `done` | `failed` (with `reason`: `connection_lost`, `not_enough_credits`, `unsupported_file`, …).

Polling: every 3 s while the Progress screen is open; every 10 s in the background list; stop on `done`/`failed`. Pause when app is backgrounded (push takes over).

### 7.4 Mix, export, assets
| Method | Path | Notes |
|---|---|---|
| PUT | `/projects/{id}/mix` | quick re-mix, **no credits** |
| POST | `/projects/{id}/exports` | send edit settings |
| GET | `/exports/{id}` | status + `download_url` |
| POST | `/assets/logos` | multipart image |
| GET | `/assets/logos` | later |

Export body (this is the `ExportSettings` model):
```json
{
  "format": "landscape",
  "mix": { "dubbed_voice": 100, "original_voice": 15, "music": 80 },
  "trim": { "start": 5, "end": 80 },
  "texts": [{ "text": "Welcome", "size": 60, "color": "#FFFFFF",
              "x": 0.5, "y": 0.85, "from": 10, "to": 60 }],
  "logos": [{ "asset_id": "logo_1", "size": 40, "opacity": 90,
              "position": "top_right", "from": 0, "to": 90 }],
  "subtitles": { "show": true, "style": "classic", "size": 55 },
  "blurs": [{ "sides": ["top","bottom"], "thickness": 30, "strength": 60,
              "style": "blur", "from": 0, "to": 90 }],
  "fit": { "mode": "blur", "blur_strength": 60 },
  "filter": { "name": "warm", "strength": 70 }
}
```
Enums: subtitle `style` = `classic|bold|box`; blur `style` = `blur|pixelate`; blur `sides` ⊂ `top|bottom|left|right` (or a free box `{x,y,w,h}`); logo `position` = `top_left|top_right|bottom_left|bottom_right`; fit `mode` = `blur|bars|fill`; filter `name` = `none|warm|cool|mono|vivid|soft`. Times are seconds. `fit` only matters when the export `format` differs from the source format.

### 7.5 Credits and content
| Method | Path | Notes |
|---|---|---|
| GET | `/credits` | balance + packs |
| GET | `/credits/history` | |
| POST | `/credits/purchase` | store receipt → add credits |
| GET | `/templates` | list |
| GET | `/tutorials` | grouped guides |
| POST | `/tutorials/{id}/progress` | mark done |

Template item (a template is only settings):
```json
{ "id": "tpl_short", "name": "Short video", "description": "For Reels, Shorts and TikTok.",
  "settings": { "format": "portrait",
    "subtitles": { "show": true, "style": "bold" },
    "mix": { "dubbed_voice": 100, "original_voice": 15, "music": 80 },
    "fit": { "mode": "blur", "blur_strength": 60 },
    "logo_position": "top_right" } }
```

### 7.6 Server requirement to confirm with the user
The server must keep **3 separate tracks** (dubbed voice, original voice, music) via stem separation so `PUT /mix` is a fast re-mix. If it does not, tell the user before building the Audio tool.

## 8. Screens (build exactly as the mockup)

IDs below are the mockup titles. Behavior notes only; copy layout from the mockups.

### Start
- **Login:** email, password, "Forgot password?", button, link to Sign up. Wrong password: short message under the field. Loading state on the button.
- **Sign up:** name, email, password (show/hide), terms checkbox (the terms say the user owns or may use the video).
- **Forgot password:** email, send link, success message.
- **Quick guide (4 pages):** swipe or Next, Skip. Last page → Sign up.
- Social login (Google/Apple): **not in v1** until the user answers question 6 in section 15. Leave an `AuthProvider` interface so it can be added.

### Main tabs
- **Projects:** list from local cache first, then refresh. Each row: thumbnail, title, languages, status chip, date. Pull to refresh. Swipe or menu → Delete (confirm). Empty → **No projects yet** (character + "Create first project"). Offline → show cached list + calm banner.
- **New project** (scrolls; Start button and tab bar stay fixed):
  - File picker (video/audio), shows name + size + a progress bar while uploading.
  - From / To language (from `/languages`).
  - Format chips: Landscape, Portrait.
  - Voice: Female, Male, Auto-detect (detect gender per speaker).
  - Audio mix: 3 sliders (Dubbed voice 100, Original voice 15, Music 80) + presets **Replace voice** (original 0), **Voice-over** (default), **Keep original** (original loud, e.g. 70).
  - Button text: `Start dubbing · N credits` where N comes from `POST /projects/estimate` (re-estimate when file/format/voice changes, debounced 400 ms).
  - Not enough credits → **Not enough credits** screen with "You need N credits" and **Buy credits**.
  - **From a template:** route `/new?template=<id>`. Prefill format, mix, subtitle style, fit, logo position. Show the banner "Short video · Settings filled in for you · Change". Fields stay editable; fields set by the template show a small "From template" tag. "Change" returns to Templates. If the user changes a field, keep the banner but remove that tag.
- **Templates:** grid of templates + link "Quick guide" + link to Learn page. Tap a template → **bottom sheet** (name, description, settings list: Format, Subtitles, Audio mix, Fit, Logo) with **Use this template** → `/new?template=<id>`.
- **Account:** name, email, credits, Buy credits, history, sign out, delete account (confirm), app version.

### Dubbing and export
- **Progress:** 5 steps (Upload, Transcribe, Translate, Generate voice, Mix and export), percent, "You can close the app. We'll tell you when it's done."
- **Loading with character:** combine with Progress (character + rotating messages + progress bar role with value).
- **Result:** video player, **Dubbed / Original** switch (keeps playback position), buttons **Edit** and **Export now**.
- **Exporting:** character + progress (poll `/exports/{id}`).
- **Video ready:** character, player, **Download** (save to gallery), **Share** (system sheet), **Edit again**.
- Failures: clear reason + Try again; credits are returned (server side). Show "Credits returned".

### Editor (Landscape and Portrait variants)
Layout: top bar (Back, title, **Export**), preview area (ink background), tool panel, **horizontally scrolling tool bar**:
`Text · Logo · Subtitles · Trim · Audio · Blur · Fit · Filters`

All tools edit one local `EditorState` (Riverpod) that maps 1:1 to `ExportSettings`. The preview draws overlays with Flutter widgets. It never re-encodes.

| Tool | Controls | Preview |
|---|---|---|
| Text | text input, size, color, position (drag), time range | drag-able overlay |
| Logo | upload image (`POST /assets/logos`), size, opacity, corner, time range | overlay |
| Subtitles | show/hide, style (Classic/Bold/Box), size | sample line overlay |
| Trim | start/end handles on a timeline | clamps playback |
| Audio | 3 sliders + 3 presets; **starts with the project's saved mix**; saves with `PUT /mix` (debounced, no credits) | plays the dubbed track with simple volume where possible |
| Blur | sides Top/Bottom/Left/Right (multi-select) or free box, thickness, strength, style blur/pixelate, "add more" | blurred overlay boxes |
| **Fit** | shown when the export format differs from the source. Options: **Blurred background**, **Black bars**, **Fill screen** + blur strength slider (only for Blurred) | simulate: background layer + centered video |
| **Filters** | None, Warm, Cool, Mono, Vivid, Soft, strength slider | apply a `ColorFilter.matrix` to the video widget |

- Format switch (Landscape/Portrait) in the editor changes `format`; Fit appears automatically.
- Filters change colors only; overlays (text, logo, subtitles) keep their colors in the preview and on the server.
- Unsaved changes: confirm dialog on Back.
- Persist the draft `EditorState` per project locally.

### Tutorials
- **Learn page:** groups (Getting started, Editing, Sound and export), progress bar, check marks. From `GET /tutorials`.
- **Guide page:** video or images, numbered steps, **Try it in the editor**, **Next guide**. On finish → `POST /tutorials/{id}/progress`.

### Problem states
- **No projects yet**, **Upload failed** (worried character, "Upload did not finish", Try again resumes), **Not enough credits**.
- Also build: no internet, session expired, server error (generic retry), file too large, unsupported file.

## 9. Fallbacks and offline

- Cache projects, languages, voices, templates, tutorials (drift). Show cache first, then refresh.
- If `/voices` or `/languages` fails and no cache: show an error state, do not guess.
- Offline: browsing cached projects works. Upload and Start are disabled with a clear message.
- Never lose a user's form: keep New project draft in memory and restore after errors.

## 10. Notifications

Register the FCM token with `POST /devices` after login and on token refresh. Push types: dubbing done, export done, job failed. Tap opens `/projects/:id` (or the export). Ask for notification permission **after the first project starts**, with a short reason, not at app launch.

## 11. Credits and payments

- Show balance in Account and in the New project button.
- Packs come from `GET /credits` (never hardcode prices; the mockup's $5/$12/$35 are samples).
- Buy flow: store billing (`in_app_purchase`) → send receipt to `POST /credits/purchase` → refresh balance. Handle pending, cancelled, restored, and failed purchases. Never grant credits on the client.
- **Check current Apple App Store and Google Play rules for selling digital credits before release.** Keep the payment layer behind an interface so it can be swapped.

## 12. Security and privacy

- Tokens only in secure storage. HTTPS only. No logging of tokens or file URLs.
- Signed URLs expire: refetch the project when a link returns 403.
- Delete project → also deletes files on the server.
- Android: request only needed permissions. iOS: add usage descriptions for photos/media.
- Obfuscate release builds. Add certificate pinning only if the user asks.

## 13. Testing

- **Unit:** models/serialization, mix presets, `EditorState → ExportSettings` mapping, template → New project prefill, token refresh interceptor, upload resume logic.
- **Widget:** each screen in loading/empty/error/offline; status chips; reduce-motion behavior.
- **Integration:** login → new project → progress → result → editor → export → video ready, against a mock server.
- **Manual matrix:** small + old Android phone, recent Android, iPhone, slow/dropping network, very long video, multi-speaker video, large text size, screen reader on.
- CI: `flutter analyze`, `flutter test` on every push.

## 14. Build phases (do in order)

Each phase ends with: analyzer clean, tests passing, a short note to the user of what works and what is stubbed.

**Phase 1: Foundation**
Project setup, flavors (dev/prod), theme tokens + fonts, l10n, router + tabs, dio client + auth interceptor, secure storage, `ApiError`, shared widgets (button, chip, character placeholder, empty/error views). *Done when:* app runs on both platforms with empty tab shells and the theme matches the mockup.

**Phase 2: Auth and onboarding**
Splash, Quick guide, Login, Sign up, Forgot password, session handling, `/me`. *Done when:* a user can sign up, log in, restart the app and stay logged in, and refresh works.

**Phase 3: New project and dubbing**
Languages/voices, file pick, chunked resumable upload, estimate, mix sliders + presets, create project (idempotent), Progress with polling, Loading with character, Projects list with cache, delete, empty/error states, Upload failed, Not enough credits. *Done when:* a real dubbing job starts and the app follows it to `done` or `failed`.

**Phase 4: Result, editor, export**
Result with Dubbed/Original switch, editor shell, tools in this order: Audio, Trim, Subtitles, Text, Logo, Blur, **Fit**, **Filters**, then Export, Exporting, Video ready, download, share. *Done when:* a full export from the editor comes back with all settings applied on the server.

**Phase 5: Credits and payments**
Account, balance, history, packs, store purchase + receipt verification, restore purchases.

**Phase 6: Content**
Templates (grid + preview sheet + `/new?template=`), template banner and "From template" tags, Learn page, Guide page, progress.

**Phase 7: Notifications**
FCM, `/devices`, permission timing, deep links.

**Phase 8: Polish**
Final character animation + reduce motion, offline polish, accessibility pass, performance (list scrolling, upload memory), crash reporting, app icon, splash, store assets.

**Phase 9: Test and launch**
Manual matrix, beta (TestFlight + Play internal testing), fixes, store pages, release.

## 15. Open questions (use these defaults, ask the user to confirm)

| # | Question | Default until answered |
|---|---|---|
| 1 | Flutter or React Native | **Flutter** |
| 2 | Credits per dubbing, pack prices | Read from API only |
| 3 | Start languages | Read from `/languages` |
| 4 | Max length / size | 2 GB, length from server |
| 5 | How long files are kept | Show a note only if the server says so |
| 6 | Google / Apple login | Not in v1; keep the provider interface (note: if Google login is added on iPhone, Sign in with Apple is usually required) |
| 7 | Store payment rules, shared credits with website | Server is source of truth for balance |
| 8 | Who records tutorial videos | Guide page supports video **or** pictures + steps |
| 9 | Fit and Filters in v1 | **Yes**, included in Phase 4 |

## 16. Not in scope for now

Speed, split clips, stickers, text animation, fade in/out, saved logos and text styles ("Library" tab), more than 2 voices, editing one speaker's voice, "Preview 10 seconds", team accounts, on-device video editing. Do not build these. Leave clean extension points (for example `ExportSettings` ignores unknown fields).

## 17. Definition of done (whole app)

- All 32 mockup screens exist and match the design tokens.
- Every data screen has loading, empty, error and offline states.
- A user can: sign up → upload → dub → compare Dubbed/Original → edit (all 8 tools) → export → download/share.
- Starting from a template fills New project correctly.
- Audio mix changes never charge credits.
- Notifications open the right project.
- `flutter analyze` is clean and all tests pass.
