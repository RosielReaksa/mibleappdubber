# Admin Website UI/UX Redesign Specification

**Status:** Design and implementation blueprint  
**Scope:** FastAPI administration console only  
**Primary route:** `/admin` (alias: `/manage-k7x`)

## 1. Purpose and scope

Redesign the server administration website into a calm, dependable operations console. Operators should be able to understand service state, find and diagnose jobs, inspect completed projects, manage user credits, review aggregate traffic and usage, and configure/test the dubbing engine without hunting through unrelated tools.

The experience should feel classic, soft, polished, and professional: warm cream surfaces, refined serif page headings, clear sans-serif data labels, muted terracotta actions, sage success states, charcoal text, thin warm dividers, and restrained shadows. Keep the interface composed and legible. Avoid cartoonish decoration, excessive rounded-card nesting, dense dashboard clutter, and fabricated live-looking data.

### In scope

- The FastAPI admin console served from `server/admin.html` by `server/main.py`.
- Six approved screens: **Overview**, **Jobs**, **Projects**, **Traffic & Usage**, **Users & Credits**, and **Engine Settings**.
- Admin sign-in, permission/session states, responsive behavior, accessibility, and operator feedback.
- Identifying backend and telemetry dependencies needed to make the UI truthful.

### Out of scope

- The phone preview at `/` and `/phone`.
- The Flutter web/mobile app mounted at `/app/`.
- Replacing the dubbing product flow or changing the mobile app design.

Any names, rows, dates, counts, charts, provider labels, or GPU details shown in visual concepts are illustrative only. Bind every displayed value to verified live data, or mark it as unavailable/demo content. Never present concept mockup values as production metrics.

## 2. Current implementation and audit basis

- **Verified current stack:** Python FastAPI server (`server/main.py`), which serves `server/admin.html` at `/admin` and `/manage-k7x`; the admin page is one HTML file with inline CSS and vanilla JavaScript. There is no frontend framework/build step for this admin console.
- **Existing admin API routes in `server/main.py`:** `POST /api/admin/auth`, `GET /api/admin/stats` (also `/api/stats`), `GET /api/admin/users`, `POST /api/admin/user/credit`, `GET /api/admin/modal/accounts`, `GET /api/admin/modal/build-logs/{target}`, `POST /api/admin/config`, `GET/POST /api/admin/gemini/config`, `POST /api/admin/gemini/test`, and `POST /api/admin/dubber/test`.
- The current page contains five tab panels, inline event handlers, tables, provider settings, a direct dubbing test, logs, and an embedded phone preview.
- `/` and `/phone` return a phone-preview page; `/app/` serves the compiled Flutter app when its build directory exists. Neither is part of this admin redesign.
- The current stats endpoint returns counts and only the latest 20 projects as `active_jobs`. Its visitor/bot values include placeholders (`128 + total_users`, `total_users or 1`, and `0`). GPU and engine strings are fixed values.
- The current completed-project panel filters the latest 20 projects, uses hard-coded format/voice labels, and points every row to `/media/dubbed.mp4`.
- Several browser requests suppress errors; the queue polls every three seconds without a last-updated indicator or pause control.
- The current header is crowded at small widths; tables lack a mobile presentation; the phone frame has fixed dimensions. Form labels are not associated with inputs, selected tab state is not exposed, and keyboard focus treatment is incomplete.
- An admin auth endpoint exists, but the current console does not call it or attach its token to admin requests. The admin page itself is served without a login flow.

This document specifies the intended experience; it does not assume that existing API responses are authoritative where their values are placeholders or incomplete. Section 16 distinguishes the verified stack above from the recommended implementation approach.

## 3. Product principles and success criteria

1. **Truth before polish:** every number and status has a defined source, time window, and refresh time. Unknown data is labeled unavailable, never silently replaced with a plausible value.
2. **Jobs first:** current work and failures are immediately visible from Overview. The Jobs screen is the operational source of truth.
3. **Separate monitoring from configuration:** users, credits, provider settings, and test tools have clear destinations and permissions.
4. **Progressive disclosure:** summaries stay compact; job, project, user, and provider details open in focused detail views.
5. **Quiet visual hierarchy:** warm surfaces and typography support scanning without making routine status feel like an alert.
6. **Resilient operation:** loading, stale, offline, empty, forbidden, and failed states explain what happened and what the operator can do next.

Success means an operator can identify a failed/active job and reach its details quickly; distinguish live health from stale/unavailable health; find the correct completed output; understand what a traffic metric counts; and apply a credit or provider change with clear confirmation and outcome feedback.

## 4. Information architecture and navigation

Use a persistent left sidebar on desktop with the product name, current environment (only if supplied by deployment configuration), and six plainly labeled destinations:

1. Overview
2. Jobs
3. Projects
4. Traffic & Usage
5. Users & Credits
6. Engine Settings

Use one page heading and short explanatory subtitle per screen. The active item must be visually distinct and programmatically exposed. Keep the account/session menu in the lower sidebar or top-right utility area. A compact global status summary may appear in the header only when populated by verified health data; it must link to the relevant detail and include freshness.

On narrow screens, replace the persistent sidebar with a menu button and accessible drawer. Do not use the embedded phone preview as the admin home. If a phone preview remains useful to developers, place it behind a clearly named separate utility link outside the six primary destinations.

Suggested route structure, compatible with a single-page implementation if needed:

- `/admin` — Overview
- `/admin/jobs`
- `/admin/projects`
- `/admin/traffic`
- `/admin/users`
- `/admin/engine`

If the implementation retains client-side panels instead of URL routes, synchronize the selected screen with the URL so it can be bookmarked and browser back/forward works. Keep `/manage-k7x` as a compatibility alias that resolves to the admin entry route, not as a distinct experience.

## 5. Visual system

The following are proposed starting tokens, not immutable brand standards. Check contrast and visual appearance during implementation. Use shared tokens rather than one-off inline color values.

| Token | Proposed value | Use |
|---|---|---|
| `canvas` | `#F6F3EC` | Overall warm ivory page background |
| `surface` | `#FFFEFA` | Main content and elevated panels |
| `surface-soft` | `#F0EDE5` | Quiet secondary areas and input backgrounds |
| `ink` | `#292722` | Primary text and headings |
| `muted` | `#716D64` | Supporting labels and descriptions |
| `divider` | `#E4DED2` | Warm, thin rules and table separators |
| `terracotta` | `#A9553D` | Primary action and active navigation accent |
| `terracotta-hover` | `#8F442F` | Hover/pressed accent; verify contrast |
| `sage` | `#536D55` | Success state text/icon; pair with a pale sage surface |
| `warning` | `#8A621F` | Warning text/icon; pair with a pale amber surface |
| `danger` | `#A3433B` | Failure/destructive text/icon; pair with pale rose |
| `focus` | `#7C4E3A` | Visible keyboard focus ring |

- **Typography:** refined serif (for example, Newsreader with Georgia fallback) for page titles and a restrained number of section headings. Use a clean sans-serif (for example, Inter/system sans) for tables, forms, body text, and controls. Use tabular numerals for values that compare vertically.
- **Layout:** generous page gutters, consistent spacing steps, readable maximum content width, aligned table columns, and clear screen-level hierarchy. Prefer dividers and whitespace over a card around every group.
- **Shape and elevation:** modest corner radii; subtle border/shadow only where elevation conveys structure. Avoid nested cards and strong glows.
- **Status:** always pair color with a text label and, when useful, an icon. Do not animate status indefinitely. Provide a reduced-motion variant.
- **Controls:** consistent heights, labels, validation, hover/pressed/disabled/loading states, and visible focus. Use explicit labels such as “Save provider settings” and “Grant 50 credits.”

## 6. Screen requirements

### 6.1 Overview

**Purpose:** Answer “Is the service healthy, and what needs attention?” at a glance.

**Content and hierarchy**

- Page title, brief description, and a clear data freshness/last-updated label.
- Compact summary metrics: active jobs, queued jobs, completed jobs for a stated time period, registered users, and failed jobs requiring attention. Include only metrics the backend can define and supply.
- Service health section for API availability, queue worker heartbeat, provider connectivity, and storage/media availability, if those checks exist. Show `Unknown`/`Not configured` when absent; do not claim a GPU is active based on static copy.
- Recent/active jobs list with status, title or safe filename, owner, target language, progress/step, created time, and a link to job details.
- A prominent failures/recent alerts section with a next action. Empty success state should say there are no current failures.

**Behavior**

- Refresh button and optional automatic refresh with visible cadence, pause/resume, and last-successful-update time. Pause when the page is hidden where practical.
- Clicking a metric opens the corresponding filtered Jobs or Users view.
- Partial endpoint failure should preserve successfully loaded sections and mark only failed sections stale/unavailable with retry.

### 6.2 Jobs

**Purpose:** Find, monitor, and recover dubbing work.

**List controls**

- Search by job/project title or ID; filters for status, target language, owner, and creation time; sort and pagination/server-side limit.
- Default view should emphasize queued, processing, and failed work, with a clear switch/filter for all jobs and completed jobs.
- Table columns: project/title, owner, source → target language when known, status, progress, current step, created/updated time, duration where known, and row actions.
- Status text: Queued, Processing, Completed, Failed, or the exact documented backend state. Unknown states must remain visible as unknown rather than be mapped to a success state.

**Details and actions**

- Row opens a detail drawer/page with job ID, complete metadata, timestamps, progress history/step if available, failure reason and recovery guidance if available, and the correct input/output artifact links.
- Retry is available only for retryable failures and requires a confirmation that identifies the selected job. Report the result and prevent duplicate submission while pending.
- Do not imply cancellability, deletion, or editing unless the API supports it.

**Data dependency:** current `/api/admin/stats` exposes only the latest 20 project records. Add/extend an admin jobs endpoint with pagination, filtering, stable status and timestamp fields, details, and output URLs before promising a complete searchable history. Confirm how retry is implemented and which failures are retryable.

### 6.3 Projects

**Purpose:** Browse completed outputs and inspect their source and export metadata.

- Search and filter completed projects by title/ID, owner, target language, completion range, and output state where supported.
- Use a project table or uncluttered list with title, owner, language pair, actual format/aspect ratio, voice, completion time, and output availability. Show fields only when stored; unknown values should be “Not recorded,” not a hard-coded “Landscape” or “Natural Neural.”
- Project detail view includes a playable output preview when supported, a distinct original/output link, project settings, and job history. Show unavailable/missing media as an explicit state with retry/refresh guidance.
- Use each record’s own output URL. Never reuse one generic output file for all rows.
- Paginate on the server for full history and use safe filenames/URLs.

**Data dependency:** the current gallery derives from the latest 20 stats rows and uses a common media URL. Supply a project listing/detail endpoint with truthful stored metadata and per-project output URLs. Confirm whether `done` is the only final success state.

### 6.4 Traffic & Usage

**Purpose:** Show aggregate product/server traffic and usage trends.

**Candidate sections, conditional on available telemetry**

- Visitors or sessions over time, with explicit timeframe and aggregation granularity.
- Project/job volume created and completed over time.
- Upload volume or bytes processed, if measured reliably.
- Aggregate language and status breakdowns from real project records.
- Data source and last collection/update time, plus definitions accessible from metric labels or an information affordance.

Provide timeframe controls only for periods the data store can answer. Empty, delayed, or uninstrumented data should clearly say that analytics are not available yet. Do not display current placeholder values as traffic: existing `total_visitors`, `unique_visitors`, and `blocked_bots` values are not reliable visitor telemetry.

**Open dependency:** establish whether an analytics source exists, what counts as a visitor/session, what retention is available, and whether historical data can be queried. If not, instrument and validate it before presenting traffic charts. Until then, show a clear “Traffic analytics not connected” state rather than synthetic charts or zeroes.

### 6.5 Users & Credits

**Purpose:** Find accounts, understand balances, and make traceable credit adjustments.

- Search by email/name; sort and paginate. Table shows email, name, current credit balance, member-since date, and supported account status only if available.
- User detail view shows the account identity, current balance, and a credit history/ledger if supported.
- Credit adjustment dialog asks for amount, direction, reason/note, and shows the resulting balance before confirmation. Use a specific button (for example “Grant 50 credits” or “Remove 10 credits”), show pending state, and return a clear success/failure message.
- Include confirmation for consequential adjustments; never let a repeated click silently apply a second change. Record operator, timestamp, delta, reason, and resulting balance in an auditable ledger if the backend supports it.
- Empty results, API errors, and permission denial have separate states.

**Data dependency:** current user listing exposes email, name, credits, and created time; the current adjustment endpoint accepts a delta but does not show an audit ledger in the UI. Confirm authorization, adjustment bounds, negative-balance policy, idempotency, and whether a reason/history API is available.

### 6.6 Engine Settings

**Purpose:** Safely inspect and configure the dubbing provider, then verify it before production use.

- Separate provider configuration from diagnostic/test execution within the screen using clear sections.
- Fields: provider type, base URL, model, and API key. Show whether a key is configured, but do not return or reveal the saved secret. Use a masked placeholder and explicit replace/clear flow. Associate labels, helper copy, validation, and errors with fields.
- “Test connection” displays a pending state and then success/failure, measured latency if returned, provider/model tested, and a useful correction step. A test must make clear whether it tests unsaved form values or currently saved values.
- “Save provider settings” requires an explicit action; confirm success from the backend and display the saved model/provider without echoing the secret. Protect against navigation away during a dirty form.
- The direct dubbing test belongs in a separate diagnostic section on this page (or a clearly secondary diagnostic subview). Explain that it runs a real server pipeline and may consume provider resources. Show file constraints, target language, voice, progress, output player/download, and a readable transcript result. Do not auto-play by default; use accessible live status feedback.
- If provider status is not available, show “Not checked” or “Unknown,” not a green operational badge.

**Data dependency:** current settings handlers expose configuration/test operations. Confirm whether the config response includes a secret and change it to return only a configured/masked indicator. Confirm connection test semantics, model validation, test cost/limits, and diagnostic log source/retention before presenting them as live operational facts.

## 7. Shared components and interaction patterns

- **App shell:** responsive sidebar/drawer, page title area, session menu, optional verified service state.
- **Metric tile:** name, value, time window/definition, freshness, optional comparison only when a real comparison period exists.
- **Status badge:** label plus icon/text semantics; color never carries meaning alone.
- **Data table:** accessible column headers, sort state, pagination, row loading, empty state, error state, and mobile alternative. Keep keyboard navigation predictable.
- **Filter bar:** labeled search and filters, clear-all action, active-filter summary, URL-synchronized state where practical.
- **Detail drawer/page:** focus management, close control, Escape handling, responsive full-screen treatment on mobile, and preserved list context.
- **Confirmation dialog:** action, affected record, amount/details, cancel and explicit confirm; focus returns to the trigger.
- **Inline alert/toast:** success, warning, failure, and informational variants with `aria-live` announcements for async outcomes.
- **Loading skeleton/spinner:** limited to the region loading; do not replace a healthy page with an indefinite global spinner.
- **Freshness indicator:** last successful fetch time and stale state, not just the current clock time.

## 8. State and failure behavior

Every data-driven screen and section must define:

- **Initial loading:** concise skeleton/indicator and stable layout to avoid shifting.
- **Empty:** explain what is empty and offer a relevant next step; distinguish “no jobs” from “could not load jobs.”
- **Error:** plain-language cause if known, safe next action, retry button, and request correlation ID if the API supplies one.
- **Stale/offline:** keep last known data visible but label its age and offer refresh; do not present stale status as current.
- **Partial failure:** render successful panels and mark failed panels independently.
- **Permission denied/session expired:** explain the session ended and return to sign-in without losing unsaved user input when safe.
- **Mutation pending/success/failure:** disable duplicate submissions, show outcome, refresh the affected data, and preserve errors until understood.

Use server responses as data, escape any user-generated text, and avoid inserting untrusted values into HTML strings. Dates and numbers should use locale-aware formatting; retain an accessible exact timestamp where useful.

## 9. Responsive behavior

Use fluid CSS grid/flex layouts and content-driven sizing; avoid fixed viewport-sized controls and phone-frame dimensions in the main admin workflow.

- **Wide desktop (approximately 1200px and above):** full sidebar, comfortable content width, multi-column summaries, full tables.
- **Tablet (approximately 768–1199px):** compact/collapsible sidebar, fewer metric columns, allow table container scrolling only when necessary, preserve row actions.
- **Mobile (below approximately 768px):** menu drawer, one-column summaries/forms, stacked page headers/actions, tables converted to compact labeled rows or intentionally scrollable with sticky key context. Keep dialogs within viewport and respect safe areas.
- At all widths, long IDs/emails must wrap or truncate with an accessible way to inspect the full value; primary actions remain reachable without horizontal page overflow.

Breakpoint numbers are implementation starting points; validate with actual content at narrow phone, tablet, and laptop sizes.

## 10. Accessibility requirements

- Semantic landmarks, one clear `h1` per screen, hierarchical headings, and a skip link to main content.
- Navigation exposes current page; if tabs are retained, use correct tab roles, selected state, keyboard behavior, and associated panels.
- Every input has a programmatic label; helper and error text are associated with the control. Use correct input types and autocomplete where appropriate.
- Visible `:focus-visible` styling on every control; maintain logical focus order and restore focus after dialogs/drawers close.
- Buttons for actions and links for navigation. Icon-only controls need accessible names; decorative icons should be hidden from assistive technology.
- Status and asynchronous updates announced politely; avoid announcing every polling refresh.
- Keyboard support for menus, tables, dialogs, video controls, and all actions. No color-only status or hover-only affordances.
- Respect reduced motion; avoid indefinite pulsing. Ensure text, controls, focus indicators, and status colors meet WCAG contrast requirements.
- Support zoom/reflow without clipping content or forcing two-dimensional scrolling except for genuinely tabular data with an accessible mobile alternative.

## 11. Authentication and credential UX

The sign-in experience is part of the admin UI redesign, but authorization must also be enforced by the server. A hidden route name or frontend-only gate is not authentication.

- Present a dedicated admin sign-in screen before loading operational data. Explain invalid credentials inline without exposing whether an account exists.
- Connect the existing `/api/admin/auth` flow to the UI only after confirming token lifecycle and server-side enforcement. Protect every admin data/mutation endpoint and both admin page aliases. Expired/rejected credentials should lead to a recoverable sign-in state.
- Define secure session storage, expiry, logout, and CSRF/origin behavior with the backend owner. Do not store long-lived secrets in URLs or log them.
- Never ship a usable default admin password. Configure secrets per deployment and require rotation/secure provisioning.
- Do not return stored provider API keys to the browser. Return a `configured` flag and safe masked metadata; accept a replacement secret only on explicit save. Never echo secrets in logs or error messages.
- Permission failures on sensitive operations (credit adjustments, engine settings) must be visible and understandable. If roles are introduced later, show permitted/denied actions consistently; do not invent roles before the backend defines them.

**Current dependency:** `/api/admin/auth` exists, but the current page does not call it and the inspected admin routes do not show token validation. Treat protected route/API enforcement as a prerequisite, not a visual-only enhancement.

## 12. Data contracts and metric definitions

Before connecting a metric or field, document its source, calculation, timezone, time window, refresh interval, and missing-data behavior. Proposed definitions:

| Display | Definition to confirm | Current evidence/dependency |
|---|---|---|
| Active jobs | Count with status `queued` or `processing` at query time | Current stats query uses these statuses |
| Completed jobs | Count with status `done`; specify lifetime or selected period | Current stats count is lifetime; overview may need a period endpoint |
| Failed jobs | Count with status `failed`; identify recoverable subset separately | Status exists in UI logic; stats has no dedicated count |
| Registered users | Count of user records at query time | Current stats query counts users |
| Queue progress | Stored project percent and step, with update time | Latest-project response includes percent/step; verify freshness/semantics |
| Project output | Output URL belonging to that project | Current gallery incorrectly uses a shared static URL |
| Traffic visitors/sessions | Analytics-defined unique visitors/sessions in selected interval | Current values are placeholders; instrumentation/source required |
| Upload/processing usage | Measured bytes/duration/jobs in a named interval | No dependable definition/source established by the inspected stats payload |
| Service health | Result of real API/worker/provider/storage checks plus checked-at time | Current GPU/engine labels are static strings |

If a definition or source is unavailable, omit the metric or show an explicit unavailable state. Zero means measured zero; it must not mean missing telemetry.

## 13. Implementation phases and priorities

### Phase 0 — Data/auth contracts (P0 prerequisite)

- Define admin authentication/session behavior and enforce it on the page and all admin APIs.
- Define job/project schemas, pagination/filter parameters, output URL ownership, health checks, and metric semantics.
- Decide whether aggregate traffic analytics exists; if not, define instrumentation and historical retention before chart work.
- Ensure provider secrets are never returned in full.

**Acceptance:** unauthorized requests cannot read or mutate admin data; current endpoints have documented authorization; data responses distinguish missing values from measured zero; every displayed status has a verified source.

### Phase 1 — Shell and design foundation (P1)

- Establish tokens, typography, page frame, sidebar/drawer, URL/navigation behavior, headings, focus, shared buttons/forms/statuses, and global loading/error patterns.
- Add a working sign-in/session-expired flow.

**Acceptance:** all six destinations are reachable and bookmarkable; desktop and mobile navigation work by keyboard and touch; current page and session state are announced accessibly.

### Phase 2 — Overview and Jobs (P1)

- Build trustworthy summary cards, freshness, health states, recent jobs, full job list/filter/pagination, details, and retry flow.
- Replace blind three-second refresh with a deliberate refresh policy and visible freshness/pause state.

**Acceptance:** filters and page state persist in the URL; job count/status matches backend definitions; failed requests are visible and recoverable; retries require confirmation and prevent duplicate submission.

### Phase 3 — Projects and Users & Credits (P1)

- Add complete paginated project history with per-record outputs and accurate metadata.
- Add user search/detail and safe, auditable credit adjustment flow.

**Acceptance:** every project preview/download corresponds to its own record; unknown metadata is not fabricated; credit updates show pending/result and cannot be double-applied accidentally.

### Phase 4 — Traffic & Usage (P2, telemetry-dependent)

- Implement aggregate charts/summary only after analytics source, definitions, and retention are confirmed.
- Provide timeframe controls, accessible chart summaries, and data freshness.

**Acceptance:** every chart has an accessible text/table equivalent and clear definition; no placeholder stats are shown as real.

### Phase 5 — Engine Settings (P1/P2)

- Add safe credential replacement, validation, test/save feedback, dirty-form protection, and separate diagnostic test workflow.

**Acceptance:** current secrets are never revealed; test results identify what was tested; save outcomes are confirmed; failures show actionable next steps; diagnostic execution state is keyboard/screen-reader accessible.

### Phase 6 — Responsive/accessibility/content verification (P1 continuous, final gate)

- Validate narrow and wide layouts, long data, zoom/reflow, keyboard-only usage, screen-reader names/state, focus return, reduced motion, contrast, and all async state variants.

**Acceptance:** no horizontal page overflow at supported widths; no inaccessible unlabeled controls or keyboard traps; every data screen has loading, empty, error, stale, and permission states; status is never conveyed by color alone.

## 14. Open questions and dependencies

1. What source should provide aggregate traffic/session metrics, and does historical data already exist? If not, what events and retention period should be instrumented?
2. Which health checks are operationally meaningful and available (worker heartbeat, provider connectivity, storage, GPU presence)? What is the expected freshness/timeout?
3. Which job states are final, retryable, or recoverable, and does the retry API accept an idempotency key?
4. Which project fields (source language, format, voice, duration, exports) are persisted today, and what endpoint supplies each project’s own output URL?
5. What are the policy limits for credit adjustments, are negative balances allowed, and is an immutable adjustment ledger required?
6. What admin session/token expiry and deployment secret-management policy should be used? Which operators may adjust credits or provider settings?
7. Is the `/manage-k7x` alias required for existing bookmarks/operations, and should it redirect to `/admin`?

## 15. Files and routes inspected

- `server/admin.html` — current admin page structure, styles, inline interactions, polling, and data rendering.
- `server/main.py` — FastAPI route wiring, phone preview routes, admin auth/stats/users/credits/provider/test endpoints, and `/app/` mounting.
- `dubber_app/README.md` and `dubber_app/lib/` — context confirming the Flutter client is a separate mobile-first app, outside this redesign scope.

**Implementation constraint:** create/modify the admin redesign artifacts only after this specification is accepted. Keep unrelated working-tree changes, including `server/engine/gemini_dubber.py`, untouched.

## 16. Recommended implementation stack

Keep the existing Python/FastAPI backend and use a small, dependency-free frontend for this admin surface. A frontend framework rewrite is not justified for six operational screens, especially when the current page is already served directly by FastAPI and no admin frontend build pipeline exists.

### Current versus recommended

| Concern | Current (verified) | Recommended for this redesign |
|---|---|---|
| Server | Python FastAPI in `server/main.py` | Keep FastAPI; isolate admin handlers in an `APIRouter` module while retaining URL compatibility |
| Admin document | `server/admin.html` returned as `HTMLResponse` | Keep a semantic HTML shell at the same path; load static CSS and ES modules |
| Styling | Inline CSS inside `admin.html` | CSS custom properties in `server/admin_ui/styles.css`; no CSS framework |
| Browser logic | Inline vanilla JS and `onclick` handlers | Native JavaScript ES modules, `fetch`, `URLSearchParams`, and History API; no bundler required |
| Persistence | Existing SQLite access through `server/db.py` | Keep existing DB layer; add explicit migrations/indexes for any new ledger or analytics tables after schema review |
| API data | Existing endpoints in `server/main.py` | Typed/documented response shapes (Pydantic response models where compatible with existing patterns) and server-side filtering/pagination |
| Tests | Existing pytest files under `server/` | Extend backend API/DB test coverage for changed contracts; do not rely on screenshots alone |

### Why not migrate frameworks now

The six-screen console can be split into readable HTML/CSS/JS modules without introducing React/Vue, Node package management, a bundler, a second deployment artifact, or a new runtime. Use accessible native controls and small render helpers. Revisit a framework only if the product later needs a much larger interactive application, shared frontend code with another product, or state complexity that has become costly to manage; document that rationale before adding a build system.

### Suggested frontend layout

```text
server/
  admin.html                    # semantic shell, landmarks, script/style links
  admin_ui/
    styles.css                  # design tokens, shell, shared components, responsive rules
    api.js                      # authenticated fetch wrapper and typed-by-convention errors
    app.js                      # route selection, shared shell, navigation, session bootstrap
    components.js               # status, table, metric, dialog, alert, loading/empty/error helpers
    screens/
      overview.js
      jobs.js
      projects.js
      traffic.js
      users.js
      engine.js
```

Use the actual project conventions if an equivalent static asset layout already exists when implementation begins. Mount or serve these assets under a dedicated same-origin path such as `/admin-assets/`. Do not place runtime secrets or user data in static files.

## 17. Ordered, file-by-file implementation handoff

Follow this order so the UI is built on enforced access and reliable data contracts rather than mock values. Preserve existing routes where clients/bookmarks depend on them. Inspect current schemas and route behavior before editing; do not infer new DB fields from the mockup.

### Step 0 — Repository and data reconnaissance (read-only)

1. Read `AGENTS.md`/repository instructions, `server/main.py`, `server/db.py`, `server/engine/gemini_dubber.py`, and `server/test_server_api.py`.
2. Inspect the actual SQLite schema and DB helper methods for projects, uploads, users, exports, and engine config. Note which fields and timestamps are persisted and which are derived.
3. Check `git status` and preserve all unrelated existing edits, especially `server/engine/gemini_dubber.py`. Do not stage, revert, reset, or clean the user’s work.
4. Inventory the legacy admin endpoints and consumers. Preserve public paths or add compatibility aliases when replacing handlers.

**Gate:** record field-level gaps and agree on telemetry/auth dependencies before UI work. Do not populate screens with hard-coded examples to hide missing APIs.

### Step 1 — Authentication and admin API boundary

**Files:** `server/admin_auth.py` (new, or the project’s existing auth module); `server/admin_routes.py` (new `APIRouter`, or refactor admin handlers out of `server/main.py`); `server/main.py` (router/static registration); `server/admin.html` and `server/admin_ui/app.js` (sign-in/session bootstrap); `server/test_server_api.py` (authorization contract coverage).

1. Replace the page’s implicit access with a sign-in state. Do not fetch admin data until session bootstrap confirms an authenticated session.
2. Make `POST /api/admin/auth` establish a secure session. Prefer a short-lived, server-validated, `HttpOnly`, `Secure` in production, `SameSite` cookie; pair cookie-authenticated mutations with CSRF/origin protection. If retaining bearer tokens instead, define expiry/revocation and never put them in URLs or logs.
3. Enforce authorization on **every** admin read and mutation route, including stats, users, credits, modal diagnostics, provider settings/tests, dubbing tests, and any new routes. Protect the admin document or serve a harmless shell that cannot expose data until authenticated.
4. Remove usable default credentials. Require deployment configuration; compare secrets safely and do not echo credential values.
5. Return `401` for expired/missing sessions and `403` for authenticated users lacking a required permission (if roles exist). Add logout/session-expiry handling.
6. For provider credentials, return only `configured`, safe masked metadata, and non-secret settings. A blank key on update should mean “retain current key” only if that behavior is explicit; otherwise require a deliberate replace/clear action.

**Gate:** unauthenticated API requests fail consistently; a valid sign-in enables the shell; logout/expiry clears protected data and returns to sign-in; no API key is returned in full.

### Step 2 — Health, overview, and traffic contracts

**Files:** `server/admin_routes.py`; `server/db.py` (only for verified DB-backed counts/indexes); optionally `server/admin_telemetry.py` (new aggregation/health helpers); `server/test_server_api.py`; `server/test_db.py` if migrations/queries change.

1. Replace misleading fields in `/api/admin/stats` without silently redefining legacy fields used elsewhere. Prefer a versioned or additive admin contract.
2. Add a health response such as `GET /api/admin/health` with `checked_at`, overall state, and individually timestamped checks for API, queue worker heartbeat, provider connection/configuration, and storage/media **only where real checks exist**. Report `unknown` when a check is unavailable. Report GPU only if the deployed platform exposes a verified runtime signal.
3. Add an overview response such as `GET /api/admin/overview?window=24h` containing explicitly defined counts/time window, source timestamps, and missing-data markers. Keep separate count queries aligned with DB status semantics.
4. Define aggregate traffic response such as `GET /api/admin/traffic?from=...&to=...&group_by=day`. Include query range, timezone, metric definitions/source, `generated_at`, and points. Do not rebrand the current placeholder visitor/bot values as telemetry.
5. If no analytics source exists, add a short design/data decision first: event names, privacy/data minimization, deduplication definition for visitors/sessions, retention, timezone, and backfill limits. Instrument the server or connect an approved analytics source before charting historical visits. Until then the screen must return a clear unavailable/not-connected state.
6. Add tests for empty DB, non-empty DB, invalid ranges, timezone boundaries, failed health dependency, and absent analytics source as applicable.

**Suggested contract shape (illustrative schema, not fixture values):**

```json
{
  "generated_at": "ISO-8601 timestamp",
  "window": { "from": "ISO-8601", "to": "ISO-8601", "timezone": "UTC" },
  "metrics": {
    "active_jobs": { "value": 0, "definition": "queued + processing", "available": true },
    "completed_jobs": { "value": null, "definition": "done in window", "available": false }
  }
}
```

Treat this as a shape example only. Do not ship example values as real results. Prefer a clean, consistent schema that fits existing response conventions.

### Step 3 — Jobs overview/list/detail and retry

**Files:** `server/admin_routes.py`; `server/db.py` if query helpers/indexes are needed; `server/admin_ui/api.js`; `server/admin_ui/screens/overview.js`; `server/admin_ui/screens/jobs.js`; `server/admin_ui/components.js`; `server/test_server_api.py`.

1. Add a server-paginated jobs endpoint: `GET /api/admin/jobs` with validated `q`, `status`, `target_language`, `owner`, `created_from`, `created_to`, `sort`, and pagination/cursor parameters. Return `items`, `next_cursor` or page metadata, and `generated_at`.
2. Add `GET /api/admin/jobs/{job_id}` with only persisted/derivable details, output/input links, current state, timestamps, and a failure reason when one exists.
3. Add or connect `POST /api/admin/jobs/{job_id}/retry` only after confirming retry semantics. Require an idempotency key or equivalent duplicate protection if the processing model permits it. Enforce retryable status server-side.
4. Implement Overview summaries/recent jobs and Jobs filters, sorting, pagination, details, and retry confirmation. Synchronize filters/page with the URL. Keep the selected row context on drawer close.
5. Ensure polling updates data without replacing focused controls, resetting filters, or announcing every unchanged value. Display last successful refresh and stale age; pause/resume polling explicitly.

### Step 4 — Project history and actual media URLs

**Files:** `server/admin_routes.py`; `server/db.py` after schema inspection; `server/admin_ui/screens/projects.js`; shared media/detail helpers in `components.js`; `server/test_server_api.py` and `server/test_db.py` where applicable.

1. Add server-paginated `GET /api/admin/projects` and `GET /api/admin/projects/{project_id}`. Include only stored values or explicitly derived values: source/target language, format/aspect ratio, voice, created/completed timestamps, export settings, and per-record artifacts.
2. Return a URL that resolves to the actual project output, not a shared sample path. Verify authorization for media delivery; use expiring/signed URLs if deployment requires them.
3. Handle missing/deleted media without presenting a broken player. Provide clear unavailable status and only offer regeneration/retry if a supported operation exists.
4. Remove hard-coded format/voice values and any gallery behavior based solely on the latest 20 overview rows.

### Step 5 — User search and credit adjustment

**Files:** `server/admin_routes.py`; `server/db.py` for safe query/ledger transaction only after schema/policy approval; `server/admin_ui/screens/users.js`; shared dialog/alert in `components.js`; `server/test_server_api.py` and `server/test_db.py` as needed.

1. Add server-side `q` search and pagination to `GET /api/admin/users`; do not download the full account table into the browser for filtering.
2. Confirm credit policies: allowed adjustment range, zero/negative balances, and required reason. Validate on the server, not only in the dialog.
3. Extend the adjustment endpoint to accept a reason and idempotency token, perform the adjustment transactionally, and return the updated balance. If auditability is required, add a ledger migration storing actor, timestamp, delta, reason, and resulting balance.
4. Build a confirmation dialog with user email, current balance, signed change, reason, and projected balance. Require explicit confirm, disable while pending, refresh the affected row, and show the returned balance. On failure, keep the dialog and entered values so the operator can correct/retry safely.

### Step 6 — Engine settings and diagnostic test flows

**Files:** `server/admin_routes.py`; `server/engine/gemini_dubber.py` only if the verified provider-config contract needs adjustment (preserve unrelated edits and review diff carefully); `server/admin_ui/screens/engine.js`; `server/admin_ui/api.js`; `server/admin_ui/components.js`; backend API tests.

1. Define a safe `GET /api/admin/gemini/config` response that omits the secret, plus an update contract that supports explicit replace/retain/clear semantics.
2. Validate provider type, URL, model, and secret server-side; return field-addressable validation errors without including secret contents.
3. Make test connection results identify provider/model, outcome, and measured latency where available. Clarify in the UI whether testing current saved values or edited unsaved values.
4. Keep direct dubbing test in a separate diagnostic section. Define upload size/type/duration constraints and resource limits. Return stage/progress if the operation can be asynchronous; otherwise make the in-flight wait and timeout/error states clear.
5. Use an operation-specific status region and transcript result. Do not auto-play output or announce every elapsed timer tick.
6. Treat engine worker logs as a dependency: do not show fabricated static log lines as live activity. If streaming/log API is unavailable, label the section as unavailable or omit it.

### Step 7 — Frontend shell, screen wiring, and static assets

**Files:** `server/admin.html`; new `server/admin_ui/styles.css`, `api.js`, `app.js`, `components.js`, and six screen modules listed in Section 16; `server/main.py` or `server/admin_routes.py` for static asset mount; backend/frontend API tests as supported by repository conventions.

1. Reduce `server/admin.html` to semantic app shell, sign-in scaffold, skip link, navigation landmark, main landmark, and module/style links. Remove inline `onclick` handlers and one-off inline styles.
2. Serve assets same-origin under `/admin-assets/` using FastAPI `StaticFiles` or an equivalent route. Preserve normal cache behavior for versioned/deployed assets; avoid exposing data files via a broad static mount.
3. Implement an API wrapper that handles credentials, JSON/text errors, `401` session expiry, abort/cancellation for superseded searches, and consistent response parsing.
4. Implement route parsing/history for six screens and query-string state for filters/pagination. Escape data via DOM text APIs; do not concatenate untrusted user content into `innerHTML`.
5. Build shared components once and wire each screen to the verified contracts from Steps 2–6. Keep traffic unavailable until its source is approved and connected.
6. Add explicit permission-denied, no-results, first-use empty, loading, stale, API error, and mutation result states in each relevant screen.

### Step 8 — Responsive and accessibility finishing work

**Files:** `server/admin_ui/styles.css`; semantic markup in `server/admin.html` and screen modules; `server/admin_ui/components.js`; add focused UI verification artifacts only if the project has a suitable browser test setup.

1. Implement desktop sidebar, compact tablet navigation, and a mobile drawer with proper focus management and Escape behavior.
2. Verify the table mobile strategy screen-by-screen (stacked labeled rows or intentional horizontal scrolling for true tabular comparison); do not allow whole-page horizontal overflow.
3. Add `aria-current`/tab semantics, associated labels and descriptions, `aria-live` mutation/refresh feedback, focus-visible styling, modal focus trap/return, keyboard controls, reduced-motion support, and contrast-safe states.
4. Test keyboard-only navigation, 200% zoom/reflow, long email/ID/title strings, empty/large datasets, slow/offline responses, expired session, denied permission, and narrow viewport.

## 18. Concrete state-transition behavior

Apply the shared state model from Section 8 consistently:

| State | Required behavior |
|---|---|
| Initial loading | Keep heading/navigation visible; show row/card skeletons only in the loading region; mark the region busy; do not show placeholder metric values as if loaded. |
| Empty dataset | Show a concise explanation and relevant next action (for example, clear filters or wait for first job). Distinguish no records from analytics not connected. |
| No search matches | Preserve search/filters, say no records match, and offer “Clear filters.” This is not an API error. |
| Stale data | Keep last known values visible with “Updated [time]” and a stale label; provide Retry/Refresh; never show stale health as currently healthy. |
| Request error | Show a human-readable message in the affected section, preserve usable prior data, offer Retry, and log diagnostic detail without exposing secrets. |
| Partial error | Leave successful panels interactive; isolate the failed panel and its retry. Do not blanket the whole dashboard with a global error. |
| Mutation pending | Disable only the relevant submit action and duplicate triggers; show progress text/spinner; keep unrelated navigation/data usable where safe. |
| Mutation success | Confirm with a specific outcome, update/reload the affected record, and announce it once through a polite live region. |
| Mutation failure | Keep user input and context, explain what failed and the next step, re-enable safe retry, and avoid generic “Something went wrong” where a server detail can be safely mapped. |
| Confirmation | Name the target and consequence (especially credit delta or retry job ID). Default focus to the safe cancel action for high-impact changes; require a separate explicit confirmation. |
| Permission denied | Explain access is unavailable; hide/disable the action consistently. On `403`, do not loop login; on `401`, clear protected state and show sign-in/session-expired message. |
| Retry action | Permit only documented retryable status; use duplicate protection; show accepted/queued result or actionable failure; refresh details and queue counts. |
| Polling | Show last successful refresh and an explicit pause/resume control. Do not flash loading skeletons on every refresh, steal focus, or announce unchanged values. |
| Connection/test state | Show Not checked → Testing → Connected/Failed with test time and useful next step; never infer healthy state from configuration being present. |
| Unsaved settings | Mark form dirty, warn before leaving, and let the operator stay or discard edits. On save failure, preserve values and field errors. |

## 19. Delivery phases, dependencies, and verification gates

The phases in Section 13 describe product priority. Use this dependency order for implementation: authentication/contracts → health and data APIs → jobs/projects/users/engine screens → traffic only when telemetry exists → responsive/accessibility hardening. Do not block truthful operations screens on analytics if that dependency is not ready; the Traffic & Usage page can ship with an explicit unavailable state.

### Required verification

- **Backend:** pytest coverage for auth required/allowed/expired/denied paths; pagination/filter validation; empty and populated datasets; project-specific media paths; credit bounds/idempotency/transaction behavior; provider secrets absent from responses; health dependency failure; traffic unavailable/valid ranges.
- **Frontend:** manually or with the repo’s existing browser test tool verify route deep links/back-forward; each loading/empty/no-match/error/stale/partial/permission/mutation state; no duplicate credit/retry submissions; API 401/403 behavior; unsaved provider settings; data escaping.
- **Responsive/accessibility:** verify desktop, tablet, and narrow mobile widths; keyboard-only flows; visible focus and focus return; accessible names/status announcements; zoom/reflow; reduced motion; contrast; long labels and IDs.
- **Data integrity:** compare displayed counts to direct DB queries for documented windows; check timezone/day boundaries; verify each project opens its own media; confirm traffic data is sourced and not a placeholder.
- **Regression:** exercise existing mobile app API behavior and existing admin route aliases. Keep changes scoped to admin functionality and explicitly inspect diffs to avoid including unrelated user modifications.

### Release acceptance gate

Do not call the redesign complete until all of the following are true:

1. Admin authentication is enforced server-side on every admin endpoint, and secrets are not exposed to the browser.
2. All six approved screens are navigable, responsive, and bound to verified contracts. Traffic is either real and defined or explicitly marked unavailable.
3. No static GPU/worker/provider claim, placeholder traffic metric, hard-coded project metadata, or shared generic output URL is presented as live per-record data.
4. Every screen handles loading, empty, stale, error, and permission states; every consequential mutation has confirmation and success/failure feedback.
5. Keyboard, screen-reader, zoom/reflow, and reduced-motion checks pass for primary workflows.
6. Existing API consumers/routes and unrelated workspace changes are preserved.

## 20. Coding-agent kickoff checklist

Before making implementation edits, the coding agent should:

- [ ] Read this specification and repository `AGENTS.md` instructions.
- [ ] Confirm current working directory and inspect `git status`; preserve all pre-existing modifications and untracked user data.
- [ ] Re-open current `server/main.py`, `server/admin.html`, `server/db.py`, engine config helpers, and existing server tests rather than relying only on this document.
- [ ] Confirm actual DB schema, existing export/media relationship, auth deployment assumptions, and whether telemetry is available.
- [ ] Write down the API/data contract deltas and any unresolved decisions before wiring UI to fields.
- [ ] Implement in the ordered steps above; keep FastAPI + vanilla ES modules unless a concrete repo constraint justifies another stack.
- [ ] Do not fabricate metrics or visual data. Use explicit unavailable states until a verified source exists.
- [ ] Verify targeted backend/UI behavior and inspect final diffs. Do not stage, revert, or modify unrelated work such as `server/engine/gemini_dubber.py`.
- [ ] Report changed files, endpoints/contracts added or changed, verification performed, and any unresolved telemetry/auth dependencies.


