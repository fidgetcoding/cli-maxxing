---
name: pdf
description: "Render a markdown file to PDF with a consistent house style — one header only (drops body H1, frontmatter `title:` is canonical), strips Purpose / Internal notes / Sources sections by default. Opt back in with --keep-notes / --keep-sources. Uses pandoc + weasyprint via the bundled render-pdf.sh. Invoke when the user asks to render, generate, export, make, or turn a markdown doc into a PDF."
user_invocable: true
---

# PDF — Markdown to PDF with house-style rules

## When to use

Invoke this skill when the user says any of:

- `/pdf <file.md>`
- "render this as a PDF"
- "make a PDF of …"
- "turn this into a PDF"
- "export to PDF"
- "PDF this doc"
- "generate a PDF"

Or when the user explicitly asks to ship a markdown file as a partner-/leadership-facing PDF.

**Do NOT** call pandoc directly for user-facing PDFs unless this skill genuinely can't handle the case (escalate first).

## The four rules (always enforced by default)

1. **One header only.** Drop the first body H1. Frontmatter `title:` is the canonical title. Never two stacked titles.
2. **No "Purpose" content.** Strip `## Purpose` sections AND any leading paragraph that begins with `**Purpose.**`.
3. **No "Internal notes" section** in PDF output unless `--keep-notes`.
4. **No "Sources" section** in PDF output unless `--keep-sources`.

The source markdown is **never modified** — preprocessing happens on a temp copy before pandoc.

## How to invoke the script

The script ships with this skill at `~/.claude/skills/pdf/render-pdf.sh`. Run it via Bash:

```bash
~/.claude/skills/pdf/render-pdf.sh <input.md> [--keep-notes] [--keep-sources] [-o <output.pdf>]
```

Examples:

```bash
# Standard render — strips Purpose / Internal notes / Sources
~/.claude/skills/pdf/render-pdf.sh 01-Projects/FOO/doc.md

# Keep internal notes
~/.claude/skills/pdf/render-pdf.sh 01-Projects/FOO/doc.md --keep-notes

# Keep both (e.g., for a personal reference doc)
~/.claude/skills/pdf/render-pdf.sh 01-Projects/FOO/doc.md --keep-notes --keep-sources

# Custom output path
~/.claude/skills/pdf/render-pdf.sh foo.md -o ~/Desktop/foo.pdf
```

Default output path: `<input>.pdf` next to the source.

## When to use the opt-in flags

| Flag | Use when |
|---|---|
| `--keep-notes` | The doc is a personal reference / internal campaign summary where the "Internal notes" block is part of the value of the PDF itself (rare). |
| `--keep-sources` | The doc is a research artifact where citations are load-bearing. Also rare. |

If unsure, **don't pass them** — default behavior matches the house style. The user will tell you to keep them when needed.

## Engine + style

- pandoc + weasyprint
- `--metadata date=""` (no auto date header)
- 0.9in margins
- Frontmatter `title:` rendered as the canonical title

## Performance

~0.5s end-to-end on a typical 1–3 page doc. The awk filter is microseconds; weasyprint is the only meaningful cost.

## Why these rules exist

PDFs are shareable artifacts (partners, leadership, external counterparts). The markdown is the vault note — keeps full context. The PDF is what gets sent. Internal notes leak intent, Purpose sections look amateur, double headers look unpolished. Recurring failure mode: stacked frontmatter+body titles shipping in client-facing PDFs.

## Failure modes / escalation

- **Missing pandoc or weasyprint.** Tell the user to `brew install pandoc weasyprint`.
- **Source file not found.** Surface the path back to him — usually a typo.
- **Edge case the awk filter doesn't catch** (e.g., a Purpose block disguised as an H3, or a "Notes" section that should be kept). Render once, show him the PDF, ask if any section needs surgery before re-rendering.

## Mirror

This skill is also versioned in the CLI-MAXXING repo at `pdf-skill/SKILL.md`. The two should stay in sync. If you edit one, edit the other.
