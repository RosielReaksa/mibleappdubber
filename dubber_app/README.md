# Dubber — Flutter mobile app

The Dubber mobile app (Android + iPhone). It is a light client: it shows screens,
uploads files, polls job status, shows a light preview, and sends edit settings to
the server. All heavy work (speech to text, translation, text to speech, mixing,
rendering) happens on the server.

Built to the spec in `../Dubber-Build-Spec (1).md`, matching the 32 mockup screens.

## Requirements

- Flutter 3.38.9 (stable) — installed at `D:\flutter`
- Dart 3.10.8
- For Android builds: Android SDK (see *Android SDK* below)
- For iOS builds: macOS with Xcode

## Run

```powershell
# Web (fastest way to preview the UI)
flutter run -d chrome

# Android (needs the SDK, see below)
flutter run -d <device-id>

# Point at a different server
flutter run --dart-define=API_BASE=https://your-server/v1
```

The API base URL defaults to `https://api.dubber.app/v1` and is overridable with
`--dart-define=API_BASE=...`.

## Test

```powershell
flutter test
```

76 tests cover the domain models, the queue rules (file validation, the plan
that decides which videos fit in the remaining credits and slots, the 20-video
queue limit, the 10-file picker limit, the 2-upload limit, idempotency keys),
the queue API shapes, the `EditorState → ExportSettings` mapping, mix presets,
template prefill, and the shared widgets (including reduce-motion and
accessibility behaviour).

## Queue and New

- **New** dubs **one** video. It is only available when the user has nothing
  processing and nothing queued; the server re-checks at submit and answers
  `already_dubbing`. When blocked, the button is replaced by a message and a
  link to the Queue.
- **Queue** is where many videos are added: pick up to 10, set the options once
  (or per video), and the server dubs them one after another. Credits and the
  20-video limit are checked per item, in order, and whatever did not fit is
  reported with a reason.
- The tab badge shows what is dubbing plus what waits behind it.

The demo server implements the queue endpoints the app calls. See
`../QUEUE_REPORT.md` for what was verified and `../QUESTIONS.md` for the API
assumptions.

## Project layout

```
lib/
  main.dart                 app entry, session restore
  app/
    app.dart                MaterialApp + text scaling
    providers.dart          API client / Dio providers
    tab_scaffold.dart       shared scaffold for the four tabs
    theme/                  tokens.dart (design system), app_theme.dart
    router/                 go_router config + bottom tab bar
  core/
    api/                    ApiClient (Dio + auth refresh), ApiError
    widgets/                buttons, fields, chips, sliders, character, states
  features/
    auth/                   login, signup, forgot password, session
    onboarding/             four-page Quick guide
    projects/               list + cache, models, API repositories
    new_project/            one video: form, upload, estimate, create
    queue/                  add many videos, wait list, reorder, retry
    jobs/                   progress with polling + character
    result/                 player, Dubbed/Original switch
    editor/                 preview overlay + 8 tool panels
    export/                 exporting → video ready
    account/                account, credits, packs
    templates/              grid + preview sheet
    tutorials/              learn page
```

Layering: **widget → Riverpod controller → repository → API client**.
Widgets never call `dio` directly, and no raw maps reach the UI.

## Design system

All colors come from `lib/app/theme/tokens.dart`. No other colors are used.

| Token | Value | Use |
|---|---|---|
| ivory | `#FAF9F5` | Screen background |
| ink | `#141413` | Main text, video background |
| muted | `#66655E` | Second text |
| clay | `#D97757` | Highlights, progress fill |
| clayButton | `#B5502D` | Buttons, active tab |
| softClay | `#F6E7DF` | Selected items |
| oat | `#F0EEE6` | Light areas, thumbnails |
| border / borderStrong | `#E8E5DA` / `#D9D6CB` | Lines, inputs |
| doneText / doneBg | `#3F5B2A` / `#E3EBD9` | Done status |
| workingText / workingBg | `#7A4A12` / `#F6E7C6` | In progress |

Type: Newsreader w500 for headings, Inter for body/buttons. Body min 14 sp,
buttons 16 sp w600. Cards radius 20, buttons/inputs radius 14, chips fully round.
Main button 52 high, full width. Side padding 20. Design frame 390 × 844.

## The character

`lib/core/widgets/dubber_character.dart` draws the clay figure with headphones at
a mixing desk as a `CustomPainter` — the same shapes as the mockup SVG. It bobs,
blinks, moves its hands, slides the knobs, and floats sparks.

It honours **reduce motion**: when `MediaQuery.disableAnimations` is true the
painter receives a frozen animation and nothing moves.

## Hard rules honoured

1. No heavy work on the phone — the preview is Flutter widgets over a dark stage.
2. Voices, languages, templates and packs all come from the API.
3. Editing sends a settings object to `POST /projects/{id}/exports`.
4. Changing the mix is `PUT /projects/{id}/mix` and never costs credits.
5. All positions are fractions 0..1, never pixels.
6. Every data screen has loading / empty / error / offline states.
7. Reduce motion, 4.5:1 contrast, semantic labels, 44 px targets, never color alone.

## Environment notes

Two Flutter SDK cache files were missing on this machine and were restored:

- `D:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf`
- `D:\flutter\bin\cache\artifacts\engine\windows-x64\icudtl.dat`

Without them, `flutter build web` fails while copying assets and `flutter test`
fails with `Check failed: context->IsValid()`.

`flutter analyze` currently crashes inside the analyzer itself
(`Bad state: No definition of type Object`) on this SDK — it reproduces on a
brand-new empty project, so it is an SDK issue, not this code. The Dart compiler
(`flutter build web`) is the source of truth here and compiles cleanly.

## Android SDK

Installed at **`D:\Android\Sdk`** — not the default `%LOCALAPPDATA%\Android\Sdk`,
because that path contains a space ("Asus TUF F15") and Flutter rejects it:

> Android SDK location currently contains spaces, which is not supported by the
> Android SDK as it causes problems with NDK tools.

Installed packages: `platform-tools` 37.0.1, `platforms;android-36`,
`build-tools;36.0.0`. JDK: Temurin 21 at
`C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot`.

`flutter config --android-sdk D:\Android\Sdk` is already applied. If you open a
new shell, set the environment first:

```powershell
$env:ANDROID_HOME = 'D:\Android\Sdk'
$env:ANDROID_SDK_ROOT = 'D:\Android\Sdk'
```

Build and install:

```powershell
flutter build apk --debug          # output in build\app\outputs\flutter-apk\
flutter install                    # to a connected device
flutter devices                    # list connected phones
```

If `flutter devices` does not list your phone: enable **Developer options** and
**USB debugging** on the phone, then run `adb devices` to check it is authorised.

### Emulator

An AVD named **`dubber_test`** is already created (Pixel 7, Android 16 / API 36,
x86_64, Google APIs). Its disk lives on **C:** at
`C:\Users\Asus TUF F15\.android\avd\dubber_test.avd` — D: was low on space.

```powershell
# Start it
D:\Android\Sdk\emulator\emulator.exe -avd dubber_test -gpu auto

# Wait until it reports "device" (not "offline"), then
flutter install
```

Notes:
- First boot takes ~2–3 minutes. Wait for
  `adb shell getprop sys.boot_completed` to return `1`.
- On the very first boot the emulator may show *"System UI isn't responding"*.
  That is the emulator's own systemui warming up, not the app — tap **Wait**.
- If the app is not found after install, launch it with
  `adb shell am start -n com.dubber.dubber_app/.MainActivity`.

## What is stubbed

These are wired to the real API shape but need server endpoints or extra plugins
before they work end to end:

- **Download** — uses the platform save dialog; files are saved where the user
  chooses rather than automatically added to Photos/Gallery.
- **Push notifications** — permission timing and FCM are not wired.
- **In-app purchases** — credit packs render from `GET /credits`; store billing
  and receipt verification are not wired.
- **Tutorials** — the Learn page uses the mockup's groups; `GET /tutorials` is not
  connected.
- **Delete account** — confirms, then reports it is not set up.
- **Social login** — "Continue with Google" reports coming soon, per the spec.

## Next steps

1. Install the Android SDK and run on a real device.
2. Connect the remaining endpoints listed above.
3. Add `drift` for offline caching beyond the current `SharedPreferences` cache.
4. Wire `intl` ARB files — all user-facing strings are currently inline.
