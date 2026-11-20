// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

export interface VitruvianUsageLimitParams {
  readonly sessionId: string;
  readonly resetsAt: string | null;
  readonly message: string;
}

const MAX_DATE_MS = 8.64e15;
const MAX_WAIT_MS = 30 * 24 * 60 * 60 * 1000;

const WINDOW_LABELS: Readonly<Record<string, string>> = {
  five_hour: "5-hour",
  seven_day: "7-day",
  seven_day_opus: "7-day Opus",
  seven_day_sonnet: "7-day Sonnet",
  seven_day_overage_included: "7-day model",
  overage: "overage",
};

const GATEWAY_503_RATE_LIMIT_RE =
  /^API Error: 503 \[[^\]\r\n]+\] \[429\]: \{"type":"error","error":\{"type":"rate_limit_error",[^\r\n]*\} \(reset after (?:(\d+)h ?)?(?:(\d+)m ?)?(?:(\d+)s)?\)/;
const GATEWAY_RESET_AFTER_RE =
  /\(reset after (?:(\d+)h ?)?(?:(\d+)m ?)?(?:(\d+)s)?\)/;
const USAGE_LIMIT_TEXT_RE =
  /usage limit|rate limit|rate_limit_error|hit your limit|quota exceeded/i;
const AUTH_TEXT_RE =
  /authentication_failed|auth_required|not logged in|invalid api key|claude auth login|unauthorized/i;

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Converts epoch seconds to an ISO-8601 UTC string (T3 `claudeUsageLimits.ts:128-132`, `ClaudeAdapterV2.ts:4134-4139`). */
export function isoFromEpochSeconds(value: unknown): string | null {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
    return null;
  }
  const ms = value * 1000;
  if (ms >= MAX_DATE_MS) {
    return null;
  }
  return new Date(ms).toISOString();
}

/** Converts either epoch seconds or an ISO timestamp string to canonical ISO-8601 UTC. */
export function isoFromTimestamp(value: unknown): string | null {
  if (typeof value === "number") {
    return isoFromEpochSeconds(value);
  }
  if (typeof value === "string" && value.trim().length > 0) {
    const parsed = Date.parse(value);
    if (Number.isFinite(parsed) && parsed > 0 && parsed < MAX_DATE_MS) {
      return new Date(parsed).toISOString();
    }
  }
  return null;
}

/** Parses gateway `(reset after Xh Ym Zs)` cooldown durations (T3 `ClaudeAdapterV2.ts:4141-4152`). */
export function parseGatewayCooldownResetAt(
  text: string,
  nowMs: number = Date.now(),
): string | null {
  const match = GATEWAY_RESET_AFTER_RE.exec(text);
  if (!match) {
    return null;
  }
  const seconds =
    Number(match[1] ?? 0) * 3_600 +
    Number(match[2] ?? 0) * 60 +
    Number(match[3] ?? 0);
  if (seconds <= 0 || !Number.isFinite(nowMs)) {
    return null;
  }
  const resetMs = nowMs + seconds * 1_000;
  return resetMs > 0 && resetMs < MAX_DATE_MS
    ? new Date(resetMs).toISOString()
    : null;
}

function isOverageAllowed(info: Record<string, unknown>): boolean {
  return (
    info.overageStatus === "allowed" ||
    info.overageStatus === "allowed_warning" ||
    info.isUsingOverage === true ||
    info.overageInUse === true
  );
}

function formatWaitDuration(waitMs: number): string {
  const totalMinutes = Math.ceil(waitMs / 60_000);
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  if (hours > 0 && minutes > 0) {
    return `${hours}h ${minutes}m`;
  }
  if (hours > 0) {
    return `${hours}h`;
  }
  return `${Math.max(1, minutes)}m`;
}

function describeRateLimitMessage(
  info: Record<string, unknown>,
  resetsAt: string | null,
  nowMs: number,
): string {
  const rawType =
    typeof info.rateLimitType === "string" ? info.rateLimitType : undefined;
  const label = rawType ? WINDOW_LABELS[rawType] : undefined;
  const resetMs = resetsAt !== null ? Date.parse(resetsAt) : NaN;
  const waitMs =
    Number.isFinite(resetMs) && Number.isFinite(nowMs)
      ? resetMs - nowMs
      : undefined;
  const wait =
    waitMs !== undefined && waitMs > 0 && waitMs <= MAX_WAIT_MS
      ? formatWaitDuration(waitMs)
      : undefined;

  if (wait) {
    return `Claude usage limit reached. This turn is paused until the ${label ? `${label} ` : ""}limit resets in ${wait}.`;
  }
  if (resetsAt) {
    return `Claude usage limit reached (${label ? `${label} ` : ""}limit). Resets at ${resetsAt}.`;
  }
  return "Claude usage limit reached. Please wait before sending another prompt.";
}

function extractAssistantText(messageRecord: Record<string, unknown>): string {
  const content = messageRecord.content;
  if (!Array.isArray(content)) {
    return "";
  }
  const parts: string[] = [];
  for (const block of content) {
    if (
      isPlainRecord(block) &&
      block.type === "text" &&
      typeof block.text === "string" &&
      block.text.trim().length > 0
    ) {
      parts.push(block.text.trim());
    }
  }
  return parts.join(" ");
}

function extractResultText(msg: Record<string, unknown>): string {
  if (msg.subtype === "success") {
    return typeof msg.result === "string" ? msg.result.trim() : "";
  }
  if (Array.isArray(msg.errors)) {
    const userFacing = msg.errors.find(
      (entry): entry is string =>
        typeof entry === "string" &&
        entry.trim().length > 0 &&
        !entry.startsWith("[ede_diagnostic]"),
    );
    if (userFacing) {
      return userFacing.trim();
    }
  }
  return "";
}

/**
 * Extracts `_vitruvian/usageLimit` notification params from SDK rate-limit, assistant, or result messages.
 * Follows T3 `claudeUsageLimits.ts` and `ClaudeAdapterV2.ts:4117-4246, 9141-9195, 9423-9438, 10331-10402`.
 */
export function extractUsageLimit(
  sessionId: string,
  message: unknown,
  options?: { readonly nowMs?: number },
): VitruvianUsageLimitParams | null {
  if (!isPlainRecord(message) || typeof message.type !== "string") {
    return null;
  }
  const nowMs = options?.nowMs ?? Date.now();

  // 1. Live `rate_limit_event` frames from the SDK.
  if (message.type === "rate_limit_event") {
    const info = message.rate_limit_info;
    if (!isPlainRecord(info)) {
      return null;
    }
    if (isOverageAllowed(info) || info.status !== "rejected") {
      return null;
    }
    const resetsAt = isoFromTimestamp(info.resetsAt);
    return {
      sessionId,
      resetsAt,
      message: describeRateLimitMessage(info, resetsAt, nowMs),
    };
  }

  // 2. Blocked synthetic `assistant` message with `error: "rate_limit"` (`ClaudeAdapterV2.ts:9423-9438`).
  if (message.type === "assistant" && message.error === "rate_limit") {
    const apiParams = isPlainRecord(message.api_error_params)
      ? message.api_error_params
      : undefined;
    const info =
      apiParams && isPlainRecord(apiParams.rate_limit_info)
        ? apiParams.rate_limit_info
        : undefined;
    if (info && isOverageAllowed(info)) {
      return null;
    }
    const resetsAt = info ? isoFromTimestamp(info.resetsAt) : null;
    const assistantMsg = isPlainRecord(message.message)
      ? extractAssistantText(message.message)
      : "";
    const text =
      assistantMsg.length > 0
        ? assistantMsg
        : describeRateLimitMessage(info ?? {}, resetsAt, nowMs);
    return {
      sessionId,
      resetsAt,
      message: text,
    };
  }

  // 3. Terminal `result` messages carrying 429, gateway 503->429, or blocking_limit (`ClaudeAdapterV2.ts:4173-4246`).
  if (message.type === "result") {
    const text = extractResultText(message);
    if (AUTH_TEXT_RE.test(text)) {
      return null;
    }

    if (message.subtype === "success") {
      if (message.is_error !== true) {
        return null;
      }
      if (message.api_error_status === 429) {
        const resetsAt = text.startsWith("API Error:")
          ? parseGatewayCooldownResetAt(text, nowMs)
          : null;
        return {
          sessionId,
          resetsAt,
          message: "Claude API rate limit reached. Try again later.",
        };
      }
      if (
        message.terminal_reason === "api_error" &&
        message.api_error_status === 503 &&
        GATEWAY_503_RATE_LIMIT_RE.test(text)
      ) {
        return {
          sessionId,
          resetsAt: parseGatewayCooldownResetAt(text, nowMs),
          message: "Claude API rate limit reached. Try again later.",
        };
      }
      if (message.terminal_reason === "blocking_limit") {
        return {
          sessionId,
          resetsAt: parseGatewayCooldownResetAt(text, nowMs),
          message:
            text.length > 0
              ? text
              : "Claude usage limit reached. Send the message again once the limit resets.",
        };
      }
      return null;
    }

    if (
      message.terminal_reason === "blocking_limit" ||
      USAGE_LIMIT_TEXT_RE.test(text)
    ) {
      return {
        sessionId,
        resetsAt: parseGatewayCooldownResetAt(text, nowMs),
        message:
          text.length > 0
            ? text
            : "Claude usage limit reached. Send the message again once the limit resets.",
      };
    }
  }

  return null;
}
