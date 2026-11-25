<!--
Copyright (c) 2026 VitruvianSoftware

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
-->

# zitadel-mcp-viewer

A **read-only** Zitadel identity for the Zitadel MCP server
(`@warnyin/zitadel-mcp`) that runs on James's Mac.

| Resource | What it is |
|---|---|
| Machine user `mcp-viewer` | No password, no client secret, bearer access tokens |
| Org membership | `ORG_OWNER_VIEWER` only: reads users, projects, apps, grants and policies; changes nothing |
| Personal Access Token | Expires on `zitadel-mcp-viewer:patExpiry` (at most a year ahead; the program refuses more, or none) |

## Outputs

`machineUserId`, `orgRole` and `patExpiry` are plain. `patToken` is a **secret**
output. The apply workflow never reads it. After an `up`, James reads it once and
stores it in Bitwarden and the keychain:

```sh
bazel run //infrastructure/pulumi/platform/zitadel-mcp-viewer:stack -- output patToken --show-secrets
```

## How it applies

Dispatch-only, through `.github/workflows/zitadel-mcp-viewer-apply.yaml`
(`preview`, then `up`), like the sibling `zitadel-apps-*` stacks. It reaches
Zitadel over the tailnet tunnel with the instance's CI machine key, and every
`up` runs through the plan guard. The `development` stack is created once by hand
before the first run:

```sh
bazel run //infrastructure/pulumi/platform/zitadel-mcp-viewer:stack -- init development
```

## Rotating the token

Move `patExpiry` forward. That **replaces** the PAT (a new token, the old one
deleted), so the commit needs an `Allow-destroy:` line naming the
PersonalAccessToken URN, then an `up`, then read and store the new token.

## Why its own stack

`zitadel-apps-mcp-slack` and `zitadel-apps-relay` each own one app's project and
OIDC clients. An org-wide read identity is a different blast radius, so it gets
its own state and its own apply.
