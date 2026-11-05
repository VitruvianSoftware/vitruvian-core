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

// Pure log parsing and failure excerpt extraction: no I/O, so it runs under
// `node --test`.

const RUN_URL =
  /github\.com\/([^/\s]+)\/([^/\s]+)\/actions\/runs\/(\d+)(?:\/job\/(\d+))?/;

// Parses a GitHub Actions run or job URL from detailsUrl.
export function parseCheckUrl(url) {
  const match = RUN_URL.exec(url ?? "");
  if (!match) return null;
  return {
    owner: match[1],
    name: match[2],
    repo: `${match[1]}/${match[2]}`,
    runId: Number(match[3]),
    jobId: match[4] ? Number(match[4]) : null,
  };
}

const ANSI_REGEX = /\x1b\[[0-9;]*[a-zA-Z]/g;
const TIMESTAMP_REGEX = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z\s*/;

// Cleans one raw line of GitHub Actions log output.
// gh run view formats lines as: `<job>\t<step>\t<timestamp> <line>`
export function cleanLogLine(raw) {
  if (!raw) return "";
  let text = String(raw).replace(/^\uFEFF/, ""); // drop BOM
  const tabParts = text.split("\t");
  if (tabParts.length >= 3) {
    // Drop the job and step column prefixes
    text = tabParts.slice(2).join("\t");
  }
  text = text.replace(TIMESTAMP_REGEX, "");
  text = text.replace(ANSI_REGEX, "");
  return text.trimEnd();
}

const ERROR_MARKERS = [
  /##\[error\]/i,
  /::error::/i,
  /\bFAIL\b/,
  /\bFAILED\b/,
  /\bError:/,
  /process completed with exit code [1-9]/i,
  /build failed/i,
];

function isErrorLine(line) {
  return ERROR_MARKERS.some((re) => re.test(line));
}

// Extracts a concise, high-signal excerpt of a failed job log (capped at maxLines).
export function extractFailureExcerpt(rawLog, maxLines = 40) {
  if (!rawLog) return "No log output available.";
  const rawLines = String(rawLog).split(/\r?\n/);
  const cleaned = rawLines.map(cleanLogLine);

  // Find lines matching error markers
  const errorIndices = [];
  for (let i = 0; i < cleaned.length; i++) {
    if (isErrorLine(cleaned[i])) {
      errorIndices.push(i);
    }
  }

  if (errorIndices.length === 0) {
    // Fall back to the last non-empty lines
    const nonBlank = cleaned.filter((l) => l.trim().length > 0);
    return nonBlank.slice(-maxLines).join("\n") || "No log content found.";
  }

  // Focus around the errors: take from before the first error up to after the last error,
  // clamped to maxLines.
  const firstError = errorIndices[0];
  const lastError = errorIndices[errorIndices.length - 1];

  let start = Math.max(0, firstError - 15);
  let end = Math.min(cleaned.length, Math.max(lastError + 5, start + maxLines));

  if (end - start > maxLines) {
    // If the error span is wide, anchor toward the end of the error span
    start = Math.max(0, end - maxLines);
  }

  return cleaned.slice(start, end).join("\n").trim();
}
