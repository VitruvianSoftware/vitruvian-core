---
name: security-guidance
description: Run static security audits on code and diffs, remediate dangerous constructs (eval, innerHTML, pickle, yaml.load, torch.load, shell=True, SQLi, SSRF, hardcoded secrets), and manage inline suppressions.
---

# Security Guidance Skill

Use this skill when auditing code changes for security vulnerabilities,
responding to a `security-guidance` hook warning, or remediating findings
reported in the Security Guidance sidecar panel.

## Safe Replacements Reference

| Vulnerable Pattern | Rule ID | Safe Replacement |
| --- | --- | --- |
| `element.innerHTML = untrusted` | `dom-xss-innerhtml` | `element.textContent = untrusted` or `DOMPurify.sanitize(...)` |
| `eval(expr)` / `new Function(code)` | `js-eval` | `JSON.parse(...)` or explicit dispatch tables |
| `yaml.load(stream)` | `python-yaml-unsafe-load` | `yaml.safe_load(stream)` or `yaml.load(stream, Loader=yaml.SafeLoader)` |
| `pickle.loads(data)` | `python-pickle-loads` | `json.loads(data)` or schema-validated serialization |
| `torch.load(path)` | `pytorch-unsafe-load` | `torch.load(path, weights_only=True)` |
| `subprocess.run(cmd, shell=True)` | `python-subprocess-shell` | `subprocess.run(["cmd", arg1, arg2], check=True)` |
| `child_process.exec(\`cmd \${x}\`)` | `node-child-process-exec` | `child_process.execFile("cmd", [x])` |
| ``SELECT * FROM t WHERE id = ${id}`` | `sql-string-concat` | Parameterized query (`WHERE id = $1`, `[id]`) |
| `${{ github.event.issue.title }}` in `run:` | `github-actions-script-injection` | Bind to an `env:` variable first and reference `"$TITLE"` |

## Inline Suppression Syntax

When a finding is an intentional test fixture or verified false positive, add an
inline suppression comment on the same line:

- JavaScript / TypeScript / Go / C++: `// security-guidance-ignore: <rule-id>` (or `// security-guidance-ignore` to suppress all rules on that line)
- Python / Shell / YAML: `# security-guidance-ignore: <rule-id>` or `# nosec <rule-id>`
