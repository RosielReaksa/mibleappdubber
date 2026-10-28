# Questions and assumptions

Things the task left open, and what was assumed instead.
Each answer changes real behaviour, so they are worth deciding before a real
server is built.

## Endpoints

I had to invent the queue API; the build spec only covers projects, uploads and
exports. These are what the app calls and what the demo server implements:

| Call | Assumed shape |
|---|---|
| `GET /queue` | `{ now_dubbing: Project?, up_next: [Project…], failed: [Project…], slots_left: int }`; `up_next` items carry `position` |
| `GET /queue/active` | `{ project: Project? }` — the head of the queue, or null |
| `POST /queue/items` | `{ items: [{ file_name, upload_id, source_language, target_language, format, voice, mix, template_id?, idempotency_key }] }` → `{ now_dubbing, up_next, rejected: [{file_name, code, message}], reserved_credits, balance, stopped_reason }` |
| `DELETE /queue/items/{id}` | remove / cancel; returns reserved credits |
| `POST /queue/items/{id}/move` | `{ "to": "top" }` |
| `PUT /queue/order` | `{ order: [id…] }` |
| `POST /queue/items/{id}/retry` | re-queue a failed job; reserves credits again |

**Question:** does your real server already have these, or should the app use
`POST /projects` + a separate queue table?

## Credits

- **Assumed:** one price per video, from `POST /projects/estimate`, regardless
  of length. The estimate endpoint takes languages, format and voice but no
  file, so it cannot price by duration.
- **Assumed:** the server charges at submit, not at upload start.
- **Assumed:** a failed job refunds in full; the Queue row says "Credits
  returned", which is only true if the server does that.
- **Assumed:** removing a job that is already dubbing refunds in full too. If a
  partly-dubbed job is cancelled, should the user pay for the work done?

## Limits

- `MAX_QUEUE_PER_USER = 20` — the number you gave. It counts the video that is
  dubbing plus everything waiting; failed jobs do not count.
- `MAX_FILES_PER_ADD = 10` per picker, as specified.
- `MAX_CONCURRENT_UPLOADS = 2`, on the client.
- **Question:** is 20 per user, or per device, or server-wide?

## Resumable uploads

The upload is chunked and each part is retried, but **a part is not resumed
after the app restarts**: the upload id lives in memory. "Resumable" today means
"a dropped connection continues from the last finished part inside one session".
True resume needs the upload id and part index written to disk. Should I add
that?

## Duration

`QueueRules` rejects a file longer than 60 minutes when the platform reports a
duration. `file_picker` does not give one, so in practice **the client cannot
check duration yet** — only the server can. Options: add a video-duration
plugin, or let the server reject and report it. Which do you prefer?

## Validation

- The app checks extension, size (2 GB) and duration (when known) before
  uploading.
- The server checks the upload exists and is complete, credits and the queue
  limit. It does **not** re-check file type or size.
- **Question:** should the server own all validation, so the two lists cannot
  drift?

## Ordering and the two screens

- New is blocked by *any* queued job, not only a processing one. That is what
  "no processing job and no queued job" says; it also means a user with 19
  waiting videos cannot start a 20th from New.
- **Question:** is that intended, or should New be blocked only while something
  is processing?

## Notifications

- **NOT IMPLEMENTED as a push.** Nothing is wired to FCM, and no local
  notification plugin is in `pubspec.yaml`. What exists is one grouped in-app
  message on the Queue tab when videos finish ("3 videos are ready · See
  Projects"), which only shows while the app is open.
- Grouping one push per batch rather than one per video needs the server to send
  the batch id, or a local scheduler. **Question:** which side should group
  them?

## Reordering

- Order is saved with `PUT /queue/order` after every move.
- **Assumed:** the server accepts a full reorder of the waiting list, and
  rejects a stale list with `stale_order`.
- Dragging was not used; each row has move-to-top / up / down buttons. A drag
  list inside the page's scroll view fights the scroll on a phone.

## Demo server

- In-memory only: restarting it clears projects, the queue and accounts.
- `--job-seconds` (default 24) sets how long a job takes.
- `X-Fail-Next: 1` makes the next added video fail at 40%, so the Failed row and
  Retry can be demonstrated.

## Still stubbed from before this task

Unchanged: logo upload, download to gallery, share, in-app purchases, tutorials,
delete account, social login. See `dubber_app/README.md`.
