# Backstage Developer Portal & MCP Server

Vitruvian Developer Portal — software catalog, service documentation, platform engineering workbench, and hosted Model Context Protocol (MCP) server for developer catalog actions.

---

## 🛠️ Exposed MCP Actions

The Backstage backend exposes 9 catalog and auth actions over Streamable HTTP at `https://backstage.vitruviansoftware.dev/api/mcp-actions/v1`:

| Action / Tool | Type | Description |
|---|---|---|
| `get_entities` | Read-only | List and filter catalog entities by kind and namespace |
| `get_entity_by_name` | Read-only | Look up a specific entity by kind, namespace, and name |
| `get_entity_facets` | Read-only | Aggregate facet statistics across catalog entities |
| `query_catalog_entities` | Read-only | Search catalog entities with full-text query, field filters, sorting, and pagination |
| `get_catalog_model_description`| Read-only | Fetch the markdown schema documentation of the catalog entity model |
| `validate_entity` | Read-only | Validate an entity JSON structure against Backstage schema rules |
| `register_entity` | Mutating | Register a new catalog entity from a repository URL location |
| `unregister_entity` | Destructive| Remove a catalog entity by its location ID |
| `who_am_i` | Read-only | Retrieve the authenticated caller's identity and user entity |

---

## 🚀 Client Configuration Guides

### 1. Google Gemini Spark (Custom MCP App)

To connect Backstage to Gemini Spark:

1. In Gemini Spark, go to **Custom MCP Apps → Add App**.
2. Enter the connection settings:
   - **App Name**: `Backstage Developer Portal`
   - **Server URL**: `https://backstage.vitruviansoftware.dev/api/mcp-actions/v1`
   - **Authentication**: `OAuth 2.0` (Authorization Code flow)
   - **Authorization URL**: `https://auth.ipv1337.dev/oauth/v2/authorize`
   - **Token URL**: `https://auth.ipv1337.dev/oauth/v2/token`
   - **Client ID**: `178bbaeb-bcfd-4b07-8cde-0fd7b8cefeaf`
   - **Client Secret**: `d528cc9c-8bce-4959-970a-c1f7278a496d`
   - **Scope**: `openid offline_access urn:zitadel:iam:org:project:id:378078330752834375:aud`
   - **Redirect URI**: `https://oauth-redirect.googleusercontent.com/r/user_bound_custom-mcp-106163123583431838693-backstage_vitruviansoftware_dev`
3. Click **Connect & Authenticate** to log into Zitadel and authorize the app.

---

### 2. Google Antigravity

In Antigravity, add the remote MCP server to your MCP configuration (`~/.gemini/antigravity/mcp_config.json`):

```json
{
  "mcpServers": {
    "backstage": {
      "url": "https://backstage.vitruviansoftware.dev/api/mcp-actions/v1",
      "headers": {
        "Authorization": "Bearer <your-zitadel-access-token>"
      }
    }
  }
}
```

---

### 3. Claude Code / Claude Desktop

In Claude Code (`~/.claude/mcp.json`) or Claude Desktop (`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "backstage": {
      "url": "https://backstage.vitruviansoftware.dev/api/mcp-actions/v1",
      "headers": {
        "Authorization": "Bearer <your-zitadel-access-token>"
      }
    }
  }
}
```
