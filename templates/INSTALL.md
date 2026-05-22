# Status Line Installation

## Overview

The `statusline.sh` script provides a dynamic status line for Claude Code that displays real-time state for 2ndBrain (Obsidian), FidgetFlo (MCP), any active Swarm/Hive sessions, and your Claude rate-limit usage bars (5h + 7-day windows).

## Prerequisites

- `jq` must be installed (`brew install jq` on macOS)
- Claude Code must be installed and configured

## Installation Steps

### 1. Copy the script

```bash
cp statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

### 2. Update Claude Code settings

Edit `~/.claude/settings.json` and add (or update) the `statusline` field:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
```

If the file already has other settings, merge the `statusLine` key into the existing JSON object.

### 3. Restart Claude Code

Close and reopen Claude Code for the status line to take effect.

## What It Shows

| Indicator | Meaning |
|-----------|---------|
| 🧠 Brain² | Working directory is inside an Obsidian vault (2ndBrain or MASTER) |
| ⚡️ fidgetflo | FidgetFlo MCP server is running |
| 🐝 Swarm | Active swarm session (with agent count if available) |
| 👑 Hive | Active hive-mind session |
| 🍯 Mini | Active mini swarm session |

It also appends your current model, session duration, context-window usage, and Claude rate-limit bars for the **5h** and **7-day** windows — `5h █░░░░ 13% · 7d █░░░░ 24%` — color-graded green → yellow → red as you approach each limit. The percentages come from Claude Code's own `rate_limits` data passed to the script on stdin, so there's no API token or network call.

## Swarm/Hive Lock Files

The script uses lock files to detect active sessions:

- `/tmp/fidgetflo-swarm-active` — Created when a swarm starts. Contents hold the agent count as a plain integer (e.g., `15`).
- `/tmp/fidgetflo-mini-active` — Created when a mini swarm starts. Contents hold the agent count as a plain integer (e.g., `5`).
- `/tmp/fidgetflo-hive-active` — Created when a hive-mind starts.

Stale lock files (older than 30 minutes) are automatically cleaned up by the script.

### Creating lock files from your automation

When starting a swarm:
```bash
echo 15 > /tmp/fidgetflo-swarm-active
```

When starting a mini swarm:
```bash
echo 5 > /tmp/fidgetflo-mini-active
```

When starting a hive-mind:
```bash
touch /tmp/fidgetflo-hive-active
```

When stopping:
```bash
rm -f /tmp/fidgetflo-swarm-active
rm -f /tmp/fidgetflo-mini-active
rm -f /tmp/fidgetflo-hive-active
```

## Troubleshooting

- **Status line not appearing**: Verify `~/.claude/settings.json` has the correct `statusline` config and restart Claude Code.
- **jq errors**: Ensure `jq` is installed: `which jq`
- **Indicators not updating**: The script runs on each prompt. Check that the relevant processes are running with `pgrep -f "fidgetflo"`.
