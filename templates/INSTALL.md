# Status Line Installation

## Overview

The `statusline.sh` script provides a dynamic status line for Claude Code that displays real-time state for 2ndBrain (Obsidian), Ruflo (MCP), UIPro, and any active Swarm/Hive sessions.

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
  "statusline": {
    "command": "bash ~/.claude/statusline.sh"
  }
}
```

If the file already has other settings, merge the `statusline` key into the existing JSON object.

### 3. Restart Claude Code

Close and reopen Claude Code for the status line to take effect.

## What It Shows

| Indicator | Meaning |
|-----------|---------|
| 🧠 2ndBrain | Working directory is inside an Obsidian vault (2ndBrain or MASTER) |
| ⚡ Ruflo | claude-flow MCP server is running |
| 🎨 UIPro | Always shown (global skill, always available) |
| 🐝 Swarm | Active swarm session (with agent count if available) |
| 🍯 Hive | Active hive-mind session |

## Swarm/Hive Lock Files

The script uses lock files to detect active sessions:

- `/tmp/ruflo-swarm-active` — Created when a swarm starts. Contents can optionally hold the agent count (e.g., `8 agents`).
- `/tmp/ruflo-hive-active` — Created when a hive-mind starts.

Stale lock files (where no matching process is running) are automatically cleaned up by the script.

### Creating lock files from your automation

When starting a swarm:
```bash
echo "8 agents" > /tmp/ruflo-swarm-active
```

When starting a hive-mind:
```bash
touch /tmp/ruflo-hive-active
```

When stopping:
```bash
rm -f /tmp/ruflo-swarm-active
rm -f /tmp/ruflo-hive-active
```

## Troubleshooting

- **Status line not appearing**: Verify `~/.claude/settings.json` has the correct `statusline` config and restart Claude Code.
- **jq errors**: Ensure `jq` is installed: `which jq`
- **Indicators not updating**: The script runs on each prompt. Check that the relevant processes are running with `pgrep -f "claude-flow"`.
