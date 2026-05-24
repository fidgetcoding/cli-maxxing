# Changelog

All notable changes to `cli-maxxing` are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **`/bullets` skill** (step 4) — crushes a paragraph or prose blob into the shortest scannable bullets: one fact per bullet, ≤~12 words, zero fluff, every signal preserved (names, numbers, dates, paths, decisions). Always outputs bullets — built because `/concise` decides shape per reply and sometimes leaves prose, which is wrong for document handoffs where nobody should have to read a blob. Triggers on `/bullets` and in plain English ("bullet this", "bulletize", "turn this into bullets"). Vendored at `bullets-skill/` (single SKILL.md). Installed by Step 4 as an inline heredoc alongside `/w4w` and `/concise` (no network dependency); self-test asserts SKILL.md landed. Listed across `README.md`, `CHEATSHEET.md`, `README-SECTIONS/cheat-sheet.md`, `install.sh` + `update.sh` summaries, the Step 4 self-test + summary, and the `uninstall.sh` Step 4 removal loop.
- **`/recon` skill** (step 7) — pre-build prior-art reconnaissance. On build-intent ("build / make / start a new X", "does X exist?") it offers a one-line prompt first (never auto-runs — Nate sometimes clones a known paid tool on purpose), then sweeps GitHub via the `gh` CLI + the web for existing free and paid options, ranks the top ~10 in a comparison table, finds the edge (or honestly calls it a red ocean), and ends with a GREEN/YELLOW/RED verdict. Output is a discussion, not code. Vendored at `recon-skill/` (single SKILL.md). Installed by Step 7 alongside `/gitfix` (depends on the `gh` CLI Step 7 already installs); no PAT needed. Step 7 installer downloads from `fidgetcoding/cli-maxxing/main` via curl with a local fallback, the non-interactive path installs it too, and the self-test asserts SKILL.md landed. Listed across `README.md`, `CHEATSHEET.md`, `README-SECTIONS/cheat-sheet.md`, `install.sh` + `update.sh` summaries, `step-final` self-test, and the `uninstall.sh` Step 7 removal.
- **`/concise` skill** (step 4) — default chat-shape filter. No fluff, no scaffolding, no headers on simple questions, no sycophancy. Auto-suspends for copywriting deliverables (tweets, scripts, decks, client docs) so it doesn't sand down voice on output going to a human audience. Vendored at `concise-skill/` (SKILL.md + 3 references — `copywriting.md`, `inputs.md`, `code-and-commits.md`). Step 4 installer downloads from `lorecraft-io/cli-maxxing/main` via curl with a local fallback for offline / pre-publish runs. Self-test asserts SKILL.md + copywriting.md reference landed. Listed across `README.md`, `CHEATSHEET.md`, `install.sh` summary, `update.sh` summary, and `uninstall.sh` skill removal loop.
- `pdf-skill` — markdown→PDF renderer enforcing Nate's house style (single H1 from frontmatter `title:`, strips body H1 / Purpose / Internal notes / Sources sections by default). Pandoc + WeasyPrint. Opt back in to dropped sections via `--keep-notes` / `--keep-sources`. Mirror of the global `~/.claude/skills/pdf/` skill.
- README: social-links badge strip (X · LinkedIn · YouTube · Instagram, ruvnet-style for-the-badge) inserted into the centered header block beneath the banner.
- **`cbrain` + `cbraintg` shell shortcuts** (step 10.9) — quick-launch aliases for the Brain² + Telegram-bridged sessions.
- Step 5 — full upstream URL verification across all five external MCPs (morgen / motion / playwright / granola / n8n).
- Step 7 — GitHub MCP migrated to the hosted endpoint at `github/github-mcp-server` (the deprecated `@modelcontextprotocol/server-github` is removed).
- Step 5 — Notion MCP migrated to the hosted OAuth endpoint at `https://mcp.notion.com/mcp`. No integration token, no per-page sharing — Notion handles auth on first use via browser OAuth.
- Step 5 — Google Calendar MCP swapped to `@cocal/google-calendar-mcp` (actively maintained); the bare `google-calendar-mcp` package was a year-stale fork.

### Changed
- Git history rewrite: `git filter-repo` collapsed all author/committer identities (dependabot[bot], lorecraft-io, nate variants) into a single `Nate Davidovich <nate@lorecraft.io>` identity across `main` and both release tags (v1.9.1, v2.0.0). All `Co-authored-by:` trailers stripped (162 of them — mostly `claude-flow <ruv@ruv.net>` carryover from pre-rebrand). Tag commit hashes changed; this repo has no published npm artifact, so no downstream impact.
- Step 6 ordering — `gh` CLI moved from Step 3 to Step 7 so the full GitHub stack (CLI + MCP + workflows) ships together.
- Step 5 — design-stack MCPs (Figma / Excalidraw / Gamma / Magic / YouTube / IG) removed from cli-maxxing cheatsheets — these now live exclusively in the `creativity-maxxing` install. cli-maxxing remains the lean core terminal install.
- Step 5 — `2ndbrain-maxxing` references flipped to `2ndBrain-mogging` across `README-SECTIONS/` and `tests/`.

### Fixed
- Step 2 (`step-2/ghostty-install.sh`): post-install summary now includes a yellow "ONE MORE STEP — GRANT FULL DISK ACCESS" section with click-by-click instructions (System Settings → Privacy & Security → Full Disk Access → toggle Ghostty ON, with the `+` → `/Applications` fallback if Ghostty isn't listed). New `--open-fda` flag jumps directly to the right pane via the canonical `x-apple.systempreferences:...?Privacy_AllFiles` URL. Closes item 1 of the WAGMI Apr-22 install-call bug catalog (`project_wagmi_install_bugs_2026_04_22.md`) — every WAGMI teammate hit silent FDA-permission errors on first launch.
- Step 1-5 — anchored MCP grep patterns at `^<name>:` so substring matches don't trigger false-positive "already installed" detection.
- Step 5 — BSD grep compat fix in Motion detection (macOS `grep` doesn't support `-P` like GNU does; pattern simplified accordingly).
- Step 6 — `SAVED_TOKEN` env var unset after self-test validation so a stale value doesn't leak into the next step.
- Step 7 / Step 8 / step-final — atomic MCP match patterns tightened to prevent partial overlaps.
- `uninstall.sh` + `INSTALL.md` — `cbraintg` ownership note + stale references cleaned up.
- Sub-modules: `gitfix-skill` and `rmini-skill` picked up the residual stash improvements from the step-forward rebase.

## [2.0.0] - 2026-04-15

### Changed — Major split + rebrand

This is the first version after the post-mogging split (per `project_cli_maxxing_split`). The original "AI Super Setup" stack was carved into three focused repos:

- **cli-maxxing** (this repo) — core terminal install: shell, package managers, Claude Code, MCPs (calendar/task/automation), GitHub stack, safetycheck.
- **creativity-maxxing** — design / video / audio / transcription tooling.
- **2ndBrain-mogging** — Obsidian + Claude Code second brain + skills + scheduled agents.

### Added — Step structure
- 8 numbered steps + 1 final step, with one command per step. See `README-SECTIONS/step-ordering.md`.
- `gitfix-skill` and `rmini-skill` as in-tree submodules.
- `terminal-academy` submodule — gamified terminal trainer.
- `templates/` — reusable install-step scaffolds.

## [1.9.1] - pre-rebrand

Last release under the "AI Super Setup" branding. Preserved as a tag for lineage.
