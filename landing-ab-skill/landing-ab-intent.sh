#!/usr/bin/env bash
# landing-ab-intent.sh — UserPromptSubmit hook.
# On landing-page intent phrasing, inject a reminder to invoke the landing-ab skill
# (self-driving landing page ladder: signup-cta tag, PostHog, flags, LP-OPS.md).
# Silent on everything else.
# Companion to ~/.claude/skills/landing-ab/SKILL.md, which is built from Angus
# Sewell's self-driving landing page field guide (2026-07-03).

PROMPT=$(jq -r '.prompt // empty' 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

# Already invoking the skill explicitly — no reminder needed.
printf '%s' "$PROMPT" | grep -Eq '/landing-ab\b' && exit 0

# Landing-page intent = LP-shaped noun, or optimization verbs aimed at a page/site.
if printf '%s' "$PROMPT" | grep -Eiq '\blanding[- ]?pages?\b|\bsplash page\b|\bone[- ]pagers?\b|\bwaitlist (page|site)\b|\blead[- ]magnet page\b|\bmarketing (site|page)\b|\bpromo (page|site)\b|\bcoming[- ]soon page\b|\b(a/?b[- ]test|posthog|heatmaps?|session replay|personali[sz]e|conversion)\b.{0,60}\b(page|site|hero|cta)\b'; then
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"LANDING-AB ENFORCEMENT: This prompt pattern-matches landing-page intent. If this turn involves building or modifying a landing page — or adding analytics, A/B testing, or personalization to one — invoke Skill({skill: \"landing-ab\"}) BEFORE building. It enforces the self-driving ladder: signup-cta CTA tag, PostHog wiring at build time, landing-ab flag stub, docs/LP-OPS.md with the L3-L5 playbook. If landing pages are only mentioned in passing, ignore this silently."}}
EOF
fi
exit 0
