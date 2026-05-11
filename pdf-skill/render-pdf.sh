#!/usr/bin/env bash
# render-pdf.sh — Nate's house-style markdown → PDF renderer
#
# Default behavior (always applied):
#   - Drops the first body H1 (frontmatter `title:` is the only header)
#   - Drops `## Purpose` section + any leading paragraph that begins with `**Purpose.**`
#   - Drops `## Internal notes` section (override with --keep-notes)
#   - Drops `## Sources` section (override with --keep-sources)
#
# Usage:
#   render-pdf.sh <input.md> [--keep-notes] [--keep-sources] [-o output.pdf]
#
# Examples:
#   render-pdf.sh foo.md
#   render-pdf.sh foo.md --keep-notes
#   render-pdf.sh foo.md --keep-notes --keep-sources -o bar.pdf

set -euo pipefail

KEEP_NOTES=0
KEEP_SOURCES=0
INPUT=""
OUTPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-notes)   KEEP_NOTES=1; shift ;;
    --keep-sources) KEEP_SOURCES=1; shift ;;
    -o)             OUTPUT="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,18p' "$0"; exit 0 ;;
    *)              INPUT="$1"; shift ;;
  esac
done

if [[ -z "$INPUT" ]]; then
  echo "usage: render-pdf.sh <input.md> [--keep-notes] [--keep-sources] [-o out.pdf]" >&2
  exit 1
fi

if [[ ! -f "$INPUT" ]]; then
  echo "error: input file not found: $INPUT" >&2
  exit 1
fi

if [[ -z "$OUTPUT" ]]; then
  OUTPUT="${INPUT%.md}.pdf"
fi

TMP=$(mktemp -t renderpdf.XXXXXX).md
trap 'rm -f "$TMP"' EXIT

awk -v keep_notes="$KEEP_NOTES" -v keep_sources="$KEEP_SOURCES" '
BEGIN { first_h1=1; skip_section=0; skip_para=0 }
{
  # drop the first body H1 (frontmatter title is canonical)
  if (first_h1 && /^# /) { first_h1=0; next }

  # H2 gating: enter or exit a skip section
  if (/^## /) {
    skip_para=0
    if (/^## Purpose$/)              { skip_section=1; next }
    else if (/^## Internal notes$/)  { if (!keep_notes)   { skip_section=1; next } else skip_section=0 }
    else if (/^## Sources$/)         { if (!keep_sources) { skip_section=1; next } else skip_section=0 }
    else                             { skip_section=0 }
  }

  # leading inline-purpose paragraph (**Purpose.** ...)
  if (!skip_section && /^\*\*Purpose\.\*\*/) { skip_para=1; next }
  if (skip_para) {
    if (/^$/) { skip_para=0; next }
    next
  }

  if (!skip_section) print
}
' "$INPUT" > "$TMP"

pandoc "$TMP" -o "$OUTPUT" \
  --pdf-engine=weasyprint \
  --metadata date="" \
  -V geometry:margin=0.9in

echo "$OUTPUT"
