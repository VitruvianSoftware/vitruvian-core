# mcp-slack
 
MCP server exposing Slack tools with dual-token support (local stdio) and OAuth 2.0 / Streamable HTTP support (remote custom MCP apps).

## Architecture & Modes

`mcp-slack` supports two operating modes:
1. **Local Stdio Transport**: Dual-token architecture (Bot token for reads, User token for writes/searches). Provides all 22 tools for local pair programming in Antigravity or Claude Code.
2. **Hosted Streamable HTTP Transport**: Protected Resource Server for Google Gemini Spark Custom MCP Apps with RFC 9728 discovery, Zitadel OAuth 2.0 authentication, channel allow-listing, and bot token execution.

For detailed sequence diagrams, configuration tables, and security controls, see the component's [README](https://github.com/VitruvianSoftware/vitruvian-core/blob/main/mcp-slack/README.md).

