#!/usr/bin/env bash
set -euo pipefail

cd "$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" 2>/dev/null || cd "$(pwd)"

# 1. Install deps
echo "Installing @chenglou/pretext + canvas..."
npm install @chenglou/pretext canvas

# 2. Verify it works
echo "Verifying API..."
node -e "
const { createCanvas } = require('canvas');
global.OffscreenCanvas = class { constructor(w,h) { this._c = createCanvas(w,h); } getContext(t) { return this._c.getContext(t); } };
const p = require('@chenglou/pretext');
const r = p.layout(p.prepare('test', '16px sans-serif'), 300, 20);
console.log('  prepare ✓  layout ✓  height=' + r.height + 'px');
const s = p.prepareWithSegments('test', '16px sans-serif');
p.layoutWithLines(s, 300, 20);
console.log('  prepareWithSegments ✓  layoutWithLines ✓');
p.walkLineRanges(s, 300, () => {});
console.log('  walkLineRanges ✓');
p.layoutNextLine(s, {segmentIndex:0, graphemeIndex:0}, 300);
console.log('  layoutNextLine ✓');
p.profilePrepare('test', '16px sans-serif');
console.log('  profilePrepare ✓');
p.clearCache();
console.log('  clearCache ✓');
p.setLocale();
console.log('  setLocale ✓');
console.log('All 9 APIs verified.');
"

# 3. Create the /pretext skill
echo "Creating /pretext Claude Code skill..."
mkdir -p .claude/skills/pretext
cat > .claude/skills/pretext/SKILL.md << 'EOF'
---
name: pretext
description: "Natural language interface to @chenglou/pretext for text measurement, line layout, profiling, shrinkwrap, and variable-width flow. Run with /pretext followed by a natural language request."
user_invocable: true
---

# Pretext — Text Measurement & Layout

When invoked with `/pretext <request>`, interpret the natural language request and call the appropriate @chenglou/pretext API.

## Available APIs

| Command Pattern | API | What it does |
|----------------|-----|-------------|
| measure, height, how tall | `prepare` + `layout` | Returns height & line count |
| lines, break into, split | `prepareWithSegments` + `layoutWithLines` | Returns each line separately |
| profile, benchmark | `profilePrepare` | Timing breakdown |
| shrinkwrap, tightest, min width | `walkLineRanges` | Find tightest fit width |
| flow, variable width | `layoutNextLine` | Per-line variable widths |
| set locale | `setLocale` | Change locale |
| clear cache | `clearCache` | Clear measurement cache |

## How to Execute

Run the appropriate Node.js code using Bash. Always include the OffscreenCanvas polyfill:

```javascript
const { createCanvas } = require('canvas');
global.OffscreenCanvas = class {
  constructor(w, h) { this._c = createCanvas(w, h); }
  getContext(t) { return this._c.getContext(t); }
};
const pretext = require('@chenglou/pretext');
```

## Parsing Rules

- Text: extract quoted string ("Hello world")
- Font: extract CSS font string (e.g., "16px Inter", "bold 24px Georgia")
- Width keywords: `wide`, `width`, `max`, `within` (defaults to 300px)
- Line height keywords: `line height`, `leading`, `lh` (defaults to 20px)
- For flow mode, provide widths as comma-separated: `widths 200,300,250`
- Add `--json` for JSON output, `--stdin` to pipe text, `--batch <file>` for bulk
EOF

echo ""
echo "Done. Use:"
echo "  node scripts/pretext.mjs '<request>'   — terminal"
echo "  /pretext <request>                     — Claude Code"
