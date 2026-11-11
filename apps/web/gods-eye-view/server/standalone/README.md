# Standalone

## Overview
Component package providing implementation for `apps/web/gods-eye-view/server/standalone`.

## Interface
- `[api-not-found.js:apiNotFoundPlugin]`
- `[google-token-unavailable.js:googleTokenUnavailablePlugin]`
- `[key-setup-hardening.mjs:hardenCredentialFile]`
- `[unwatched-cache.js:unwatchedRuntimeDirsPlugin]`
- `[vite.config.js:standaloneConfig]`
- `[voiceTools.js:standaloneVoiceTools]`

## Invariants
- None

## Side Effects
- [key-setup-hardening.mjs:140]: `spawn = spawnSync,`
- [key-setup-hardening.mjs:148]: `// `-N` (strip the ACL) is Apple-only. Spawn /bin/chmod by absolute`
- [key-setup-hardening.mjs:152]: `const aclRemoval = spawn('/bin/chmod', ['-N', filepath], {`
- [key-setup.js:93]: `* the panel's status fetch fails and the client removes the whole surface.`
- [key-setup.js:137]: `return fs.readFileSync(storePath(), 'utf8');`
- [key-setup.js:166]: `protocol: req.socket?.encrypted ? 'https:' : 'http:',`

## Verification
- Run: `bazel test //apps/web/gods-eye-view/server/standalone/...`
