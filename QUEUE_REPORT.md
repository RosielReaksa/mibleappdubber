# Queue and New — report

State of the correction you sent: **New = one video, Queue = many videos.**

Everything below was checked on 2026-10-27 against the demo server
(`demo_server/server.py`) on the Android emulator (`dubber_test`), unless the
item says otherwise.

Legend:
- **VERIFIED** — seen working end to end: the app talked to the server and the
  screen showed the expected result (screenshot or server check).
- **CODE-ONLY** — implemented and compiles; not exercised end to end.
- **NOT TESTED** — not implemented, or no way to exercise it yet.

---

## 1. What was removed from New

From the earlier multi-video build:

| Removed | Was |
|---|---|
| `new_project/application/batch_runner.dart` | uploaded N files, created N projects |
| `new_project/domain/batch_rules.dart` | batch limits, credit maths, labels |
| `test/batch_rules_test.dart` | tests for the above |
| `_BatchFilePicker` widget | list of files with per-file remove |
| `addFiles` / `removeFile` / `setBatchProgress` / `totalCredits` on the controller | batch state |
| `"Start N videos · X credits"` label | batch button label |
| Multi-select in the New picker (`allowMultiple: true`) | now `false` |

The New screen now holds **one** `PickedFile` and a single `start()` call.

## 2. New screen

| Item | State | Evidence |
|---|---|---|
| One video only; picker is single-select | **VERIFIED** | picker shows no "N selected" header; one card `clip_a.mp4` |
| Validates type, size, duration before submit | **VERIFIED** | `QueueRules.validate`; 20 unit tests in `test/queue_rules_test.dart` |
| Button reads "Start dubbing · 12 credits" | **VERIFIED** | screenshot `q_16_newfile.png` |
| No job created when validation fails | **VERIFIED** | `setFile` rejects before any upload; no request is sent |
| Button only when nothing is processing or queued | **VERIFIED** | blocked below |
| Server re-checks at submit (`already_dubbing`) | **VERIFIED** | direct `POST /projects` → 409 `already_dubbing`; the app maps it to the blocked state |
| Blocked message + button to Queue | **VERIFIED** | `q_25_blocked.png`: *"busy2.mp4" is already dubbing. Add more videos from the Queue tab.* + **Open Queue** |
| After submitting, switch to the Queue tab | **VERIFIED** | `q_17_started.png`: Queue, `clip_a.mp4` **Now dubbing 30%** |
| Resumable upload | **CODE-ONLY** | chunked PUT per part, retried 5× with backoff; resume-after-restart is not implemented (see QUESTIONS) |
| Credits reserved at submit | **VERIFIED** | 120 → 108 after one start; server refunds on remove/fail |

## 3. Queue screen

| Item | State | Evidence |
|---|---|---|
| "Add videos" replaces "Start a new project" | **VERIFIED** | `q_03_queue_empty.png` |
| Multi-select picker, up to 10 | **VERIFIED** | `q_09_select3.png`, `q_10_selected.png` |
| One set of settings, applied to all | **VERIFIED** | "Settings for every video", `q_10_selected.png` |
| Settings changeable per video | **CODE-ONLY** | "Change" per row opens its own sheet; not driven on the device |
| Per-file validation with a reason, valid files still added | **VERIFIED (API)** | server returns one rejection for the bad file, adds the other 4 |
| Credits reserved in order; partial add reported | **VERIFIED (API)** | 36 credits, 5 videos → exactly 3 added, 2 reported not added, `reserved_credits` 36, balance 0 |
| `MAX_QUEUE_PER_USER` = 20 with "Your queue is full" | **VERIFIED (API)** | 20 slots, add refused past 20; copy in `slots_left` |
| One job run at a time; the rest wait, in order | **VERIFIED** | `q_12_afteradd.png`: 1 dubbing, 2 waiting at positions 1–2 |
| At most 2 uploads at once; the rest wait | **CODE-ONLY** | `maxConcurrentUploads = 2` worker pool; not observed on device |
| Now dubbing section | **VERIFIED** | `q_12_afteradd.png` |
| Up next, numbered, remove / move to top / reorder | **VERIFIED** | screenshot; move-to-top and reorder confirmed through the API |
| Failed with Try again | **VERIFIED** | `q_30_failed.png` |
| Failed rows can also be dismissed | **VERIFIED** | `q_30_failed.png` (× in the corner) |
| "Credits returned" on failed rows | **VERIFIED** | `q_30_failed.png` |
| Done leaves the queue and appears in Projects | **VERIFIED** | finished job shows as **Done** in `q_29_relaunch.png` |
| Tab badge | **VERIFIED** | badge **3** in `q_12_afteradd.png`, **1** in `q_17_started.png` |
| Auto-refresh within 5 s | **VERIFIED** | 3 s while the tab is visible; 10 s elsewhere |
| Grouped "N videos are ready" message | **CODE-ONLY** | one SnackBar on the Queue tab; not seen because jobs finish one at a time |
| Push notification on finish/fail | **NOT TESTED** | no FCM/plugin wired; see QUESTIONS |

## 4. The tests you asked for

| # | Test | State | Evidence |
|---|---|---|---|
| 1 | New with an empty queue: Start works, job starts in seconds | **VERIFIED** | `q_16_newfile.png` → `q_17_started.png`; API: status `processing` immediately |
| 2 | New while a job is processing or queued: nothing created, message shown, API refuses | **VERIFIED** | `q_25_blocked.png`; `POST /projects` → 409 `already_dubbing` (both when processing and when merely queued) |
| 3 | 5 videos at once: 1 processing, 4 queued at 1–4 | **VERIFIED** | API check: `positions == [1,2,3,4]`, `reserved_credits == 60` |
| 4 | 5 videos, 1 invalid: 4 created, the failure explained | **VERIFIED (API)** | 3 waiting + 1 dubbing = 4 added; 1 rejection with a reason |
| 5 | Credits for 3 of 5: 3 added, 2 reported, reserved = 3 × 12 | **VERIFIED (API)** | added 3, `reserved_credits` 36, 2 rejected, `stopped_reason: not_enough_credits`, balance 0 |
| 6 | A video from New shows as Now dubbing; queue videos wait behind it | **VERIFIED** | API: `now_dubbing == FromNew.mp4`, `up_next == [Q0, Q1]` |
| 7 | Race: two devices start together, one wins, the other gets "already dubbing" | **VERIFIED (API)** | two concurrent `POST /projects` → `[200, 409]`, loser got `already_dubbing`, one job exists |
| 8 | When the New video finishes, New shows Start dubbing again | **VERIFIED** | API: `/queue/active` empty once finished, and a new start succeeded |

Test 5 is API-only because no credit pack combination lands exactly on 36
credits in the app; the server was driven with a balance set by a first add.

## 5. End-to-end scripts

Not part of the app. They drive the demo server over HTTP:

```powershell
python demo_server/server.py --port 8099 --job-seconds 180
python tools/queue_e2e.py            # 35 checks, tests 1-9
python tools/queue_failures_e2e.py   # 15 checks: failed, retry, dismiss, refund
```

`--job-seconds` was added so a job can be kept alive long enough to look at
New's blocked state. `X-Fail-Next: 1` on `POST /queue/items` makes the next
video fail partway, so the Failed row can be seen.

## 6. Test suite and build

- `flutter test` — **76 tests pass** (`test/queue_rules_test.dart`,
  `test/queue_models_test.dart`, `test/queue_widgets_test.dart`, plus the
  earlier model and widget suites).
- `flutter build web` — clean.
- `flutter build apk --debug` — built and installed on the emulator.
- `flutter analyze` still crashes inside the analyzer on this SDK; the compiler
  is the check (same as before, reproduces on an empty project).

## 7. Known gaps

- The app keeps working state in memory. Killing it mid-upload loses that
  upload's progress; the job on the server is unaffected.
- Push notifications are not wired (no FCM). The in-app message covers the
  foreground case only.
- The Queue tab polls every 10 s while another tab is open, not less; the badge
  and the finish message need that.
