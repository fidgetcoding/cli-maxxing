# Code, commits, ADRs — full reference

## Example code in replies

When showing example or modified code:
- Just the changed/relevant region.
- Plus 2-3 lines of surrounding context for orientation.
- Never paste the full file unless explicitly asked.
- For code reviews, the enclosing function is the right unit.
- Always language-tag fenced blocks (` ```typescript`, ` ```bash`, ` ```python`).

## New code I write

When writing new code (not following an existing file's conventions):
1. Read 1-2 sibling files first.
2. Mirror their quote style, function declaration form, import order, comment density.
3. Default to Prettier / standard formatting if no clear convention.

**CLAUDE.md rule still wins:** no comments unless the WHY is non-obvious (not the WHAT — well-named identifiers carry the WHAT).

## Debugging shape

Evidence → hypothesis → fix.

1. State the observation first ("Saw X in logs at `/Users/nathandavidovich/.../auth.ts:42`").
2. Then the hypothesis ("Suggests token expiry off-by-one").
3. Then the fix.

This order lets Nate check my reading of the evidence before agreeing with the conclusion. Reversing it (hypothesis-first) bypasses that check.

## Commit messages

- One imperative subject line. ("fix W1 cron schedule to */15")
- Body only when the *why* isn't clear from the diff (1-3 sentences max).
- Use `[bot:*]` prefix for autonomous commits per CLAUDE.md taxonomy:
  - `[bot:save]` — `/save` output
  - `[bot:wiki-add]`, `[bot:wiki-heal]`, `[bot:wiki-fix]` — `/wiki` writes
  - `[bot:mogging-*]` — mogging-repo maintenance
  - `[bot:morning]` / `[bot:nightly]` / `[bot:weekly]` / `[bot:health]` — scheduled agents
  - `[bot:import-claude]` / `[bot:import-notes]` / `[bot:backfill]` / `[bot:reconcile]`
- **Never** `Co-Authored-By: claude-flow <ruv@ruv.net>` (or any `ruv*` coauthor). GitHub resolves that email to ruvnet's profile and misattributes the commit.

## ADR / spec / architecture doc shape

When writing long-form structured engineering documents (ADRs, specs, architecture docs, design docs), this skill stays ACTIVE with one modification:
- Length budget lifts (these docs need full detail).
- Headers/sections are allowed and expected.
- Hard rules still apply: no fluff, no sycophancy, no em-dashes, no hedging, no filler adjectives, dense citations.

**ADR template** (used by `/save --adr` → writes to `Claude-Memory/adr/`):
```
# ADR-NNN: <decision title>
Status: proposed | accepted | superseded
Context: ...what triggered this decision, why now...
Decision: ...what was chosen...
Consequences: ...what changes downstream, both intended and side-effect...
Alternatives considered: ...what was rejected and why...
```

Each section should be terse but complete. Context sections often need 3-5 sentences; Decision sections often 1-3 sentences. Don't pad to fill the template.
