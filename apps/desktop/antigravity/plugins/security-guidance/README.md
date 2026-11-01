# security-guidance

An Antigravity desktop plugin that performs real-time vulnerability and secret
scanning on file writes and edits (`write_file`, `edit_file`, `write_to_file`,
`replace_file_content`, `multi_replace_file_content`) and `run_command`
(`PreToolUse`).
It blocks hardcoded credentials and
critical command injection patterns before they land on disk, prompts with
context-specific remediation guidance on risky constructs (`eval(`, `innerHTML`,
`pickle.loads`, `yaml.load(`, `torch.load` without `weights_only=True`, SQL
string concatenation, SSRF), and records audit findings for the interactive
Security Guidance side panel.

## Features

- **16 Built-in Vulnerability & Secret Patterns (`BUILTIN_PATTERNS`):**
  - Hardcoded PEM private keys, AWS Access Key IDs (`AKIA...`), GCP API keys
    (`AIza...`), and GitHub Personal Access Tokens (`ghp_...`, `github_pat_...`)
  - Remote shell execution (`curl ... | sh`), Python `subprocess` with
    `shell=True` / `os.system`, and Node `child_process.exec` interpolation
  - DOM XSS via `.innerHTML` / `dangerouslySetInnerHTML` and dynamic `eval()` /
    `new Function()`
  - Unsafe deserialization (`pickle.loads`, `yaml.load()` without `SafeLoader`,
    `torch.load()` without `weights_only=True`)
  - SQL string concatenation, path traversal (`../`), cloud metadata SSRF
    (`169.254.169.254`), and GitHub Actions `${{ github.event.* }}` script
    injection
- **Inline Suppression Comments:** Suppress false positives on a line with
  `// security-guidance-ignore: <rule-id>[, <rule-id>]` or `# nosec: <rule-id>`
  (`all` for every rule). Without the colon and list (`# nosec`), the comment
  suppresses every rule on that line. You can also suppress findings from the
  side panel.
- **Interactive Sidecar Panel & OpenUI Lang v0.5:** Inspect active and
  suppressed findings, paste code or unified diffs to run ad-hoc security scans,
  wake the owning conversation with a remediation prompt, and view live OpenUI
  Lang v0.5 state (`GET /api/openui`).

## Requirements

The hook is written in Rust using only the standard library. The first time
it runs, `hooks/rust-hook.sh` compiles it with `rustc` (about 1-2 s) into
`~/.cache/antigravity-plugins/`, and later runs reuse that binary. You need
Rust installed ([rustup.rs](https://rustup.rs)). Without it, the hook asks
before every edit and command, says that nothing is being checked, and gives
the reason on stderr. The side panel runs on Antigravity's Node.js.

## Install

From GitHub:

```bash
agy plugin install https://github.com/VitruvianSoftware/security-guidance
```

Or link a local checkout into Antigravity's plugin folder:

```bash
ln -s "$(pwd)" ~/.gemini/config/plugins/security-guidance
```

Then enable it under Customizations → Installed, and open the side panel from
any conversation via the ⋮ menu → Extensions → Security Guidance.

## Update

Disable the plugin under Customizations → Installed, pull the latest changes,
and re-enable:

```bash
git -C ~/.gemini/config/plugins/security-guidance pull
```

## Layout

| Path | Description |
| --- | --- |
| `plugin.json` | Plugin manifest |
| `hooks.json`, `hooks/security-check.sh` | `PreToolUse` security scanner hook (allows on `Stop`) |
| `hooks/rust-hook.sh` | Builds the hook from `hooks/src` with `rustc` on first use, then runs it |
| `hooks/src/` | The hook: `lib.rs` (rules, store, decision, tests), `json.rs`, `main.rs` |
| `rules/AGENTS.md` | Standing security instructions for agents |
| `skills/security-guidance/SKILL.md` | Skill for running security audits and remediating findings |
| `sidecars/panel/sidecar.json` | Sidecar manifest |
| `sidecars/panel/main.mjs` | Sidecar backend and REST API |
| `sidecars/panel/lib/core.mjs` | The same rules as regular expressions, for the panel's ad-hoc scans and summary |
| `sidecars/panel/lib/openui.mjs` | OpenUI Lang v0.5 parser, renderer, and state serializer |
| `sidecars/panel/{index.html,app.js,styles.css}` | Interactive security dashboard and ad-hoc scanner |

## Test

From the plugin folder:

```bash
node --test sidecars/panel/lib/
rustc --edition 2021 --test hooks/src/lib.rs -o /tmp/security-guidance-test && /tmp/security-guidance-test
```

Or through Bazel in the monorepo:

```bash
bazel test //apps/desktop/antigravity/plugins/security-guidance/...
```
