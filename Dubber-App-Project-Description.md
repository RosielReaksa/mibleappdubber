# Dubber Mobile App: Project Description

Version 1.0 · Design phase · Written October 26, 2026

Design mockup (28 screens): https://claude.ai/artifact/Jcc6TxG1fgyqXamhywiw45

---

## 1. What is Dubber?

Dubber is a service that **dubs videos into another language**. The user uploads a video, chooses a language and a voice, and the server makes a new video where the speech is replaced by the dubbed voice.

The Dubber **website and server already exist** (still in development). This project is the **mobile app** (Android and iPhone) for the same service.

**Main idea:** the app is a light "front door". It shows screens and talks to the server. All the heavy work (speech, translation, voice, video) happens **on the server**.

### Goals
- Let a user dub a video from a phone in a few taps.
- Let the user finish the video in a small editor (text, logo, subtitles, blur, audio mix) before export.
- Feel soft, friendly, and simple, with a cute animated character while the user waits.
- Use the same server and the same rules as the website.

### Not goals (for now)
- A full professional video editor like CapCut. We only add tools that help dubbing.
- Many voices. For now there are **2 voices** (female and male). More can be added later.
- Editing video on the phone. The final video is made on the server.

---

## 2. Users

- Creators who make videos for other countries (YouTube, TikTok, Reels, Shorts).
- Small businesses with ads and tutorials.
- Teachers and trainers.

These users usually have a phone, not a computer. They want fast results and few settings.

---

## 3. Main user journey

1. **Start:** first time, the user sees the 4-step Quick guide, then signs up or logs in.
2. **New project:** upload a video or audio file, choose the languages, the video format (Landscape or Portrait), the voice, and the audio mix.
3. **Dubbing:** the server works. The app shows progress with the animated character. The user can close the app and get a notification.
4. **Result:** the user plays the dubbed video and compares it with the original.
5. **Edit (optional):** add text, logo, subtitles, blur, change the audio mix, trim.
6. **Export:** the server renders the final video. The user downloads or shares it.

---

## 4. Features

### 4.1 First version (MVP)
- Sign up, log in, forgot password
- Quick guide for new users
- Projects list with status
- New project: upload, languages, format, voice, audio mix
- Dubbing progress and notification when done
- Result screen with Dubbed / Original switch
- Basic editor: Text, Logo, Subtitles, Trim, Audio, Blur
- Export, download, share
- Credits and buying credits
- Account screen
- Templates and tutorials
- Empty and error screens

### 4.2 Later
- Fit (blurred background when changing Landscape / Portrait)
- Filters (simple color styles)
- Fade in and fade out
- Saved logos and saved text styles (a "Library" tab)
- More voices and more languages
- Edit the voice of one speaker
- "Preview 10 seconds" of the audio mix
- Speed, split clips, stickers, text animation
- Team accounts

### 4.3 Voices
- **Natural female** and **Natural male**.
- **Detect gender automatically:** the server finds each speaker and their gender, then uses the male voice or the female voice for each speaker (good for interviews and talks).
- The voice list must come **from the server** (`GET /voices`), so new voices can be added without updating the app.

### 4.4 Video format
- **Landscape 16:9** and **Portrait 9:16**.
- The user chooses at the start and can change it in the editor.

### 4.5 Audio mix
Three volume sliders (0 to 100%):

| Slider | Default | Meaning |
|---|---|---|
| Dubbed voice | 100% | The new voice |
| Original voice | 15% | The old voice, very quiet under the new one |
| Background music | 80% | The music from the original video |

**Presets:**
- **Replace voice:** original voice off.
- **Voice-over:** original voice low (default).
- **Keep original:** original voice loud.

The mix is saved with the project. The editor must start with the same values the user chose in New project.

> **Important for the server:** to control voice and music separately, the server must **separate the voice from the music** in the original audio (stem separation). It must keep the 3 tracks (dubbed voice, original voice, music) so that changing the mix later is a quick re-mix, not a new dubbing. Changing the mix should **not** cost credits again.

### 4.6 Editor tools

The editor has a bottom tool bar that **scrolls sideways**.

| Tool | What the user can do | Status |
|---|---|---|
| Text | Type text, size, color, position, time | Designed |
| Logo | Upload image, size, opacity, corner position, time | Designed |
| Subtitles | Show/hide, style (Classic, Bold, Box), size | Designed |
| Trim | Set start and end of the video | Designed |
| Audio | The 3 sliders | Designed |
| Blur | Blur or pixelate Top, Bottom, Left, Right (more than one at once) or a free box, thickness, strength, add more | Designed |
| Fit | Blurred background when the format changes | Later |
| Filters | Simple color styles | Later |

**How editing works:** the editor on the phone only shows a **light preview**. When the user taps **Export**, the app sends a small list of settings to the server, and the server makes the final video (see section 7.4). This gives the same result on every phone.

### 4.7 Templates
Ready-made styles (News, Short video, Tutorial, Business ad). A template is only a **list of settings** (format, subtitle style, audio mix, logo position). When the user taps a template, New project opens with those settings filled in. Templates come from the server (`GET /templates`), so new ones can be added without an app update.

### 4.8 Tutorials
- **Quick guide:** 4 steps, shown the first time the app opens and again from the Templates page.
- **Learn page:** list of short guides in groups (Getting started, Editing, Sound and export), with a progress bar and check marks.
- **Guide page:** a video, numbered steps, a "Try it in the editor" button, and "Next guide".
- Guides come from the server (`GET /tutorials`). Progress is saved per user.

### 4.9 Credits and payments
- Dubbing costs credits (the mockup shows "12 credits" as a sample).
- The user can buy credit packs (sample prices only: $5, $12, $35).
- If credits are not enough, the app shows the "Not enough credits" screen.
- **Check the current Apple App Store and Google Play rules.** Selling digital credits inside an app usually must use the store's own billing. The server must verify the purchase receipt.

### 4.10 Notifications
Push notifications when dubbing is done, export is done, or a job failed.

---

## 5. Screens (28)

**Start**
1. Login
2. Sign up
3. Forgot password
4. Quick guide (4 screens)

**Main tabs (bottom menu: Projects, New, Templates, Account)**
5. Projects (list with status)
6. New project (scrolls; the Start dubbing button and the menu stay fixed)
7. Templates
8. Account and credits

**Dubbing and export**
9. Progress (dubbing)
10. Loading with animated character
11. Result
12. Exporting
13. Video ready

**Editor**
14. Editor, Landscape
15. Editor, Portrait
16. Logo tool
17. Subtitles tool
18. Trim tool
19. Audio tool
20. Blur tool

**Tutorials**
21. Learn page
22. Guide page

**Problem states**
23. No projects yet
24. Upload failed
25. Not enough credits

---

## 6. Design system

The style is **soft, warm, and classic**.

### Colors
| Name | Value | Use |
|---|---|---|
| Ivory | `#FAF9F5` | Screen background |
| Ink | `#141413` | Main text, video background |
| Muted | `#66655E` | Second text |
| Clay | `#D97757` | Highlights, progress bar, decoration |
| Clay button | `#B5502D` | Buttons and active tab (white text stays easy to read) |
| Soft clay | `#F6E7DF` | Selected items |
| Oat | `#F0EEE6` | Light areas, thumbnails |
| Border | `#E8E5DA` and `#D9D6CB` | Lines and inputs |
| White | `#FFFFFF` | Cards |
| Done (green) | text `#3F5B2A` on `#E3EBD9` | Done status |
| Working (sand) | text `#7A4A12` on `#F6E7C6` | In progress status |

### Type
- **Headings:** Newsreader (a serif font), weight 500.
- **Body and buttons:** Inter (sans-serif).
- Minimum body text: 14 px. Buttons: 16 px.

### Shapes and spacing
- Cards: radius 20. Buttons and inputs: radius 14. Chips: fully round.
- Main buttons are 52 px high and full width.
- Screen side padding: 20 px.
- Design size in the mockup: 390 × 844 (a normal phone).
- Touch targets are at least 44 px.

### Navigation
- **Bottom menu** with 4 tabs: Projects, New, Templates, Account. Icon plus label.
- The editor has its **own scrolling tool bar** at the bottom.

### The character and loading
- A small clay-colored character with headphones works at a mixing desk. It bobs, blinks, and moves its hands. A small spinning spark floats above its head.
- Friendly messages change every 3 seconds ("Listening to your video…", "Translating the words…", "Teaching the voice to talk…", "Mixing the sound…").
- The same character is used for Exporting, Video ready, empty states, and errors (a worried face for problems).
- **Respect "reduce motion":** if the phone setting is on, stop the animation and show one message.

### Accessibility
- Text contrast of at least 4.5:1.
- Every icon button has a label (for screen readers).
- Do not use color alone to show a state.
- Progress bars use the progress bar role with the current value.

---

## 7. Technology

### 7.1 Mobile app

| Part | Recommendation | Why |
|---|---|---|
| Framework | **Flutter** (or React Native) | One code base for Android and iPhone. The app is mostly screens and server calls. Choose what you or your developer already know. |
| Language | Dart (Flutter) | |
| Server calls | `dio` (HTTP) | Interceptors for tokens, retry, and progress |
| State | Riverpod (or Bloc) | Clean and testable |
| Navigation | `go_router` | Tabs, deep links, back stack |
| Login storage | Secure storage (Keychain / Keystore) | Safe tokens |
| File picker | `file_picker` / `image_picker` | Video, audio, logo image |
| Upload | Chunked and resumable upload | Videos are big and mobile internet drops |
| Video / audio preview | `video_player` (or `chewie`), `just_audio` | Result screen and editor preview |
| Push notifications | Firebase Cloud Messaging | Job finished |
| Purchases | `in_app_purchase` (or RevenueCat) | Credits |
| Local cache | `drift` / `hive` | Project list works with weak internet |
| Crash and logs | Firebase Crashlytics or Sentry | Find problems early |
| Languages (app text) | `intl` | The app itself can be translated |

### 7.2 Server (your existing Dubber server)

| Part | Recommendation |
|---|---|
| API | REST + JSON, versioned (`/v1/...`) |
| Login | Token login (JWT access token + refresh token) |
| Database | PostgreSQL (users, projects, jobs, credits) |
| File storage | Object storage (S3-compatible) with signed URLs |
| Job queue | A queue with workers (for example Redis + a worker system). Dubbing and export are long jobs. |
| Job progress | Polling first (`GET /jobs/{id}`); WebSocket or server events later |
| Video | FFmpeg (burn text, logo, subtitles, blur, trim, mix, format) |
| Notifications | Firebase Cloud Messaging from the server |
| Payments | Verify Apple / Google receipts on the server and add credits |
| Security | HTTPS only, rate limits, file type and size checks, signed URLs that expire |

### 7.3 Dubbing pipeline (on the server)

1. **Upload** and check the file.
2. **Extract audio** from the video.
3. **Separate** the voice from the music (stem separation).
4. **Speech to text** with timing, and **speaker detection with gender** (speaker diarization).
5. **Translate** the text to the target language.
6. **Text to speech** with the chosen voice (female, male, or per speaker by gender).
7. **Match the timing** so the new speech fits the original scenes.
8. **Mix** the dubbed voice, the original voice, and the music with the user's volumes.
9. **Render** the dubbed video and save the separate tracks for later re-mixing.

Each step reports progress so the app can show the steps (Upload, Transcribe, Translate, Generate voice, Mix and export). You can use your own models or outside services for steps 3 to 6.

### 7.4 Editing and export (server-side rendering)

Decision: **editing is done on the server.**

- The app sends only the edit settings.
- The server renders the final video with FFmpeg and returns a download link.
- Benefits: same result on every phone, the editor can be improved without an app update, the website can use the same settings.
- The preview on the phone is only a simple overlay on the video.

---

## 8. API (first draft)

All paths start with `/v1`. All requests (except login and register) need `Authorization: Bearer <token>`.

### Account
| Method | Path | Purpose |
|---|---|---|
| POST | `/auth/register` | Create account |
| POST | `/auth/login` | Log in, returns tokens |
| POST | `/auth/refresh` | New access token |
| POST | `/auth/forgot-password` | Send reset link |
| POST | `/auth/reset-password` | Set new password |
| GET | `/me` | Name, email, credits |
| POST | `/devices` | Save the push notification token |

### Upload
| Method | Path | Purpose |
|---|---|---|
| POST | `/uploads` | Start an upload (file name, size, type) |
| PUT | `/uploads/{id}/parts/{n}` | Send one part (can retry) |
| POST | `/uploads/{id}/complete` | Finish the upload |

### Projects and dubbing
| Method | Path | Purpose |
|---|---|---|
| GET | `/projects` | List projects with status |
| POST | `/projects` | Create a project and start dubbing |
| GET | `/projects/{id}` | One project (links to dubbed and original video) |
| DELETE | `/projects/{id}` | Delete a project |
| GET | `/jobs/{id}` | Status, percent, and current step |
| GET | `/voices` | Available voices (now female and male) |
| GET | `/languages` | Available languages |

### Editing and export
| Method | Path | Purpose |
|---|---|---|
| PUT | `/projects/{id}/mix` | Change the audio mix (quick re-mix, no credits) |
| POST | `/projects/{id}/exports` | Send edit settings, start export |
| GET | `/exports/{id}` | Export status and download link |
| POST | `/assets/logos` | Upload a logo image |
| GET | `/assets/logos` | List saved logos (later) |

### Credits
| Method | Path | Purpose |
|---|---|---|
| GET | `/credits` | Balance and packs |
| GET | `/credits/history` | Payment and usage history |
| POST | `/credits/purchase` | Send the store receipt, add credits |
| POST | `/projects/estimate` | Price in credits before starting |

### Content
| Method | Path | Purpose |
|---|---|---|
| GET | `/templates` | List templates |
| GET | `/tutorials` | List guides in groups |
| POST | `/tutorials/{id}/progress` | Mark a guide as done |

### Job status values
`queued` → `uploading` → `processing` (with a `step`) → `done`, or `failed` (with a clear reason, for example `connection_lost`, `not_enough_credits`, `unsupported_file`).

---

## 9. Data examples

### Create a dubbing project (`POST /projects`)
```json
{
  "upload_id": "up_123",
  "source_language": "en",
  "target_language": "km",
  "format": "landscape",
  "voice": "female",
  "mix": { "dubbed_voice": 100, "original_voice": 15, "music": 80 },
  "template_id": null
}
```
`voice` can be `female`, `male`, or `auto` (detect gender).
`format` can be `landscape` or `portrait`.

### Job status (`GET /jobs/{id}`)
```json
{
  "id": "job_456",
  "status": "processing",
  "step": "generate_voice",
  "percent": 64,
  "steps": ["upload", "transcribe", "translate", "generate_voice", "mix_export"]
}
```

### Export (`POST /projects/{id}/exports`)
```json
{
  "format": "landscape",
  "mix": { "dubbed_voice": 100, "original_voice": 15, "music": 80 },
  "trim": { "start": 5, "end": 80 },
  "texts": [
    { "text": "Welcome to our product", "size": 60, "color": "#FFFFFF",
      "x": 0.5, "y": 0.85, "from": 10, "to": 60 }
  ],
  "logos": [
    { "asset_id": "logo_1", "size": 40, "opacity": 90,
      "position": "top_right", "from": 0, "to": 90 }
  ],
  "subtitles": { "show": true, "style": "classic", "size": 55 },
  "blurs": [
    { "sides": ["top", "bottom"], "thickness": 30, "strength": 60,
      "style": "blur", "from": 0, "to": 90 }
  ]
}
```
Positions use values from 0 to 1 (a share of the video width and height), so they work for any video size.

---

## 10. Screen states and errors

Every screen that loads data needs these states: **loading**, **empty**, **error**, and **offline**.

| Situation | What the user sees |
|---|---|
| No projects | Character + "No projects yet" + Create first project |
| Upload stops | Worried character + "Upload did not finish" + Try again (the upload continues from where it stopped) |
| Not enough credits | "You need 12 credits" + Buy credits |
| Dubbing failed | Clear reason + Try again, and credits are returned |
| No internet | Show saved projects and a calm message |
| Wrong password | Short message under the field |

---

## 11. Quality and safety

- **Privacy:** users upload their own videos. Store them safely, use expiring links, and let the user delete a project and its files.
- **Rights:** the terms must say the user owns or may use the video.
- **Limits:** set a maximum file size (the mockup says 2 GB) and a maximum length. Check the file on the server, not only in the app.
- **Cost control:** the server must show the credit price before starting and must not start a job twice.
- **Speed:** show the list from the saved copy first, then update it.
- **Testing:** test on small and old phones, slow internet, and both Android and iPhone. Test very long videos and videos with more than one speaker.

---

## 12. Plan

| Phase | Work |
|---|---|
| 0. Design | Done: 28 screens in the mockup. Next: Fit, Filters, and the template-to-New-project step. |
| 1. Server API | Write the final API list, build login, upload, project, job status, credits. |
| 2. App base | Choose Flutter or React Native, make the project, build Login, New project, Progress, Result. |
| 3. Editor | Preview, Text, Logo, Subtitles, Audio, Trim, Blur, export job. |
| 4. Money | Credits, store purchases, receipt checks. |
| 5. Content | Templates, tutorials, Quick guide. |
| 6. Polish | Animation, states and errors, accessibility, speed. |
| 7. Test and launch | Beta test, fix, store pages, release. |

---

## 13. Questions to confirm

1. Flutter or React Native? (Choose what the builder already knows.)
2. How many credits does one dubbing cost, and what are the real prices of credit packs?
3. Which languages are available at the start?
4. Maximum video length and file size?
5. Should the original video and dubbed video be kept forever, or deleted after some days?
6. Do users log in with Google or Apple too (on iPhone the App Store may require Sign in with Apple when other social logins exist)?
7. Which payment rules apply for each store, and does the website share the same credits as the app?
8. Who records the tutorial videos, or should the guides use pictures and steps only?

---

## 14. Words used in this document

- **Dubbing:** replacing the speech in a video with speech in another language.
- **Stem separation:** splitting audio into parts, for example voice and music.
- **Speaker diarization:** finding who speaks and when.
- **TTS (text to speech):** making a voice from text.
- **FFmpeg:** a tool that edits video and audio on the server.
- **Job:** a long task on the server (dubbing or export) that the app checks until it is done.
- **Template:** a saved list of settings that a new project can start with.
- **Credits:** the points a user spends to dub a video.
