# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| latest  | Yes       |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Do NOT open a public GitHub issue.**
2. Email: nate@lorecraft.io
3. Include: description of the vulnerability, steps to reproduce, and potential impact.
4. You will receive acknowledgment within 48 hours.

## Credential Handling

CLI-MAXXING install scripts collect API credentials interactively and store them in local config files with restrictive permissions (`chmod 600`). Credentials are never committed to this repository.

**Stored credentials and their locations:**
- Motion Calendar: `~/.motion-calendar-mcp/.env`
- Telegram Bot: `~/.claude/channels/telegram/.env`

## Scope

- Shell scripts in this repository
- Installation workflows
- GitHub Actions workflows
