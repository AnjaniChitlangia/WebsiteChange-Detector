# Watchtower AI — hackathon pitch

## The problem
The pages people depend on change without warning: a competitor's price, a university's admissions notice, a refund policy, an exam date, a government circular, an API deprecation. Checking them by hand doesn't scale. Existing "page changed" tools have a worse problem: **noise**. Modern pages differ on every load because of clocks, view counters, session tokens, ads and rotating banners. Naive diffing alerts on all of it, and people mute the alerts within a week. A monitor that cries wolf is as useless as no monitor.

## The solution
Watchtower AI renders each page in a real headless browser on a schedule, separates **signal from noise**, and explains every real change in plain language:

> **Price dropped from ₹1,499 to ₹1,199 in “Pro”.** Impact 67/100 (heuristic), confidence High.
> Where: Plans section. Why it may matter: price changes can affect purchase decisions.
> Ignored this check: 1 clock, 1 live counter, 1 session token, 1 render timing, rotating banner, ad slot.

Outages, CAPTCHAs and access-denied pages are classified as **monitoring failures, never as changes**. They are retried politely, alerted once, and followed by a recovery note.

## What makes it different (USP)
1. **Noise Intelligence.** Volatile tokens are masked before hashing. Common noise regions (ads, carousels, cookie banners) are dropped. A *second load at baseline* teaches it whatever else flickers on that specific site. Users can say "ignore lines like this", and it learns. Alerts are deduplicated in the database and A/B-test flip-flops are suppressed.
2. **Explainable Change Reports.** Every change says *what* changed (word-level diff), *where* (section heading and CSS landmark, plus a highlighted region on the screenshot), *why it may matter* (category-specific), and *how confident* the system is (with reasons).
3. **Change Impact Score.** A transparent 0–100 ranking built from configurable rules: change type (price, policy, announcement, removed section), keyword matches, watched regions and magnitude. Every point is itemised, and it is **clearly labelled a heuristic**, not a promise about real-world impact.
4. **Change Timeline.** A searchable history of every version, visual diff and failed check per page. Compare any two versions, or subscribe by RSS.

## Who it's for
- **Students and applicants:** admissions portals, scholarship pages, exam notices, results pages.
- **Small businesses and e-commerce teams:** competitor pricing and stock.
- **Compliance and legal teams:** terms, privacy and refund policies of vendors and regulators.
- **Developers:** release notes, status pages and API deprecation notices.
- **Journalists and researchers:** government circulars and public datasets.

## Built to scale
- **Shared fetches.** 200 users watching one URL means **one** headless render per interval. Each user's selectors, sensitivity and keywords are applied to that shared capture.
- **Stateless API plus horizontally scaled workers.** BullMQ on Redis; Redis locks for the scheduler, per-host throttling and digests; `ROLE=api|worker` to split them.
- **Storage stays bounded.** Snapshots are stored only when content changes; old captures are pruned; screenshots are capped in height.
- **Polite by design.** robots.txt and Crawl-delay, per-host gaps, a 15-minute minimum interval with jitter, capped retries, and progressive backoff on failing sites. That makes it a good citizen at scale.

## Real-world impact
Watchtower turns "keep refreshing that page" into a calm stream of trustworthy, explained alerts. People hear about what matters (a price, a deadline, a policy) without drowning in noise. That makes monitoring usable for everyday people, not just engineers.

## Tech
React, Vite, TypeScript, Tailwind, Recharts · Node.js and Express · Playwright (Chromium) · PostgreSQL with Prisma · BullMQ and Redis · pixelmatch · Nodemailer, Telegram and Discord · optional Anthropic summaries. 88 automated tests, including a real-browser end-to-end test of the full detection pipeline.
