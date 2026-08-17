---
name: landing-ab
description: Build every landing page "self-driving" per the 5-level PostHog ladder (Angus Sewell field guide, 2026-07-03). Use whenever the user asks to build, make, create, ship, spin up, redo, or redesign a landing page, marketing site, marketing page, splash page, one-pager, waitlist page, lead-magnet page, promo page/site, coming-soon page, or product page — or wants A/B testing, PostHog, analytics, heatmaps, session replay, conversion optimization, feature flags, or per-visitor personalization added to an existing page. Also invocable directly as /landing-ab.
---

# /landing-ab — self-driving landing pages

Every landing page ships able to watch, test, and rebuild itself. No more frozen billboards.

**Source:** Angus Sewell's self-driving landing page field guide (2026-07-03). The ladder: L1 Static → L2 Watch → L3 Test → L4 Auto-iterate → L5 Personalize.

## Non-negotiable defaults on every new landing-page build (L1+L2 baked in)

1. **Tag the primary CTA** with `class="signup-cta"` — turns the L3 A/B test into a two-minute flag edit instead of a redeploy.
2. **Wire PostHog at build time**, not later:
   ```js
   // npm i posthog-js — in <head>/app entry (static page: HTML <script> snippet from PostHog docs)
   import posthog from 'posthog-js'
   posthog.init('<YOUR_PROJECT_KEY>', {
     api_host: 'https://us.i.posthog.com',  // MUST match key region (US/EU) or 401s + no data
     defaults: '2026-05-30',
     enable_heatmaps: true
   })
   ```
   Ask the user once for the PostHog project key + region. Unknown → leave `<YOUR_PROJECT_KEY>` and flag it in `docs/LP-OPS.md`.
3. **Stub the experiment flag hook** so L3 is pre-wired:
   ```js
   posthog.onFeatureFlags(function () {
     if (posthog.getFeatureFlag('landing-ab') === 'test') {
       // render version B
     }
   })
   ```
4. **Light mode default** — never ship `prefers-color-scheme: dark` as default.
5. **Drop `docs/LP-OPS.md`** into the repo (see template below) so the optimization loop survives the session.

Division of labor: `copywriting` owns the words, `high-end-visual-design` / `ui-ux-pro-max` own the look — this skill owns instrumentation + the optimization loop.

## docs/LP-OPS.md template (generate per repo, fill in repo/URL specifics)

- **L3 · Run an A/B test:** add `disable_web_experiments: false` to init → PostHog Toolbar → Experiment → New → pick `signup-cta` → edit variant B → set primary metric → Launch (auto 50/50). Call it ONLY at **95%+ chance to win AND ≥50 exposures/variant**. Set run length BEFORE launch; don't peek — early stops ship false winners.
- **L4 · Weekly optimizer loop:** connect PostHog MCP read-only:
  `claude mcp add --transport http posthog "https://mcp.posthog.com/mcp?readonly=true" -s user`
  Weekly agent prompt:
  ```
  You're my landing-page optimizer. Using the PostHog MCP (read-only), pull results
  for experiment 'landing-ab'. If a variant has >95% chance to win and ≥50
  exposures/variant, reply with: the winner, the % lift, and ONE specific change to
  test next. Wait for my "approved". On approval, edit the page in GitHub repo
  [me/site], open a PR, summarize. Never merge without my approval.
  ```
  Schedule via GitHub Actions cron (Claude Code headless). Keep the human-approval gate; write access only on the deploy step.
- **L5 · Personalize:** capture interest signals (`posthog.capture('viewed_pricing')`) → dynamic cohort ("performed X in last 30 days") → multivariate flag `lp-personalize` with JSON payload per variant, release condition targeted at the cohort:
  ```js
  posthog.onFeatureFlags(function () {
    const r = posthog.getFeatureFlagResult('lp-personalize')
    if (r?.payload) applyContent(r.payload)  // payload = { hero, cta, showPricing }
  })
  ```
  GDPR: cookies + GeoIP are personal data — consent banner before L5. Need real volume per cohort before trusting a tailored variant.

## After the page ships

Offer once, one line: "Ladder next steps — L3 A/B now, L4 weekly optimizer (PostHog MCP + Actions cron), L5 per-cohort personalization?"

## Existing pages

Invoked on an already-live page: retrofit in ladder order — tag CTA → add PostHog → then whatever level the user asked for. Never skip L2; everything above it is blind without data.
