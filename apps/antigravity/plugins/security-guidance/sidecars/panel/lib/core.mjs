/**
 * Copyright (c) 2026 VitruvianSoftware
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

// Pure vulnerability scanner, unified diff analyser, inline suppression filter,
// and state summariser for the security-guidance Antigravity plugin.

export const BUILTIN_PATTERNS = [
  {
    id: "hardcoded-private-key",
    category: "secrets",
    severity: "critical",
    cwe: "CWE-798",
    regex:
      /-----BEGIN\s+(?:RSA\s+|EC\s+|DSA\s+|OPENSSH\s+|PGP\s+)?PRIVATE\s+KEY-----/,
    message: "Hardcoded PEM private key block detected.",
    remediation:
      "Remove private keys from source code and load them from secret managers or environment variables at runtime.",
  },
  {
    id: "aws-access-key",
    category: "secrets",
    severity: "critical",
    cwe: "CWE-798",
    regex: /\b(?:AKIA|ASIA)[0-9A-Z]{16}\b/,
    message: "Hardcoded AWS Access Key ID detected.",
    remediation:
      "Use IAM workload identity federation or environment credentials instead of embedding AWS access keys.",
  },
  {
    id: "gcp-api-key",
    category: "secrets",
    severity: "high",
    cwe: "CWE-798",
    regex: /\bAIza[0-9A-Za-z_-]{33,39}\b/,
    message: "Hardcoded Google Cloud API key detected.",
    remediation:
      "Inject API keys via secret manager or runtime environment variables and restrict key scope.",
  },
  {
    id: "github-pat",
    category: "secrets",
    severity: "critical",
    cwe: "CWE-798",
    regex: /\b(?:ghp_[0-9A-Za-z]{36}|github_pat_[0-9A-Za-z_]{50,})\b/,
    message: "Hardcoded GitHub Personal Access Token detected.",
    remediation:
      "Revoke the token immediately and use short-lived GitHub App installation tokens instead.",
  },
  {
    id: "command-injection-curl-sh",
    category: "command-injection",
    severity: "critical",
    cwe: "CWE-78",
    regex: /\b(?:curl|wget)\b[^\n|]*\|\s*(?:sudo\s+)?(?:ba)?sh\b/,
    message: "Remote script piped directly into a shell interpreter.",
    remediation:
      "Download the artifact to a temporary file, verify its cryptographic checksum or signature, and then execute it.",
  },
  {
    id: "js-eval",
    category: "code-injection",
    severity: "high",
    cwe: "CWE-95",
    regex: /\b(?:eval\s*\(|new\s+Function\s*\()/,
    message: "Dynamic JavaScript code execution via eval() or new Function().",
    remediation:
      "Use JSON.parse() for data parsing or an explicit lookup table instead of dynamic code evaluation.",
  },
  {
    id: "dom-xss-innerhtml",
    category: "xss",
    severity: "high",
    cwe: "CWE-79",
    regex: /(?:\.innerHTML\s*=|dangerouslySetInnerHTML\s*=)/,
    message:
      "Potential DOM XSS via direct HTML injection (.innerHTML / dangerouslySetInnerHTML).",
    remediation:
      "Use .textContent, safe DOM node construction, or sanitize untrusted HTML with DOMPurify before rendering.",
  },
  {
    id: "python-pickle-loads",
    category: "deserialization",
    severity: "high",
    cwe: "CWE-502",
    regex: /\b(?:c?pickle)\.(?:loads?|Unpickler)\s*\(/,
    message: "Unsafe Python pickle deserialization can execute arbitrary code.",
    remediation:
      "Use json.loads(), msgpack, or protobuf instead of unpickling untrusted bytes.",
  },
  {
    id: "python-yaml-unsafe-load",
    category: "deserialization",
    severity: "high",
    cwe: "CWE-502",
    regex: /\byaml\.load\s*\((?![^)]*SafeLoader)/,
    message:
      "yaml.load() called without SafeLoader allows arbitrary object instantiation.",
    remediation:
      "Use yaml.safe_load() or pass Loader=yaml.SafeLoader explicitly.",
  },
  {
    id: "pytorch-unsafe-load",
    category: "deserialization",
    severity: "high",
    cwe: "CWE-502",
    regex: /\btorch\.load\s*\((?![^)]*weights_only\s*=\s*True)/,
    message:
      "torch.load() without weights_only=True uses pickle under the hood.",
    remediation: "Pass weights_only=True to torch.load() or use safetensors.",
  },
  {
    id: "python-subprocess-shell",
    category: "command-injection",
    severity: "high",
    cwe: "CWE-78",
    regex:
      /\b(?:subprocess\.(?:run|Popen|call|check_output|check_call)\s*\([^)]*shell\s*=\s*True|os\.system\s*\()/,
    message:
      "Shell command execution via subprocess(shell=True) or os.system().",
    remediation:
      "Pass an argument list (e.g. subprocess.run(['cmd', arg])) with shell=False.",
  },
  {
    id: "node-child-process-exec",
    category: "command-injection",
    severity: "medium",
    cwe: "CWE-78",
    regex: /\b(?:exec|execSync)\s*\(\s*`[^`]*\$\{/,
    message:
      "Interpolated template literal passed to child_process.exec / execSync.",
    remediation:
      "Use execFile / execFileSync or spawn with an explicit arguments array instead of shell interpolation.",
  },
  {
    id: "sql-string-concat",
    category: "sql-injection",
    severity: "high",
    cwe: "CWE-89",
    regex:
      /\b(?:SELECT|INSERT\s+INTO|UPDATE|DELETE\s+FROM)\b[^\n;`'"]*(?:\+\s*[A-Za-z_$]|\$\{[^}]+\})/i,
    message:
      "SQL statement constructed using string concatenation or template interpolation.",
    remediation:
      "Use parameterized queries ($1, ?) with bound parameter arrays.",
  },
  {
    id: "path-traversal",
    category: "path-traversal",
    severity: "medium",
    cwe: "CWE-22",
    regex: /(?:\.\.\/){2,}/,
    message: "Multi-level relative path traversal sequence (../../) detected.",
    remediation:
      "Resolve paths with path.resolve() and verify they remain inside the allowed base directory.",
  },
  {
    id: "ssrf-metadata-ip",
    category: "ssrf",
    severity: "high",
    cwe: "CWE-918",
    regex: /\b169\.254\.169\.254\b/,
    message:
      "Cloud instance metadata service IP (169.254.169.254) referenced directly.",
    remediation:
      "Block link-local metadata addresses in outbound HTTP validators and use official SDK credential providers.",
  },
  {
    id: "github-actions-script-injection",
    category: "code-injection",
    severity: "high",
    cwe: "CWE-94",
    regex:
      /\$\{\{\s*github\.event\.(?:issue|pull_request|comment|review|commits|head_commit)\.[^}]+\}\}/,
    message:
      "Untrusted GitHub event context interpolated directly in workflow.",
    remediation:
      "Bind the expression to an intermediate step env: variable and reference it as a quoted shell variable.",
  },
];

/**
 * Checks whether a single source line has an inline suppression comment for
 * `ruleId` (`security-guidance-ignore` or `nosec`).
 *
 * @param {string} lineText
 * @param {string} ruleId
 * @returns {boolean}
 */
export function hasInlineSuppression(lineText, ruleId) {
  const text = String(lineText ?? "");
  const igMatch = text.match(
    /(?:\/\/|#)\s*(?:security-guidance-ignore|nosec)(?:\s*:\s*([A-Za-z0-9_,\s-]+))?/i,
  );
  if (!igMatch) return false;
  if (!igMatch[1]) return true;
  const ids = igMatch[1]
    .split(",")
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);
  return (
    ids.includes("*") ||
    ids.includes("all") ||
    ids.includes(ruleId.toLowerCase())
  );
}

/**
 * Scans a string of source code or shell commands against `BUILTIN_PATTERNS`
 * (or a custom pattern list), respecting inline suppression comments.
 *
 * @param {string} content
 * @param {{ filePath?: string, patterns?: Array<Record<string, any>>, startLine?: number }} [options]
 * @returns {Array<Record<string, any>>}
 */
export function scanContentForPatterns(content, options = {}) {
  const text = String(content ?? "").replaceAll("\r\n", "\n");
  if (!text) return [];
  const filePath = String(options.filePath || "<inline>");
  const patterns = Array.isArray(options.patterns)
    ? options.patterns
    : BUILTIN_PATTERNS;
  const startLine =
    Number(options.startLine) > 0 ? Number(options.startLine) : 1;

  const lines = text.split("\n");
  const findings = [];

  for (let i = 0; i < lines.length; i++) {
    const lineText = lines[i];
    const lineNum = startLine + i;
    for (const pat of patterns) {
      if (!pat || !(pat.regex instanceof RegExp)) continue;
      if (pat.regex.test(lineText)) {
        if (hasInlineSuppression(lineText, pat.id)) continue;
        findings.push({
          id: `${pat.id}:${filePath}:${lineNum}`,
          ruleId: pat.id,
          category: pat.category || "security",
          severity: pat.severity || "medium",
          cwe: pat.cwe || "CWE-20",
          filePath,
          line: lineNum,
          snippet: lineText.trim().slice(0, 160),
          message: pat.message,
          remediation: pat.remediation,
        });
      }
    }
  }

  return findings;
}

/**
 * Scans a unified git diff (only added `+` lines) for vulnerabilities and
 * attributes each finding to its target file and new-file line number.
 *
 * @param {string} diffText
 * @param {{ patterns?: Array<Record<string, any>> }} [options]
 * @returns {Array<Record<string, any>>}
 */
export function scanDiffForVulnerabilities(diffText, options = {}) {
  const lines = String(diffText ?? "")
    .replaceAll("\r\n", "\n")
    .split("\n");
  let currentFile = "<diff>";
  let currentLine = 1;
  const findings = [];

  for (const line of lines) {
    if (line.startsWith("+++ b/")) {
      currentFile = line.slice(6).trim();
      continue;
    }
    if (line.startsWith("+++ ")) {
      currentFile = line.slice(4).trim();
      continue;
    }
    const hunk = line.match(/^@@\s+-[0-9,]+\s+\+([0-9]+)(?:,[0-9]+)?\s+@@/);
    if (hunk) {
      currentLine = Number(hunk[1]);
      continue;
    }
    if (line.startsWith("+") && !line.startsWith("+++")) {
      const addedText = line.slice(1);
      const lineFindings = scanContentForPatterns(addedText, {
        filePath: currentFile,
        patterns: options.patterns,
        startLine: currentLine,
      });
      findings.push(...lineFindings);
      currentLine += 1;
    } else if (!line.startsWith("-") && !line.startsWith("\\")) {
      currentLine += 1;
    }
  }

  return findings;
}

/**
 * Filters out findings that match any stored suppression rule (by finding `id`,
 * `ruleId`, or `filePath`).
 *
 * @param {Array<Record<string, any>>} findings
 * @param {Array<string | Record<string, any>>} [suppressions]
 * @returns {Array<Record<string, any>>}
 */
export function filterSuppressedFindings(findings, suppressions = []) {
  const list = Array.isArray(findings) ? findings : [];
  const supList = Array.isArray(suppressions) ? suppressions : [];
  if (supList.length === 0) return list;

  return list.filter((f) => {
    if (!f || typeof f !== "object") return false;
    return !supList.some((s) => {
      if (typeof s === "string") {
        return s === f.id || s === f.ruleId || s === f.filePath;
      }
      if (s && typeof s === "object") {
        if (s.id && s.id === f.id) return true;
        if (s.ruleId && s.filePath) {
          return s.ruleId === f.ruleId && s.filePath === f.filePath;
        }
        if (s.ruleId && !s.filePath) return s.ruleId === f.ruleId;
      }
      return false;
    });
  });
}

/**
 * Summarises active findings, severity counts, and suppressions for the
 * Security Guidance panel and OpenUI Lang v0.5 view.
 *
 * @param {{ findings?: Array<Record<string, any>>, suppressions?: Array<any> }} [state]
 */
export function summariseSecurityState(state = {}) {
  const rawFindings = Array.isArray(state?.findings)
    ? state.findings.filter((f) => f && typeof f === "object")
    : [];
  const suppressions = Array.isArray(state?.suppressions)
    ? state.suppressions
    : [];
  const active = filterSuppressedFindings(rawFindings, suppressions);

  const counts = {
    critical: 0,
    high: 0,
    medium: 0,
    low: 0,
  };
  for (const f of active) {
    const sev = String(f.severity || "medium").toLowerCase();
    if (sev in counts) counts[sev] += 1;
    else counts.medium += 1;
  }

  return {
    totalActive: active.length,
    totalRecorded: rawFindings.length,
    suppressedCount:
      Math.max(0, rawFindings.length - active.length) || suppressions.length,
    counts,
    activeFindings: active,
  };
}
