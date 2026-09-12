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
// Channel allow-list
// ---------------------------------------------------------------------------
//
// SLACK_CHANNEL_IDS historically gated only `listChannels` — it filtered what
// the server would *enumerate* and nothing else. Every other channel-scoped
// call (history, info, thread replies, and the write paths) passed the caller's
// channel ID straight through to Slack, so a caller who already knew an ID read
// or wrote that conversation regardless of the setting.
//
// That is harmless for stdio, where the caller is a local process the user
// started themselves. It is not harmless for a network-reachable listener: the
// bot token carries `groups:history`, `im:history` and `mpim:history`, so
// "anything you can name" spans private channels and DMs the bot belongs to.
//
// This module turns that listing filter into an actual boundary. The guard is
// mandatory on the HTTP transport and absent on stdio, which preserves existing
// local behaviour exactly.

/** Raised when a caller names a channel outside the configured allow-list. */
export class ChannelNotAllowedError extends Error {
  readonly channelId: string;

  constructor(channelId: string) {
    super(
      `Channel ${channelId} is not in this server's allow-list. ` +
        `Remote access is restricted to the channels listed in SLACK_CHANNEL_IDS.`
    );
    this.name = "ChannelNotAllowedError";
    this.channelId = channelId;
  }
}

/** Raised when a channel is declared both public and private. */
export class ConflictingChannelDeclarationError extends Error {
  constructor(ids: string[]) {
    super(
      `Channel(s) ${ids.join(", ")} appear in both SLACK_CHANNEL_IDS and ` +
        `SLACK_PRIVATE_CHANNEL_IDS. A channel is one or the other; listing it ` +
        `twice means one of the two declarations is wrong, and guessing which ` +
        `would defeat the point of declaring visibility separately.`
    );
    this.name = "ConflictingChannelDeclarationError";
  }
}

/**
 * Raised when Slack disagrees with how a channel was declared.
 *
 * The case this exists for: an operator means to add a public channel and
 * pastes a private one. With a single allow-list that is undetectable — the ID
 * is on the list, so it is admitted. Declaring visibility separately turns it
 * into a contradiction, and a private conversation reached through a line that
 * claims to be public is exactly the mistake worth refusing.
 */
export class ChannelVisibilityMismatchError extends Error {
  constructor(channelId: string, declared: ChannelVisibility) {
    super(
      `Channel ${channelId} is declared ${declared} in configuration, but ` +
        `Slack reports it as ${declared === "public" ? "private" : "public"}. ` +
        `Refusing rather than resolving the disagreement. If that access is ` +
        `genuinely wanted, move the ID from ` +
        `${declared === "public" ? "SLACK_CHANNEL_IDS to SLACK_PRIVATE_CHANNEL_IDS" : "SLACK_PRIVATE_CHANNEL_IDS to SLACK_CHANNEL_IDS"}` +
        ` — deliberately, because granting a public endpoint access to a ` +
        `private conversation is the decision the two lists exist to make visible.`
    );
    this.name = "ChannelVisibilityMismatchError";
  }
}

/**
 * Raised when a channel's visibility could not be established at all.
 *
 * Distinct from a mismatch on purpose. A mismatch means Slack answered and
 * disagreed; this means Slack did not answer the question, so there is nothing
 * to compare the declaration against. Treating "unverified" as "verified fine"
 * is the failure this whole module exists to avoid, and it would be invisible:
 * a missing field reads exactly like a passing check.
 */
export class ChannelVisibilityUnverifiableError extends Error {
  constructor(channelId: string, received: unknown) {
    super(
      `Cannot determine whether channel ${channelId} is private: Slack's ` +
        `response carried is_private as ${Object.prototype.toString.call(received)} ` +
        `rather than a boolean. Refusing rather than assuming the declaration ` +
        `was correct.`
    );
    this.name = "ChannelVisibilityUnverifiableError";
  }
}

/** Raised at startup when the HTTP transport has no usable allow-list. */
export class MissingAllowlistError extends Error {
  constructor() {
    super(
      "SLACK_CHANNEL_IDS must list at least one channel ID when " +
        "MCP_TRANSPORT=http. Refusing to expose an unbounded Slack surface."
    );
    this.name = "MissingAllowlistError";
  }
}

/** Raised when a channel parameter is present but cannot be checked. */
export class UnusableChannelParamError extends Error {
  constructor(value: unknown) {
    super(
      `Channel parameter must be a non-empty string; received ` +
        `${Object.prototype.toString.call(value)}. Refusing the call rather ` +
        `than sending an unverifiable channel to Slack.`
    );
    this.name = "UnusableChannelParamError";
  }
}

/**
 * What a request's parameters say about which channel it targets.
 *
 * Three cases, kept distinct on purpose. Collapsing "no channel parameter"
 * with "a channel parameter I can't read" is what makes a guard fail open:
 * the value is still sent to Slack, and the GET branch stringifies it, so
 * `{channel: ["C0PRIVATE"]}` reaches Slack as `channel=C0PRIVATE` while the
 * allow-list sees nothing to check. A single-element array and any object
 * with a `toString` both do this.
 */
export type ChannelParam =
  | { kind: "absent" }
  | { kind: "channel"; channelId: string }
  | { kind: "unusable"; value: unknown };

/**
 * Reads the channel a Slack request is addressed to.
 *
 * Slack is inconsistent about the parameter name: `channel` on the
 * conversations, chat and pins families, `channel_id` on bookmarks and
 * canvases. Enforcement anchors here rather than on wrapper-method
 * signatures, so this is the one piece that has to know both spellings.
 */
export function readChannelParam(
  params: Record<string, unknown>
): ChannelParam {
  const hasChannel = Object.prototype.hasOwnProperty.call(params, "channel");
  const hasChannelId = Object.prototype.hasOwnProperty.call(
    params,
    "channel_id"
  );
  if (!hasChannel && !hasChannelId) return { kind: "absent" };

  const value = hasChannel ? params.channel : params.channel_id;

  // Absent and explicitly-undefined/null are the same intent: the caller is
  // not naming a channel. createCanvas omits it this way.
  if (value === undefined || value === null) return { kind: "absent" };

  if (typeof value !== "string" || value.length === 0) {
    return { kind: "unusable", value };
  }
  return { kind: "channel", channelId: value };
}

/**
 * Applies `guard` to a Slack request's parameters, failing closed.
 *
 * This lives here rather than on the client so the *decision* — not just the
 * extraction — is directly testable. The original defect was in what the
 * caller concluded from a `undefined` return, one layer above a function that
 * was itself behaving correctly.
 */
export function assertParamsAllowed(
  guard: ChannelGuard,
  params: Record<string, unknown>
): void {
  const param = readChannelParam(params);
  if (param.kind === "absent") return;
  if (param.kind === "unusable") throw new UnusableChannelParamError(param.value);
  guard.assertAllowed(param.channelId);
}

/** How a channel was declared, which is what makes a mismatch detectable. */
export type ChannelVisibility = "public" | "private";

export interface ChannelGuard {
  /** Channel IDs this server may touch, in configuration order. */
  readonly allowed: readonly string[];
  /** Only those declared public. */
  readonly publicChannels: readonly string[];
  /** Only those declared private — granted deliberately, per channel. */
  readonly privateChannels: readonly string[];
  /**
   * How the operator declared this channel, or undefined if not allowed.
   *
   * The point of keeping the two lists apart: with one list, "is it allowed"
   * and "is it explicitly listed as private" are the same question, so a check
   * against Slack's own `is_private` can only ever agree with the guard. Two
   * lists make "declared public, Slack says private" a contradiction the code
   * can see.
   */
  declaredVisibility(channelId: string): ChannelVisibility | undefined;
  /**
   * Checks Slack's own `is_private` against how the channel was declared.
   *
   * Call this wherever `is_private` is *already* in hand — `conversations.info`
   * returns it, so `listChannels` and `getChannelInfo` get the check for free.
   * It deliberately does not fetch: making `history` and `replies` verify would
   * add a round trip to the hot path to re-answer a question startup already
   * settled.
   *
   * A no-op unless the guard was built with `enforceVisibility`, which is the
   * HTTP transport only. See {@link createChannelGuard}.
   */
  assertVisibilityMatches(channelId: string, isPrivate: unknown): void;
  /** Throws {@link ChannelNotAllowedError} unless `channelId` is allowed. */
  assertAllowed(channelId: string): void;
  /** Non-throwing form, for filtering rather than rejecting. */
  isAllowed(channelId: string): boolean;
}

/**
 * Splits the raw `SLACK_CHANNEL_IDS` value into channel IDs.
 *
 * Tolerates the shapes people actually produce when pasting from Slack's UI —
 * surrounding whitespace, trailing commas, blank entries — because a silently
 * dropped ID here means a channel that mysteriously fails at request time.
 */
export function parseChannelIds(raw: string | undefined): string[] {
  if (!raw) return [];
  const seen = new Set<string>();
  const ids: string[] = [];
  for (const part of raw.split(",")) {
    const id = part.trim();
    if (id.length === 0 || seen.has(id)) continue;
    seen.add(id);
    ids.push(id);
  }
  return ids;
}

/**
 * Builds the guard applied to every channel-scoped call on the HTTP transport.
 *
 * `required` is true for HTTP and false for stdio. When not required and no IDs
 * are configured, the returned guard allows everything — that is the existing
 * local behaviour and changing it would break every current stdio user.
 *
 * `enforceVisibility` is also HTTP-only, and is a *separate* flag rather than a
 * second reading of `required` because it answers a different question. A stdio
 * user may set `SLACK_CHANNEL_IDS` today to filter what gets listed; they have
 * never been asked to say which of those channels are private, so every one of
 * them would read as declared-public and any private channel among them would
 * start failing. `required` asks "may this list be empty"; `enforceVisibility`
 * asks "may Slack contradict the declaration". They coincide today only because
 * both happen to be properties of the HTTP transport.
 */
export function createChannelGuard(
  raw: string | undefined,
  {
    required,
    enforceVisibility = false,
  }: { required: boolean; enforceVisibility?: boolean },
  rawPrivate?: string
): ChannelGuard {
  const publicChannels = parseChannelIds(raw);
  const privateChannels = parseChannelIds(rawPrivate);
  const allowed = [...publicChannels, ...privateChannels];

  const overlap = publicChannels.filter((id) => privateChannels.includes(id));
  if (overlap.length > 0) {
    throw new ConflictingChannelDeclarationError(overlap);
  }

  if (allowed.length === 0) {
    if (required) throw new MissingAllowlistError();
    return {
      allowed: [],
      publicChannels: [],
      privateChannels: [],
      declaredVisibility: () => undefined,
      // Nothing was declared, so there is nothing for Slack to contradict.
      // This is the same reason isAllowed returns true above, and it is why
      // assertVisibilityMatches cannot simply key off declaredVisibility being
      // undefined: on this guard it is undefined for every channel in the
      // workspace, so that reading would refuse every stdio call.
      assertVisibilityMatches: () => {},
      assertAllowed: () => {},
      isAllowed: () => true,
    };
  }

  const publicSet = new Set(publicChannels);
  const privateSet = new Set(privateChannels);
  const declaredVisibility = (
    channelId: string
  ): ChannelVisibility | undefined =>
    publicSet.has(channelId)
      ? "public"
      : privateSet.has(channelId)
        ? "private"
        : undefined;

  const checkVisibility = (channelId: string, isPrivate: unknown): void => {
    const declared = declaredVisibility(channelId);
    // Fail closed on its own terms rather than leaning on assertAllowed having
    // already refused this channel somewhere upstream. That would be true
    // today and silently false the first time this is called from a path that
    // reaches Slack by some other route — and the symptom would be an
    // undeclared channel passing a check named "assert".
    if (declared === undefined) throw new ChannelNotAllowedError(channelId);
    if (typeof isPrivate !== "boolean") {
      throw new ChannelVisibilityUnverifiableError(channelId, isPrivate);
    }
    if (declared !== (isPrivate ? "private" : "public")) {
      throw new ChannelVisibilityMismatchError(channelId, declared);
    }
  };

  return {
    allowed,
    publicChannels,
    privateChannels,
    assertVisibilityMatches: enforceVisibility ? checkVisibility : () => {},
    declaredVisibility,
    isAllowed: (channelId: string) =>
      publicSet.has(channelId) || privateSet.has(channelId),
    assertAllowed: (channelId: string) => {
      if (!publicSet.has(channelId) && !privateSet.has(channelId)) {
        throw new ChannelNotAllowedError(channelId);
      }
    },
  };
}

