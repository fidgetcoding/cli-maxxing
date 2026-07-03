---
name: agent-business
description: Turn any app or human service into an AI agent business (Angus Sewell 6-op playbook, 2026-07-03). Use whenever Nate wants to build an AI agent that texts clients, a texting coach/tutor/advisor/consultant agent, an SMS/iMessage/WhatsApp agent, a service-as-an-agent business, or says "turn this app into an agent", "AI coach business", "agent that replaces a [coach/tutor/advisor]", or wants the app-to-agent playbook applied to a market. Also invocable directly as /agent-business.
---

# /agent-business — turn any app into an AI agent business

Every winning app is a cheap self-serve version of a service humans pay far more for. Rebuild that human service as an AI agent living between app and human: same outcome, fraction of the human's price. Worked example: texting AI fitness coach at $700/mo vs a $1,500+/mo human coach.

**Source of truth:** `/Users/nathandavidovich/BRAIN2/02-Sources/SRC-2026-07-03-agent-business-build-guide.md` (archived PDF alongside).

Run the 6 ops in order. Each op below = objective + the moves. Verbatim prompts live in the source note — pull them when executing.

## Op 1 — Pick the market
- App Store → Top Charts → category with a clear human equivalent. Name the app's outcome (lose fat, file taxes, learn Spanish), the human pro selling it, and their monthly price.
- Only pick categories where the human charges MONTHLY and the outcome is measurable — coach, tutor, advisor, consultant. Skip one-off services.
- Wedge: same outcome, agent-delivered, fraction of cost.

## Op 2 — Reverse-engineer the data
- Don't copy app features. Work backwards from the outcome → the 3–6 signals proving it's happening → raw data points per signal (units + frequency).
- Schema: always a `users` table keyed by PHONE NUMBER (people text from one number, not one inbox — phone is the join key, not email) + one table per signal (e.g. `food_log`, `workout_log`, `weight_log`, `goals`).
- Postgres on Supabase; Airtable only for no-code. Schema-design prompt in the source note.

## Op 3 — Pick the stack
- Three pieces: **brain** (Claude — decides + writes every reply) · **builder** (n8n; Gumloop only if allergic to node graphs) · **database** (Postgres/Supabase).
- Give the agent DB tools: `log_*` per signal + `get_client_state`.
- Start on n8n even if the client is non-technical: one webhook, one agent node, one Postgres node.

## Op 4 — Wire it to their texts
- No app to download — the client texts a number. Connector inbound webhook → builder trigger; agent gets a `send_message` tool on the connector's send API. Trigger fires on every inbound `{phone, text}`.
- Connectors: LoopMessage (iMessage — converts best, blue bubble = trust, needs a Mac online, from $24.99/mo) · Twilio (SMS+WhatsApp — zero-hardware start) · Unipile (multi-channel).
- Connector is swappable later without touching the agent — start Twilio if no Mac.

## Op 5 — The inbound brain
- Per-message loop: look up client by phone (create + 3 onboarding questions if new) → classify text (log-type vs question) → call the matching log tool with parsed values → unknown values looked up via Apify/web, NEVER guessed → reply 1–2 warm sentences + one specific next action.
- Make the agent ask before assuming — one clarifying question beats a wrong log that poisons every later nudge. Full system prompt in the source note.

## Op 6 — The proactive coach
- The check-in is what clients actually pay for. Schedule trigger 2×/day max (over-texting gets muted).
- Per active user: read last 7 days of logs vs `goals` → decide the SINGLE most useful nudge → send ONE short, specific text → log what was sent so the next run doesn't repeat it. Cron prompt in the source note.

## Loadout
Claude (brain) · n8n (orchestrator) · Postgres/Supabase (DB) · LoopMessage / Twilio / Unipile (messaging) · Apify (lookups/enrichment). All free-tier or BYO except the connector.

## Guardrails
- Business model first: name the human price and the agent price BEFORE building anything.
- Ship the inbound brain (Op 5) before the proactive cron (Op 6) — reactive must work before proactive.
- Per-client data isolation from day one (per-client tables or client_id scoping).
