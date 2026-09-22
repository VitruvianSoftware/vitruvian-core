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

// ---------------------------------------------------------------------------
// Slack URL parsing
// ---------------------------------------------------------------------------
//
// A permalink is the most common way a human hands a message to an agent, and
// the channel ID inside it is what the allow-list must inspect. Parsing lives
// here, as pure functions, so the tool layer can turn a URL into a channel and
// timestamp *before* the call is dispatched — `channelGuard` then sees a real
// channel ID rather than a string it cannot check. Passing the URL through and
// letting Slack resolve it would move the allow-list decision to after the
// request it exists to prevent.
//
// Everything fails closed: a URL this cannot read is refused, never guessed.

/** Raised when a URL is not a Slack permalink or file link this can read. */
export class InvalidPermalinkError extends Error {
  constructor(input: string, reason: string) {
    super(
      `Cannot parse "${input}" as a Slack link: ${reason}. Expected the form ` +
        `https://<workspace>.slack.com/archives/<channel>/p<timestamp>.`,
    );
    this.name = "InvalidPermalinkError";
  }
}

export interface MessageRef {
  channelId: string;
  /** Slack message timestamp, `seconds.micros`. */
  ts: string;
  /** Present only for a reply; the parent's timestamp. */
  threadTs?: string;
}

const CHANNEL_ID = /^[CDG][A-Z0-9]+$/;
const FILE_ID = /^F[A-Z0-9]+$/;
const SLACK_TS = /^\d+\.\d{6}$/;

/**
 * Workspace hosts only. Enterprise Grid uses `<org>.enterprise.slack.com`,
 * and both end in `.slack.com`; anything else — including a host that merely
 * *contains* `slack.com` — is refused.
 */
function isSlackHost(hostname: string): boolean {
  return hostname === "slack.com" || hostname.endsWith(".slack.com");
}

function parseUrl(input: string): URL {
  let url: URL;
  try {
    url = new URL(input);
  } catch {
    throw new InvalidPermalinkError(input, "not a URL");
  }
  if (url.protocol !== "https:") {
    throw new InvalidPermalinkError(input, "not an https URL");
  }
  if (!isSlackHost(url.hostname)) {
    throw new InvalidPermalinkError(
      input,
      `${url.hostname} is not a Slack host`,
    );
  }
  return url;
}

/**
 * Reads channel and timestamp out of a message permalink.
 *
 * `p1700000000123456` is the timestamp with the dot removed; it is restored
 * by splitting six digits from the end. A `thread_ts` query parameter marks a
 * reply and names its parent — unless it equals the message's own timestamp,
 * which is how Slack links a parent opened from the thread view.
 */
export function parsePermalink(input: string): MessageRef {
  const url = parseUrl(input);
  const match = /^\/archives\/([^/]+)\/p(\d{16})\/?$/.exec(url.pathname);
  if (!match) {
    throw new InvalidPermalinkError(
      input,
      "path is not /archives/<channel>/p<timestamp>",
    );
  }
  const channelId = match[1]!;
  if (!CHANNEL_ID.test(channelId)) {
    throw new InvalidPermalinkError(input, `${channelId} is not a channel ID`);
  }
  const digits = match[2]!;
  const ts = `${digits.slice(0, -6)}.${digits.slice(-6)}`;

  const threadTs = url.searchParams.get("thread_ts");
  if (threadTs === null || threadTs === ts) return { channelId, ts };
  if (!SLACK_TS.test(threadTs)) {
    throw new InvalidPermalinkError(
      input,
      `thread_ts=${threadTs} is not a Slack timestamp`,
    );
  }
  return { channelId, ts, threadTs };
}

/**
 * Accepts either a bare file ID or a Slack file URL and returns the ID.
 *
 * File URLs take the form `https://<ws>.slack.com/files/<user>/<file>/<name>`.
 * The ID is what `files.info` wants; nothing else in the URL is trusted.
 */
export function parseFileReference(input: string): string {
  const trimmed = input.trim();
  if (FILE_ID.test(trimmed)) return trimmed;
  if (!trimmed.startsWith("https://")) {
    throw new InvalidPermalinkError(input, "not a file ID or file URL");
  }
  const url = parseUrl(trimmed);
  const match = /^\/files\/[^/]+\/([^/]+)(?:\/|$)/.exec(url.pathname);
  if (!match || !FILE_ID.test(match[1]!)) {
    throw new InvalidPermalinkError(
      input,
      "path is not /files/<user>/<file id>/…",
    );
  }
  return match[1]!;
}
