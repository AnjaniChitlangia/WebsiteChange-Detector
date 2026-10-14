# Watchtower AI

**The internet changes. Never miss what matters.**

Watchtower AI monitors public web pages in a real headless browser, ignores the noise that changes on every load (clocks, live counters, tokens, ads, rotating banners), and explains the changes that matter: what changed, where, why it may matter, how confident it is, and a heuristic **Change Impact Score**.

Built for the VinnovateIT *Website Change Detector* challenge.

---

## Quick start

### Option A: Docker (one command)

```bash
docker compose up --build
```

Open **http://localhost:4000** and click **Try the live demo**. This starts PostgreSQL, Redis and the app (API, worker, headless Chromium and the built React app), runs the migrations and seeds a demo account.

### Option B: Local development (Windows, macOS, Linux)

Requires **Node.js 20+** and **PostgreSQL**. Redis is optional; without it an in-process queue is used.

```bash
# 1. Start Postgres + Redis (or point DATABASE_URL at any Postgres, e.g. Neon/Supabase)
docker compose up -d db redis

# 2. Install
npm install

# 3. Configure
cp .env.example apps/server/.env        # Windows: copy .env.example apps\server\.env

# 4. Headless Chromium, database tables and the demo account
npm run setup

# 5. Run API + worker (:4000) and the web app (:5173)
npm run dev
```

Open **http://localhost:5173**, then either create an account or click **Use the demo account**.

> **If you used the `D:\WebsiteChangeDetector` folder:** its `node_modules` folder contains *Linux* packages that were downloaded for testing. Delete `node_modules`, `npm-cache`, `parts` and `deps.tgz` first, then run `npm install`.

Demo login (seeded): `demo@watchtower.ai` / `watchtower-demo`

---

## Two-minute judge demo

Everything below is a **real** check: real Chromium, real HTTP, real database. The only controlled thing is the test website, served by Watchtower itself so you can change it on demand.

1. Click **Try the live demo**. You land in **Simulation lab**.
2. **Add the demo store.** A baseline snapshot is captured. Watchtower loads the page twice and learns anything that flickers between loads.
3. **Reload with new noise only.** The clock, viewer counter, rotating banner, ad and session token all change. Result: *Only noise changed*, no alert, and the ignored items are listed.
4. **Drop the Pro price.** Result: *Meaningful change*, scored **High**, with the summary "Price dropped from ₹1,499 to ₹1,199 in Pro".
5. **Open the change report:** before/after screenshots with the changed region highlighted, a word-level text diff, what/where/why explanations, confidence, and the Impact Score breakdown.
6. **Simulate an outage (HTTP 503)** or **show a CAPTCHA wall.** These show as *Check failed* (retried with backoff) or *Blocked*. They are **never** treated as content changes. Bring the site back online to get a recovery alert.
7. Open **Alerts** to see the notification centre. Each alert shows exactly which channels were *sent*, *failed* or *skipped*.

Other things to try:
- **Regions tab:** click elements on the screenshot to watch, ignore, or track a number.
- **Versions tab:** compare any two versions.
- **Notifications:** Discord webhook, Telegram, email, and the daily digest.

---

## How the core requirements are met

| Requirement | Implementation |
|---|---|
| Add URL, name, interval (15 min to 24 h); headless rendering | Add-website modal with live URL validation; intervals 15/20/25/30 min and 1/6/12/24 h; Playwright Chromium in an isolated context per check |
| Scheduler + job queue with timeouts and retries; public pages only, no credentials | DB-driven scheduler → **BullMQ** (Redis) with an in-process fallback; 30 s navigation timeout; 3 attempts with exponential backoff and jitter; URLs containing credentials are rejected and no cookies are kept |
| Each check saves text + screenshot; new snapshot only when the content hash changes | Every check stores a `Capture`; a `Snapshot` (blocks + screenshot) is written **only** when the SHA-256 of the *normalized* text changes |
| Noise filtering for timestamps, counters, ads, rotating banners and random tokens, plus sensitivity | Masking rules (dates, times, relative times, live counters, UUIDs, hex/JWT/session tokens, render timings), default noise selectors (ads, carousels, cookie banners), **double-load volatility learning**, user feedback ("ignore lines like this"), Low/Balanced/High sensitivity |
| Visual picker for watch/ignore regions (CSS selectors) | **Regions** tab: click elements on the latest screenshot to watch, ignore, or track a number; saved as CSS selectors (also editable as text) |
| Text diff, highlighted screenshot diff, compare any two versions | Line and word diff, pixel diff (pixelmatch) with ignored regions masked and changed regions clustered into boxes; side-by-side and pixel-diff views; **compare any two snapshots** |
| Alerts via email / Telegram / Discord with summary and diff link; no duplicates; daily digest | Nodemailer SMTP, Telegram Bot API, Discord webhooks; a DB-unique dedupe key plus an oscillation guard; per-user digest at a chosen local hour; every delivery attempt is logged honestly |
| Per-page timeline; dashboard with last checked, last changed, status (OK, error, blocked) | Searchable timeline (changes, failures, quiet checks), dashboard with search, filters, sort and pagination, charts, and a recent-alerts list |

### The four design questions

**1. Is a site outage or CAPTCHA a change?** No. Every fetch is classified *before* comparison (`engine/pageState.ts`):
- 5xx responses, timeouts, connection errors and empty pages count as `ERROR` and are retried.
- 401/403/451 responses and CAPTCHA widgets or wording count as `BLOCKED` and are not retried.
- 429 counts as `RATE_LIMITED`, and `Retry-After` is honoured.

Failed loads are never compared with the baseline, so they cannot create changes. The user gets one failure alert per streak and a recovery alert afterwards.

**2. If 200 users watch the same URL, is it fetched 200 times?** No. URLs are normalized (case, default port, fragment, tracking parameters, parameter order) into one shared `Page`. A check renders the page **once**. Each user's `Monitor` then applies its own selectors, sensitivity and keywords to that single capture. Queue jobs are keyed by page, so duplicate requests collapse into one.

**3. How do you avoid endless alerts on pages that differ on every load?**
1. Token masking before hashing.
2. Default noise selectors.
3. Learning from a second load at baseline: anything that differs between two loads seconds apart is volatile.
4. User feedback.
5. Sensitivity thresholds.
6. A UNIQUE alert dedupe key, plus an A→B→A oscillation guard.

**4. How do you avoid hammering a site?**
- robots.txt and `Crawl-delay` are respected.
- A per-host minimum gap is enforced across all workers via a Redis lock.
- The interval floor is 15 minutes, with jitter on schedules.
- Fetches are shared between users.
- Retries are capped.
- Failing sites are checked progressively less often (×2, ×4, ×8, at most every 24 h).
- Media and known ad/tracker requests are blocked in the browser.
- The manual "check now" button has a cooldown.

### Bonus features
Keyword-only alerts · number tracking with charts · optional AI one-line summaries (Anthropic API; falls back to rule-based summaries, always labelled) · per-page RSS feed · daily digest.

---

## Architecture

```
            ┌───────────── React + Vite + Tailwind (apps/web) ─────────────┐
            │ Landing · Dashboard · Monitor detail · Change report ·       │
            │ Compare · Alerts · Notifications · Simulation lab            │
            └───────────────────────────┬──────────────────────────────────┘
                                        │ JSON over same-origin /api (cookie session)
┌───────────────────────────── Express API (apps/server/src/api) ───────────────────────────┐
│ auth · monitors · changes/compare · alerts/settings · stats · demo-site · RSS · media     │
└──────────────┬──────────────────────────────────────────────────────┬────────────────────┘
               │ Prisma (pg adapter)                                  │ enqueue(pageId)
        ┌──────▼──────┐                                       ┌───────▼────────┐
        │ PostgreSQL  │◀───────── results ────────────────────│ BullMQ / Redis │
        └─────────────┘                                       └───────┬────────┘
                                                                      │
┌────────────────────────── Worker (apps/server/src/worker) ─────────▼──────────────────────┐
│ scheduler tick → robots.txt → host throttle → Playwright capture (SSRF-guarded routes)    │
│ → classify (OK / ERROR / BLOCKED) → per monitor: normalize + mask → hash → diff → score   │
│ → visual diff → snapshot/change → dedupe → alert → email / Discord / Telegram / digest    │
└───────────────────────────────────────────────────────────────────────────────────────────┘
```

```
apps/
  server/
    prisma/            schema.prisma, migrations, seed.ts
    src/
      engine/          pure, unit-tested logic: normalize (noise), diff, classify, score, report,
                       detect, visual (pixel diff), pageState (outage/CAPTCHA), dedupe
      capture/         Playwright capture + in-page extraction, static fallback, robots/throttle
      security/        URL validation + DNS-aware SSRF guard
      queue/           BullMQ + in-process queue, backoff policy
      worker/          scheduler, page-check pipeline, digests, retention, heartbeat
      notify/          email / Discord / Telegram, digests, optional AI summaries
      api/             Express routes, auth, serializers
      demo/            controlled demo website + simulation actions
  web/                 React app (pages/, components/, lib/)
packages/shared/       URL validation, constants and API types shared by both sides
```

---

## Security

- **SSRF protection.** Only `http(s)` URLs are accepted, and URLs with credentials are rejected. Hostnames are resolved and **every** resolved address must be public. Every request the headless browser makes (redirects, sub-resources) is re-checked, and the redirect chain is verified again after load. The only exception is the built-in demo site, and only when `DEMO_MODE=true`.
- **Secrets stay on the server.** API keys, SMTP passwords and the Telegram bot token live only in environment variables. Discord webhook URLs are write-only and returned masked.
- **Sessions.** JWT in an httpOnly, SameSite=Lax cookie, plus a same-origin check on state-changing requests. Passwords are hashed with bcrypt. Auth endpoints are rate-limited.
- **Input validation.** Zod on every input. Selector syntax and length are bounded. User regexes are length-limited and screened for catastrophic patterns.
- **Browser isolation.** Each check runs in a fresh browser context with no cookies or storage. Downloads and service workers are disabled.
- **Headers.** Helmet with a strict Content-Security-Policy for the app.

## Honesty rules the app follows

- A delivery is shown as *sent* only when the provider accepted it. Unconfigured channels show *skipped*, with the reason.
- Status indicators come from a real worker heartbeat ("Worker online · BullMQ · Chromium"). The dashboard says how often it refreshes.
- The Impact Score is always labelled a heuristic, with every point attributed to a named factor.
- The seed creates accounts and monitors only. **No fake history.** Every check, change and alert in the app comes from a real run.
- If Chromium is unavailable, Watchtower falls back to a static HTML fetch and labels it "Static HTML" (lower confidence, no screenshot).

---

## Configuration

See [`.env.example`](.env.example). Key variables:

| Variable | Purpose |
|---|---|
| `DATABASE_URL` | PostgreSQL connection string (required) |
| `REDIS_URL` | Enables BullMQ (recommended). Empty means in-process queue |
| `JWT_SECRET` | Required in production |
| `APP_URL` | Public web URL used in alert links and RSS |
| `ROLE` | `all`, or run `api` and `worker` separately to scale |
| `DEMO_MODE` | Serves the controlled demo site and one-click demo login |
| `SMTP_*`, `TELEGRAM_BOT_TOKEN` | Enable email and Telegram delivery (Discord needs no server config) |
| `ANTHROPIC_API_KEY`, `LLM_MODEL` | Optional AI summaries |
| `RESPECT_ROBOTS`, `HOST_MIN_GAP_MS`, `WORKER_CONCURRENCY` | Politeness and throughput |

## Tests

```bash
npm test
```

There are 88 tests (Vitest):
- URL validation and SSRF (including DNS-rebinding style resolution).
- Noise masking and volatility learning.
- Change detection and classification.
- Impact scoring.
- Outage and CAPTCHA classification.
- Retries and backoff.
- Duplicate and oscillation alert suppression.
- Queue de-duplication and the retry cap.
- Pixel diff and region clustering.
- An **end-to-end test** that renders the demo site in real Chromium. It checks that a noise-only reload keeps the same hash, that a price drop is detected (with exactly one visual region, at the price), and that an outage and a CAPTCHA are classified as failures.

The end-to-end test skips itself if Chromium isn't installed (`npm run browsers`).

## Deployment

The app is one Docker image (API, worker, Chromium and the web build). Any container host with Postgres works, for example Render, Railway, Fly.io or a VM:

1. Provision Postgres (e.g. Neon, Supabase) and Redis (e.g. Upstash).
2. Deploy the `Dockerfile`. Set `DATABASE_URL`, `REDIS_URL`, `JWT_SECRET`, `APP_URL` and optionally `SMTP_*`, `TELEGRAM_BOT_TOKEN` and `ANTHROPIC_API_KEY`. Set `DEMO_MODE=false` for a production deployment, or keep it `true` for judging.
3. To scale, run one service with `ROLE=api` and N services with `ROLE=worker`. The Redis locks keep the scheduler, per-host throttling and digests correct across workers.

The web app is served by the API in production (same origin, so no CORS and the cookie sessions keep working). If you prefer Vercel or Netlify for the frontend, add a rewrite that sends `/api/*`, `/feeds/*` and `/demo-site/*` to the API host so it stays same-origin.

## Notes and limitations

- The worker needs internet access to monitor real sites. Behind a corporate proxy, set `HTTPS_PROXY`.
- CAPTCHAs are detected and reported, never solved or bypassed.
- Screenshots are capped at 3000 px of page height (`MAX_SCREENSHOT_HEIGHT`). Text extraction covers the whole page.
- A browser extension is not included; the in-app visual picker covers region selection.
