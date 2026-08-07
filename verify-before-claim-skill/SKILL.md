---
name: verify-before-claim
description: >
  Verify-before-claim protocol — run BEFORE answering any question about installed MCP servers,
  active subscriptions/pricing/plans, or available AI models. Reads actual local config
  (~/.claude.json, .mcp.json, .claude/settings.json, your own reference notes) and live
  account/billing state instead of relying on memory. Refuses to confirm any model name or
  product until verified against a real source; says 'unverified:' plainly when it can't check.
  Natural-language triggers: "is X free", "am I paying for X", "what plan is X on",
  "do I have the X MCP", "is X installed", "is X cloud-only", "can I remove X locally",
  "does model X exist", "what models are available", "which MCP servers do I have".
---

# Verify Before Claim

Never answer these three question classes from memory. Check, cite, or say `unverified:`.

## 1. Installed MCP servers

- Local registry: `jq -r '.mcpServers | keys[]' ~/.claude.json` (user scope) plus `<project>/.mcp.json` if present.
- An entry with `"type": "stdio"` / a `command` field is a LOCAL process — removable with `claude mcp remove <name>`. Only `claude.ai <Name>` connectors (session-injected, no local entry) are cloud-side.
- Not in either file and not in the session's connected-server list → "not configured" — never guess.

## 2. Subscriptions / pricing / plans

Check in order; cite the first hit:

1. Your own notes on what a tool costs — whatever you keep them in. The point is that a written
   record you made beats a recollection you didn't. Calendar and task tools are the usual trap:
   several of the popular ones have a free-looking tier and an annual bill attached to the plan
   you're actually on.
2. Live account tools: `mcp__supabase__get_organization` (returns `plan`), any provider MCP that
   exposes plan/credit state, or the provider's billing page driven through a browser tool.
3. Local config / receipts / invoices.

NEVER assert "free tier" or "paid" without one of the above. If none is reachable: `unverified: could not check <provider> billing — need dashboard access or a screenshot`.

## 3. AI model names

- Claude models: verify against the `claude-api` skill reference before confirming — never from memory.
- Other providers: live models endpoint or official docs fetched this session.
- Model not found in a verifiable source → `unverified: '<name>' not found in <source checked>`. Do NOT confirm it exists; do NOT silently autocorrect to a similar real name — flag the mismatch.

## Output contract

Every answer carries: **Verdict** (CONFIRMED / REFUTED / UNVERIFIED) · **Source** (file path or tool call) · one-line evidence. If a config file doesn't exist, say so plainly ("no .mcp.json in this project"). Billing/pricing answers auto-lift to full detail.

## Test suite

`references/test-claims.md` — 5 adversarial claims with expected verdicts. Re-run all 5 after any edit to this skill; a claim answered without a cited source is a FAIL even if the verdict is right.
