# security-guidance: real-time vulnerability and secret guardrails

The `security-guidance` plugin scans `edit_file`, `write_file`, and
`run_command` tool calls before execution.

## How to handle Security Guidance alerts

- **Critical findings (`deny`):** Hardcoded credentials (PEM private keys, AWS
  keys, GCP API keys, GitHub tokens) and remote shell piping (`curl ... | sh`)
  are blocked automatically. Never hardcode secrets in source files; load them
  from environment variables or secret managers instead.
- **High / Medium findings (`ask`):** Constructs such as `eval()`,
  `.innerHTML`, `pickle.loads()`, `yaml.load()` without `SafeLoader`,
  `torch.load()` without `weights_only=True`, `subprocess` with `shell=True`,
  and SQL string concatenation trigger a security warning. Prefer the safe
  alternative named in the remediation hint:
  - Replace `.innerHTML` with `.textContent` or DOM APIs.
  - Replace `yaml.load(data)` with `yaml.safe_load(data)`.
  - Pass `weights_only=True` to `torch.load(...)`.
  - Pass argument arrays without `shell=True` to `subprocess.run([...])`.
  - Use parameterized queries (`$1`, `?`) instead of string interpolation in SQL.
- **Intentional false positives:** If a pattern is genuinely required (for
  example inside a unit test fixture), annotate that line with
  `// security-guidance-ignore: <rule-id>` or `# nosec <rule-id>`.
