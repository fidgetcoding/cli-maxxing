---
name: osmani-build
description: >
  Product-build lifecycle gate over the addy-agent-skills plugin (addyosmani/agent-skills — 24 phase
  skills: define → plan → build → verify → review → ship). Fires on PRODUCT build-intent: the user starts
  building out a real tool, app, webapp, CLI, MCP server, API, bot, or skill — NOT creative ideation,
  content work, one-off scripts, or vault notes. On build-intent, OFFER one line (combined with the
  /recon offer) — do NOT auto-run. Greenfield → enter at Define. Build already started → NEVER
  retroactive Define/Plan; enter at the current phase, usually Verify → Review → Ship. Invoke directly
  as /osmani-build [define|plan|build|verify|review|ship] to skip the offer and jump to a phase.
  Triggers: "build / building out / start building / let's build / make a real / scaffold / MVP"
  plus a product noun.
user_invocable: true
allowed-tools: Skill, Bash, Read, Grep, Task, Agent
---

# osmani-build — phase-gated product builds

Thin orchestrator. The addy plugin skills do the actual work; this skill decides WHICH of the 24
fire, in what order, with your house rules overriding addy's defaults. Born 2026-07-02, same day
the plugin landed (`reference_addy_agent_skills_plugin.md`).

## When this fires — OFFER, never auto-run

On product build-intent, ask ONE line combined with the /recon offer, then wait:

> Real build — want `/recon` (prior art), `/osmani-build` (define→ship lifecycle), both, or neither?

- Product build-intent = starting to build out a tool / app / webapp / CLI / MCP server / API / bot /
  skill intended for real use.
- NOT build-intent: creative ideation, content/copy work, one-off scripts, vault/note work, small
  refactors. (A refactor heading toward a ship can still get `/osmani-build verify` — offer only when
  the user signals shipping intent.)
- Explicit `/osmani-build` invocation skips the offer.
- "Neither" is always a fine answer. The offer is the contract; the run is optional.

## Entry assessment

First move: figure out where the project IS. Look, don't guess — check the dir/repo.

| State | Signal | Entry phase |
|---|---|---|
| Greenfield | no repo, empty dir, idea only | Define |
| Speced | spec/PRODUCT.md exists, little code | Plan |
| Mid-build | working code exists | Build or Verify — ask one line |
| Built | feature-complete, unshipped | Verify → Review → Ship |

HARD RULE: if building already started, NEVER walk backwards into Define/Plan
retroactively. Pick up at the current phase and move forward only.

## Phase map

Run phases in order from the entry point. Within a phase, invoke only the applicable skills via
`Skill({skill: "agent-skills:<name>"})`.

| Phase | Plugin skills | Applicability notes |
|---|---|---|
| Define | interview-me → idea-refine → spec-driven-development | greenfield only; skip any step whose output already exists |
| Plan | planning-and-task-breakdown | tracked tasks → /maketasks (HARD RULE), never raw 05-Tasks writes |
| Build | incremental-implementation (always) · test-driven-development (matches house TDD-London preference) · context-engineering · source-driven-development · doubt-driven-development | frontend-ui-engineering only for UI · api-and-interface-design only for APIs |
| Verify | browser-testing-with-devtools (web surfaces) · debugging-and-error-recovery (on failures) | plus native /verify when the diff has a runtime surface |
| Review | code-review-and-quality · code-simplification · security-and-hardening · performance-optimization | native /code-review, /simplify, /security-review are substitutes — prefer addy's inside the full lifecycle |
| Ship | git-workflow-and-versioning · ci-cd-and-automation · shipping-and-launch · observability-and-instrumentation | documentation-and-adrs ONLY on explicit ask · deprecation-and-migration only when replacing a live thing |

## Phase gates

At each phase boundary, one line — e.g. `Define done → Plan next. Continue / skip to <phase> / stop?`
Default momentum is continue; a bare "go" advances. Never re-litigate a completed phase.

## House overrides (bind over addy defaults)

- **No PRs** on lorecraft-io/fidgetcoding repos — direct push to main (`feedback_no_prs`). Ignore any
  PR-flow steps inside git-workflow-and-versioning.
- **Never** `Co-Authored-By: claude-flow <ruv@ruv.net>` or any ruv* coauthor on commits.
- **No proactive docs/READMEs.** documentation-and-adrs runs only on explicit ask; READMEs follow
  `feedback_readme_style` (personal voice, no dev-jargon jokes).
- **ADRs route through /save branch 4** → `Claude-Memory/adr/ADR-<nnn>-<slug>.md`, not addy's location.
- **Never dark mode by default** on any scaffold (`feedback_never_dark_mode`).
- **Task creation → /maketasks.** Any planning output that becomes tracked tasks goes through the
  skill — never direct 05-Tasks writes, never minted UUIDs.
- **/recon stays separate** — this skill never runs the landscape sweep itself.

## Invocation mechanics

1. Primary: `Skill({skill: "agent-skills:<name>"})`.
2. Plugin skills not loaded this session (pre-restart)? Read the source directly and follow it inline:
   `ls ~/.claude/plugins/cache/addy-agent-skills/agent-skills/*/skills/<name>/SKILL.md`
   (version dir changes on plugin update — always glob, never hardcode).
3. Plugin missing entirely? Reinstall with the SSH→HTTPS workaround in
   `reference_addy_agent_skills_plugin.md`, then continue.

## Non-goals

- No prior-art sweep (that's /recon).
- No session capture (that's /save).
- No creative/content pipelines — products only.
