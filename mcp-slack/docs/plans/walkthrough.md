# `mcp-slack` Gemini Spark Custom App Integration Walkthrough

We have extended `mcp-slack` to support Google Gemini Spark custom MCP connections and added comprehensive documentation with visual sequence diagrams.

---

## 🏛️ The Two Usage Modes

`mcp-slack` supports two operating modes tailored to different execution environments and trust boundaries:

| Property | Mode 1: Local Stdio Transport | Mode 2: Hosted Streamable HTTP Transport |
|---|---|---|
| **Target Client** | Claude Code, Antigravity, Cursor, Codex | Google Gemini Spark Custom MCP Apps |
| **Transport Protocol** | `stdio` (JSON-RPC over stdin/stdout) | `Streamable HTTP` (RFC 9728 + OAuth 2.0) |
| **Authentication** | Local process environment variables | RFC 9728 metadata discovery + Zitadel OAuth (JWT) |
| **Identity & Writes** | Dual-Token: Posts *as you* (User Token `xoxp-...`) | Bot Token: Posts as app bot (Bot Token `xoxb-...`) |
| **Security Controls** | Local machine boundary; optional channel filter | Strict per-request Zitadel `sub` allowlist + channel allowlist |
| **Tool Surface** | All 22 tools (messaging, search, canvases, pins) | 10 curated HTTP-safe tools |

---

## 📊 Visual Sequence Diagrams

### 1. Mode 1: Local Stdio Architecture (Desktop Pair Programming)

```mermaid
sequenceDiagram
    autonumber
    actor Dev as Developer (James)
    participant IDE as Agent IDE (Antigravity / Claude)
    participant Server as mcp-slack (stdio Process)
    participant SlackAPI as Slack Web API

    Dev->>IDE: "Post update to #dev" / "Search my DMs"
    IDE->>Server: JSON-RPC CallTool (stdin)
    alt Read Operation (e.g. list channels, history)
        Server->>SlackAPI: GET /conversations.history (Bot Token xoxb-...)
        SlackAPI-->>Server: Channel history
    else Write / Search Operation (e.g. post message, search)
        Server->>SlackAPI: POST /chat.postMessage (User Token xoxp-...)
        SlackAPI-->>Server: Message posted as authenticated human user
    end
    Server-->>IDE: Tool response (stdout)
    IDE-->>Dev: Response displayed in chat
```

---

### 2. Mode 2: Hosted Streamable HTTP Architecture (Gemini Spark Custom MCP App)

```mermaid
sequenceDiagram
    autonumber
    actor User as James
    participant Spark as Google Gemini Spark
    participant Envoy as Envoy Gateway / Ingress
    participant Server as mcp-slack (K8s Pod)
    participant Zitadel as Zitadel IdP (auth.ipv1337.dev)
    participant SlackAPI as Slack Web API

    Note over Spark,Server: Phase 1: RFC 9728 Discovery & OAuth Metadata
    Spark->>Envoy: GET /.well-known/oauth-protected-resource/mcp
    Envoy->>Server: Forward probe
    Server-->>Spark: 200 OK (RFC 9728 JSON: resource, authorization_servers, scopes)

    Note over Spark,Zitadel: Phase 2: OAuth 2.0 Authorization Code Flow
    Spark->>Zitadel: Discover endpoints (/.well-known/openid-configuration)
    Spark->>User: Prompt to Authorize via Zitadel
    User->>Zitadel: Authenticate & Grant Access
    Zitadel-->>Spark: Redirect to googleusercontent.com with Auth Code
    Spark->>Zitadel: Exchange Code for Access Token (JWT)
    Zitadel-->>Spark: Access Token (JWT with sub, aud, client_id)

    Note over Spark,SlackAPI: Phase 3: Authenticated Tool Invocations
    Spark->>Envoy: POST /mcp (CallTool: slack_list_channels) with Bearer JWT
    Envoy->>Server: Forward request
    Server->>Server: Local JWT Verification (JWKS, aud, sub in OIDC_ALLOWED_SUBJECTS)
    Server->>Server: Check channel in SLACK_CHANNEL_IDS
    Server->>SlackAPI: Call Slack API (Bot Token xoxb-...)
    SlackAPI-->>Server: API Response
    Server-->>Spark: 200 OK (Streamable HTTP JSON-RPC result)
    Spark-->>User: Assistant displays Slack info
```

---

## 🛠️ Summary of Code Changes in PR #1966

1. **RFC 9728 Discovery** in [`httpTransport.ts`](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/mcp-slack/src/httpTransport.ts):
   - Handles `GET /.well-known/oauth-protected-resource` and `/.well-known/oauth-protected-resource/mcp`.
   - Injects `resource_metadata` in `WWW-Authenticate` header on HTTP 401 challenges.
2. **Ingress Routing** in [`httproute.yaml`](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/mcp-slack/deploy/chart/templates/httproute.yaml):
   - Added `/.well-known/oauth-protected-resource` PathPrefix routing.
3. **Zitadel OIDC Redirect URIs** in [`main.go`](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/infrastructure/pulumi/platform/zitadel-apps-mcp-slack/main.go):
   - Added Gemini Spark `googleusercontent.com` OAuth callback URIs.
4. **Documentation** in [`README.md`](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/mcp-slack/README.md) & [`docs/index.md`](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/mcp-slack/docs/index.md):
   - Added comprehensive user guides, comparison table, and Mermaid sequence diagrams.
5. **Unit Tests** in [`httpTransport.test.ts`](file:///Users/james/Workspace/gh/application/vitruvian/vitruvian-core/mcp-slack/__tests__/httpTransport.test.ts):
   - Added automated tests verifying discovery endpoints and challenge header injection (135 tests passing).
