# Installation & User Guide

Welcome to the **Vitruvian Roborock** integration! This guide walks you through installing and using the plugin with **Antigravity**, **Claude Code**, or directly as a standalone **CLI (`rrctl`)**.

---

## 1. Prerequisites

- macOS or Linux. Nothing else: `rrctl` is a single binary with no runtime to install.
- A Roborock vacuum cleaner (S-series or Q-series V1 protocol, e.g. S8, S7, Q7, Q8, etc.) associated with your Roborock mobile app.

---

## 2. Installation

`rrctl` is one self-contained binary: the daemon, the CLI and the MCP server.
The plugins start it as `rrctl mcp`, so put `rrctl` on your `PATH` first, one of
these ways:

- **Download it** from the
  [latest release](https://github.com/VitruvianSoftware/mcp-roborock/releases/latest)
  (macOS universal, Linux x86_64), check it against its `.sha256`, and put
  `rrctl` in a directory on your `PATH`, such as `~/.local/bin`.
- **Build it** with Rust installed:
  `cargo install --locked --git https://github.com/VitruvianSoftware/mcp-roborock`
- **In the vitruvian-core monorepo:** `bazel build //apps/mcp/roborock:rrctl`,
  then copy `bazel-bin/apps/mcp/roborock/rrctl` onto your `PATH`.

### Option A: Claude Code

Add our repository as a plugin marketplace and install `vitruvian-roborock`:

```bash
# 1. Register the Vitruvian Roborock marketplace
claude plugin marketplace add VitruvianSoftware/mcp-roborock

# 2. Install the plugin
claude plugin install vitruvian-roborock
```

Once installed, Claude Code has access to:
- **Skills**: `/roborock-control` (clean rooms, dock, wash mop) and `/roborock-setup` (first-time login).
- **MCP Tools**: `get_status`, `start_clean`, `control`, `return_to_dock`, `wash_mop`, `get_map`, `setup_login`.

---

### Option B: Antigravity

```bash
agy plugin install https://github.com/VitruvianSoftware/mcp-roborock
```

No clone is needed: Antigravity finds the plugin in the repository's `plugin/`
folder and installs it as `vitruvian-roborock`.

To verify the installation:
```bash
agy plugin list
```
You will see `vitruvian-roborock` listed with its skills and MCP server.

---

### Option C: Standalone CLI (`rrctl`)

If you want the terminal CLI and local web dashboard without an AI agent:

Install `rrctl` as described at the top of this section; the plugins are optional.

Verify it:

```bash
rrctl --help
```

---

## 3. First-Time Setup & Authentication

Before commanding the vacuum, log in with your Roborock account:

### Via Terminal
```bash
rrctl setup
```
1. Enter the email address linked to your Roborock account.
2. Check your email for the 6-digit verification code sent by Roborock.
3. Paste the code into the prompt. Credentials are saved securely to `~/.config/vitruvian/roborock/credentials.json` with strict `0600` permissions.

*(Note: If you have previously used the upstream `roborock` CLI on your machine, your login in `~/.roborock` is automatically detected and migrated).*

### Via AI Agent
Simply prompt your agent:
> *"Log into my Roborock vacuum with email user@example.com"*

The agent will invoke `setup_login` and prompt you for the verification code.

---

## 4. Daily Usage & Commands

### Terminal Commands

| Task | Command |
| :--- | :--- |
| **Check vacuum status** | `rrctl status` (or `rrctl status --json`) |
| **Open live dashboard** | `rrctl dashboard` (opens in default browser) |
| **Save floor map** | `rrctl map -o floorplan.png` |
| **Pause cleaning** | `rrctl pause` |
| **Resume cleaning** | `rrctl resume` |
| **Send to dock** | `rrctl dock` |
| **Manage daemon** | `rrctl daemon [status\|start\|stop]` |

### Natural Language Prompts for Agents

You can interact conversationally with Claude Code or Antigravity:

- *"What is the current status and battery level of our vacuum?"*
- *"Show me the latest floor map."*
- *"Clean the Kitchen and Living room."*
- *"Send the vacuum back to the dock and wash the mop."*
- *"Stop cleaning."*

---

## 5. Room Labels & Selective Cleaning

When you label rooms in the Roborock mobile app (e.g. *Kitchen*, *Living room*, *Study*, *Hall*), the local daemon automatically maps those names to their segment IDs.

To clean specific rooms:
```bash
# Via agent:
"Clean the Kitchen and Dining room twice."

# Or via the MCP tools / API:
# action: clean_rooms, params: {"rooms": ["Kitchen", "Dining room"], "repeat": 2}
```

---

## 6. Architecture & Security

- **Single Daemon Architecture**: One local daemon (`127.0.0.1:8765`) maintains the single session with the vacuum (supporting automatic LAN fallback for low-latency control) to respect Roborock cloud connection limits.
- **Loopback Token Authentication**: All requests between the CLI/MCP server and the daemon require a 256-bit bearer token stored at `~/.config/vitruvian/roborock/daemon-token` (`mode 0600`).
- **No Cloud Relay**: Dashboard and agent interactions run 100% on your local machine.
