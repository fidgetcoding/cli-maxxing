## MCP Server Setup

Claude Code connects to MCP (Model Context Protocol) servers for extended capabilities. After running Step 4 (FidgetFlo), the FidgetFlo MCP server is configured automatically.

For manual MCP setup or troubleshooting, see the [Claude Code MCP documentation](https://docs.anthropic.com/en/docs/claude-code/mcp-servers).

### Verify MCP Connection

After setup, verify the MCP server is connected:
```bash
claude mcp list
```

If the FidgetFlo MCP server isn't showing, re-add it:
```bash
claude mcp add fidgetflo -- npx -y fidgetflo@latest
```
