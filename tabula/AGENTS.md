# Agent Guide for Tabula

This document provides instructions for AI Agents working on the Tabula repository, specifically
regarding verification workflows and testing.

## 📋 Requirements

For a detailed understanding of expected behavior and verified capabilities, refer to
`docs/product/REQUIREMENTS.md`.

## 🤖 How to Verify Changes

When you are asked to "verify" changes, especially for UI or Sync logic, follow this standard
procedure:

### 1. Automated E2E Testing

Always run the Playwright suite first. It covers standard user journeys and ensures no regressions.

```bash
# In 'extension' directory
npx playwright test tests/sync-journeys.spec.ts
```

### 2. Manual Browser Verification (Critical)

Automated tests mock some browser behaviors. For "true" verification of persistence and UI
interactions, use the **Browser Subagent**.

**Prompt to Agent:**

> "Load `chrome-extension://hgnonehmcoenpidnakjafkcfpppibfio/dashboard.html` in the browser
> subagent. Create a new Space, Rename it, reload the page, and verify the name persists. Then
> delete it."

**Key things to watch:**

- **Persistence**: Does the change stick after `reload`? (If not, API validation might be failing).
- **Console Errors**: Check `capture_browser_console_logs` if actions fail silently.
- **Strict Mode**: Playwright selectors can be strict; use specific text/classes.

## 🧪 Validated User Journeys

The following are critical paths that MUST work:

1.  **Create Space**: Should appear immediately.
2.  **Rename Space**: Must persist after reload.
3.  **Create Section**: Should appear in sidebar.
4.  **Rename Section**: Uses `prompt()` dialog. Subagent can override `window.prompt`.
5.  **Delete/Archive**: Should remove from view.

## 🛠 Setup for Agents

Everything is a Bazel target; no npm install or manual services needed:

1.  `bazel build //tabula/extension:dist` — build the extension
2.  `bazel test //tabula/...` — unit + hermetic integration suites
3.  `bazel test --config=e2e //tabula/...` — Playwright E2E (Bazel boots
    Postgres, Redis, migrations, and the API as managed test services)
