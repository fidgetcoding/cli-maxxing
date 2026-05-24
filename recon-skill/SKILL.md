---
name: recon
description: Pre-build competitive reconnaissance. On build-intent, OFFER it as a one-line question first — do NOT auto-run. Nate sometimes intentionally builds a free version of a known paid product and doesn't need the whole landscape. When run, it sweeps GitHub + web for existing free and paid options, ranks the top ~10 competitors and best repos in a comparison table (maturity, license, price, install, key features, activity), then finds where an edge exists (or honestly says it's a red ocean). Fires the OFFER whenever Nate says "build / create / make / let's do / I want to build / start a new <thing>", or asks "does this exist / what's out there for <thing>". Output is a discussion, not code — building starts only after the verdict. Invoke directly as /recon <thing> to skip the offer and run.
allowed-tools: Bash, WebSearch, WebFetch, Read, Write, Task, Agent
---

# recon — look before you build

The rule (memory `feedback_prior_art_check_before_building`): **prior-art sweep BEFORE code, not after.** talk2me is the scar — a whole hands-free voice loop for Claude Code built and shipped before discovering `mbailey/voicemode` (MIT, ~1.2k★) does nearly the same thing and Anthropic ships native `/voice`. The check belongs at turn one.

This skill produces a **ranked landscape + edge analysis + GREEN/YELLOW/RED verdict**. It does NOT build. Building starts only after the discussion.

## When this fires — OFFER first, don't auto-run

On build-intent ("build / create / make / start a new / I want to build / let's do" a product, tool, library, app, CLI, MCP server, skill, extension, or category-named feature) — and on "does X exist?" / "what's out there for X?" — **ask one line, then wait:**

> Want me to run `/recon` first — sweep what exists + find the edge? Or do you already know the landscape (e.g. you just want a free version of a paid tool)?

- **Yes / "do recon"** → run the full procedure below.
- **"No, I know it exists, I want a free version"** (a common, legit Nate move) → skip the landscape sweep, but offer the lighter cut: *"Want the top incumbent's feature list as a build target so the clone hits parity?"* — then build.
- **"Just build it"** → respect it, build, no recon.

Direct `/recon <thing>` skips the offer and runs immediately.

**Never auto-run the full sweep without asking.** Nate sometimes builds a known duplicate on purpose (a free version of something good). The offer is the safeguard; the call is his. Skip the offer entirely for trivial scripts, vault edits, or bespoke glue.

## Procedure

### 1. Frame the thing (1 line)
State what's being built in one sentence + its category name(s). Derive 4-8 search terms: the obvious name, the category, adjacent categories, and the "X for Y" framing (e.g. "voice loop", "voice MCP Claude Code", "hands-free dictation terminal").

### 2. Sweep (parallel, broad)
Run these concurrently. For a broad/unfamiliar space, spin 3-5 parallel `Agent` (researcher/Explore) calls — one per sub-angle — to hit the top ~10 fast. For a narrow space, inline is fine.

- **GitHub:** `gh search repos "<terms>" --limit 20 --sort stars` (gh CLI is authed; the GitHub MCP token is DEAD — never use `mcp__github__*`). Also `gh search repos` per alternate term. Capture stars, license, pushedAt.
- **Web:** `WebSearch` the category + "open source", "alternatives", "vs", "best <category> 2026". Hit product directories (Product Hunt, AlternativeTo, lobehub/MCP directories, npm, PyPI) where relevant.
- **Paid/commercial:** explicitly search for the SaaS/paid incumbents, not just free repos — pricing pages, "<category> pricing".
- `WebFetch` the 2-3 most relevant repos/sites to confirm features + license + price (don't trust the search snippet alone — look-don't-guess).

### 3. Capture each competitor
For the top ~10 (mix of repos + products), record: **name · what it is · free/paid (+ price) · license · maturity (stars / users / age) · install path (MCP / CLI / app / lib) · 1-2 standout features · last active**.

### 4. Rank + table
Order by relevance-to-what-Nate-wants (not just popularity). Render a comparison table. **Keep cells narrow — Nate reads on an 80-col Ghostty** (per `feedback_table_rendering_keep_cells_narrow`): 2-col ≤30 chars, 3-col ≤20, 4+ col → switch to per-competitor bullets. Lead with a one-line "best overall" pick + why.

### 5. Find the edge
The actual point. Answer plainly:
- Is there an **unclaimed niche** (a feature/integration/platform nobody covers)?
- A **free-vs-paid gap** (paid incumbent, no good free one — or vice versa)?
- A **quality/UX gap**, or an **agent-agnostic / interoperability angle** the others miss?
- Does Nate have an **unfair advantage** here (existing audience, adjacent tool, distribution)?
- Or is it a **red ocean** where a mature free incumbent already wins?

Be honest. Do NOT manufacture novelty (the talk2me lesson). If the differentiator is "I'd understand my own code" or "for content/learning", say that's the value — it's real, but it's not a moat.

### 6. Verdict + discuss
End with one:
- **🟢 GREEN** — novel, or a clear unclaimed edge. Worth building. Name the wedge.
- **🟡 YELLOW** — crowded but a real wedge exists. Build only if you commit to that wedge; name it + the work it implies.
- **🔴 RED** — a mature free incumbent already does this. Reconsider: contribute to the existing one, fork for the one missing feature, or build only for learning/content (state which).

Then **stop and have the conversation.** Don't roll into building. Nate decides after seeing the landscape.

## Output shape

```
RECON: <thing in one line>

LANDSCAPE (top N)
<ranked table or per-competitor bullets — narrow cells>

BEST OF BREED: <pick> — <one line why>

THE EDGE
<unclaimed niche / gaps / Nate's advantage — or "red ocean, here's why">

VERDICT: 🟢/🟡/🔴 <one line>
<the wedge to commit to, or the reason to skip/contribute instead>

Sources: <markdown links to every repo/page used>
```

## Hard rules

- **Sweep before any code.** This is the whole point — never let a build start without it for in-scope requests.
- **gh CLI for GitHub, not the MCP** (token dead). `gh search repos`, `gh repo view <owner/repo> --json ...`.
- **Look, don't guess** — WebFetch/`gh repo view` the top hits to confirm license + price + activity. Don't assert features from a snippet.
- **Don't overclaim novelty.** If it exists, say so first sentence. Honesty over hype.
- **Cite sources** — markdown links for every competitor named.
- Narrow table cells (80-col Ghostty). EST timestamps. "Nate" never "Nathan".
- Output is a discussion + verdict. Building is a separate, later step Nate green-lights.
