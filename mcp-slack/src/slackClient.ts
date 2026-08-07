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
// Slack API client with dual-token support
// ---------------------------------------------------------------------------
//
// Split out of index.ts so its wiring is reachable from tests. Two of the
// defects found while building the HTTP transport lived here rather than in
// the primitives it calls — the primitives were correct and tested; the
// callers were neither.

import {
  assertParamsAllowed,
  type ChannelGuard,
} from "./channelAllowlist.js";
import type { SlackCredentials, WriteTokenPreference } from "./config.js";

/**
 * The user token was required by a call that reached the HTTP transport.
 *
 * Its own type rather than a bare Error so callers can tell it apart from a
 * network failure. It is a configuration/transport fault, and the startup
 * verifier would otherwise wrap it in a message asserting Slack was
 * unreachable — the exact inversion auth.ts stopped making when it began
 * discriminating on whether the library reached a verdict instead of assuming
 * a cause.
 */
export class UserTokenUnavailableError extends Error {
  constructor(method: string) {
    super(
      `Slack method ${method} requires the user token, which is not ` +
        `available on this transport.`
    );
    this.name = "UserTokenUnavailableError";
  }
}

export class SlackClient {
  private botHeaders: Record<string, string>;
  private userHeaders: Record<string, string> | undefined;
  private teamId: string;
  private channelGuard: ChannelGuard;
  private writeToken: WriteTokenPreference;

  constructor(
    slack: SlackCredentials,
    options: { channelGuard: ChannelGuard; writeToken: WriteTokenPreference }
  ) {
    this.botHeaders = {
      Authorization: `Bearer ${slack.botToken}`,
      "Content-Type": "application/json",
    };
    // Absent on the HTTP transport. resolveConfig refuses to start if a user
    // token is present there, so this is undefined by construction rather than
    // by a code path that could be changed later.
    this.userHeaders = slack.userToken
      ? {
          Authorization: `Bearer ${slack.userToken}`,
          "Content-Type": "application/json",
        }
      : undefined;
    this.teamId = slack.teamId;
    this.channelGuard = options.channelGuard;
    this.writeToken = options.writeToken;
  }

  /**
   * Enforces the channel allow-list on every outbound Slack call.
   *
   * This is the fix for `SLACK_CHANNEL_IDS` having only ever filtered
   * `listChannels`: without it, naming an ID was sufficient to read or write
   * any conversation the bot belongs to, including private channels and DMs.
   *
   * It lives in `api()` rather than at each call site on purpose. Guarding
   * per-method made enforcement depend on someone remembering to add a line
   * to each new method — and on the method's signature being shaped such that
   * the channel parameter is obvious. Two methods (`addBookmark`,
   * `createCanvas`) were missed on exactly that basis: one has a multi-line
   * signature, the other takes the channel third and optional. Anchoring on
   * the request parameters instead makes "a call naming a channel is checked"
   * a property of the transport rather than a coincidence of how the wrappers
   * happen to be written.
   *
   * Slack is inconsistent about the parameter name — `channel` on the
   * conversations/chat/pins families, `channel_id` on bookmarks and canvases —
   * so both are checked.
   */
  private guardParams(params: Record<string, unknown>): void {
    assertParamsAllowed(this.channelGuard, params);
  }


  // Helper to make Slack API calls
  private async api(
    method: string,
    params: Record<string, unknown>,
    token: "bot" | "user" = "bot",
    httpMethod: "GET" | "POST" = "GET"
  ): Promise<unknown> {
    this.guardParams(params);

    const headers = token === "bot" ? this.botHeaders : this.userHeaders;
    if (!headers) {
      // Reached only if a user-token tool is invoked on the HTTP transport.
      // Those tools are withheld from the HTTP tool list, so this is a
      // defence-in-depth backstop, not an expected path.
      throw new UserTokenUnavailableError(method);
    }

    if (httpMethod === "GET") {
      const qs = new URLSearchParams();
      for (const [k, v] of Object.entries(params)) {
        if (v !== undefined && v !== null) qs.append(k, String(v));
      }
      const res = await fetch(`https://slack.com/api/${method}?${qs}`, {
        headers,
      });
      return res.json();
    }

    const res = await fetch(`https://slack.com/api/${method}`, {
      method: "POST",
      headers,
      body: JSON.stringify(params),
    });
    return res.json();
  }

  // ── Channels (Bot Token) ────────────────────────────────────────────

  async listChannels(limit = 100, cursor?: string) {
    // Enumeration reads the same allow-list the guard enforces, rather than
    // re-parsing SLACK_CHANNEL_IDS from the environment. The two used to
    // diverge: this loop split on commas without dropping blanks, so
    // "C1,,C2" yielded an empty id — which conversations.info merely failed
    // on before, but which the guard now (correctly) refuses, taking the
    // whole listing down with it. A trailing comma is exactly the shape
    // parseChannelIds documents itself as tolerating, three lines away.
    if (this.channelGuard.allowed.length === 0) {
      const params: Record<string, unknown> = {
        types: "public_channel",
        exclude_archived: "true",
        limit: Math.min(limit, 200),
        team_id: this.teamId,
      };
      if (cursor) params.cursor = cursor;
      return this.api("conversations.list", params);
    }

    const channels = [];
    for (const channelId of this.channelGuard.allowed) {
      const data = (await this.api("conversations.info", {
        channel: channelId,
      })) as {
        ok: boolean;
        channel?: { is_archived: boolean; is_private?: unknown };
      };
      if (data.ok && data.channel) {
        // Before the archived filter, not after: a channel declared public
        // that Slack says is private is a contradiction worth refusing whether
        // or not it would have been listed.
        this.channelGuard.assertVisibilityMatches(
          channelId,
          data.channel.is_private
        );
        if (!data.channel.is_archived) channels.push(data.channel);
      }
    }
    return { ok: true, channels, response_metadata: { next_cursor: "" } };
  }

  async getChannelInfo(channelId: string) {
    const data = await this.api("conversations.info", {
      channel: channelId,
      include_num_members: "true",
    });
    const channel = (data as { channel?: { is_private?: unknown } }).channel;
    if (channel) {
      this.channelGuard.assertVisibilityMatches(channelId, channel.is_private);
    }
    return data;
  }

  /**
   * Confirms every allow-listed channel is what configuration says it is.
   *
   * Run once at HTTP startup, before the listener accepts anything, so the
   * operator finds out from a process that refuses to start rather than from a
   * private conversation reached through a line that claimed to be public.
   *
   * A channel the bot cannot see is also fatal here. It would otherwise be an
   * allow-list entry that silently does nothing — and the reason it does
   * nothing (bot not invited, wrong ID, wrong workspace) is exactly the sort of
   * thing worth learning at deploy time rather than the first time someone
   * asks for it.
   */
  async verifyAllowlistVisibility(): Promise<void> {
    for (const channelId of this.channelGuard.allowed) {
      let data: {
        ok?: boolean;
        error?: string;
        channel?: { is_private?: unknown };
      };
      try {
        data = (await this.api("conversations.info", {
          channel: channelId,
        })) as typeof data;
      } catch (error) {
        // Not everything out of api() is an availability failure. The
        // user-token backstop is a configuration fault, and claiming it was an
        // outage would send the operator to the wrong system — the same
        // assume-the-cause mistake this catch exists to avoid making about
        // token validity. Unreachable from here today, since this calls with
        // the bot token and SLACK_BOT_TOKEN is required; the guarantee lives
        // in another file from the claim, which is what makes it worth typing.
        if (error instanceof UserTokenUnavailableError) throw error;
        // Slack never answered, which is a different failure from Slack
        // answering and disagreeing — the same distinction the auth path draws
        // between an IdP outage and a bad token. Both exit non-zero, because
        // starting with unverified channels would defeat the check entirely,
        // but only one of them is fixed by editing configuration. Without this
        // the operator gets "fetch failed" and no idea which system to look at.
        throw new Error(
          `Could not verify allow-listed channel ${channelId} — Slack did not ` +
            `return a usable answer: ` +
            `${error instanceof Error ? error.message : String(error)}. ` +
            `The allow-list has not been judged either way, so startup fails ` +
            `closed rather than serving unverified channels. Usually this is ` +
            `Slack or network availability; the underlying message above is ` +
            `the thing to read, not this sentence.`
        );
      }
      if (!data.ok || !data.channel) {
        // channel_not_found is what Slack returns for a private channel the
        // bot has not joined, which makes it the expected answer for the
        // intuitive deploy order — add the ID, deploy, then invite the bot.
        // That order does not start, and without this it presents as a broken
        // deploy rather than a skipped step. The remedy goes in the message
        // because this is read at deploy time, when nobody is reading a README.
        const remedy =
          data.error === "channel_not_found" || data.error === "not_in_channel"
            ? ` Invite the bot to the channel first, then deploy — this check ` +
              `runs before the listener starts, so an uninvited private ` +
              `channel stops the server rather than degrading it.`
            : "";
        throw new Error(
          `Cannot verify allow-listed channel ${channelId}: Slack returned ` +
            `${data.error ?? "no channel"}. Every channel in SLACK_CHANNEL_IDS ` +
            `and SLACK_PRIVATE_CHANNEL_IDS must be readable by this bot.${remedy}`
        );
      }
      this.channelGuard.assertVisibilityMatches(
        channelId,
        data.channel.is_private
      );
    }
  }

  async getChannelHistory(channelId: string, limit = 10) {
    return this.api("conversations.history", {
      channel: channelId,
      limit,
    });
  }

  async getThreadReplies(channelId: string, threadTs: string) {
    return this.api("conversations.replies", {
      channel: channelId,
      ts: threadTs,
    });
  }

  async setChannelTopic(channelId: string, topic: string) {
    return this.api(
      "conversations.setTopic",
      { channel: channelId, topic },
      "user",
      "POST"
    );
  }

  // ── Users (Bot Token) ───────────────────────────────────────────────

  async getUsers(limit = 100, cursor?: string) {
    const params: Record<string, unknown> = {
      limit: Math.min(limit, 200),
      team_id: this.teamId,
    };
    if (cursor) params.cursor = cursor;
    return this.api("users.list", params);
  }

  async getUserProfile(userId: string) {
    return this.api("users.profile.get", {
      user: userId,
      include_labels: "true",
    });
  }

  // ── Search (User Token) ─────────────────────────────────────────────

  async searchMessages(query: string, count = 20, sort = "score") {
    return this.api(
      "search.messages",
      { query, count: Math.min(count, 100), sort },
      "user"
    );
  }

  async searchFiles(query: string, count = 20, sort = "score") {
    return this.api(
      "search.files",
      { query, count: Math.min(count, 100), sort },
      "user"
    );
  }

  // ── Messaging (User Token) ─────────────────────────────────────────

  async postMessage(channelId: string, text: string) {
    return this.api(
      "chat.postMessage",
      { channel: channelId, text },
      this.writeToken,
      "POST"
    );
  }

  async replyToThread(channelId: string, threadTs: string, text: string) {
    return this.api(
      "chat.postMessage",
      { channel: channelId, thread_ts: threadTs, text },
      this.writeToken,
      "POST"
    );
  }

  async updateMessage(channelId: string, ts: string, text: string) {
    return this.api(
      "chat.update",
      { channel: channelId, ts, text },
      this.writeToken,
      "POST"
    );
  }

  async addReaction(channelId: string, timestamp: string, reaction: string) {
    return this.api(
      "reactions.add",
      { channel: channelId, timestamp, name: reaction },
      "user",
      "POST"
    );
  }

  // ── Pins (User Token) ──────────────────────────────────────────────

  async listPins(channelId: string) {
    return this.api("pins.list", { channel: channelId }, "bot");
  }

  async pinMessage(channelId: string, timestamp: string) {
    return this.api(
      "pins.add",
      { channel: channelId, timestamp },
      "user",
      "POST"
    );
  }

  async unpinMessage(channelId: string, timestamp: string) {
    return this.api(
      "pins.remove",
      { channel: channelId, timestamp },
      "user",
      "POST"
    );
  }

  // ── Bookmarks (Bot Token for read, User Token for write) ───────────

  async listBookmarks(channelId: string) {
    return this.api("bookmarks.list", { channel_id: channelId }, "bot");
  }

  async addBookmark(
    channelId: string,
    title: string,
    link: string,
    emoji?: string
  ) {
    const params: Record<string, unknown> = {
      channel_id: channelId,
      title,
      type: "link",
      link,
    };
    if (emoji) params.emoji = emoji;
    return this.api("bookmarks.add", params, "user", "POST");
  }

  // ── Canvases (User Token) ──────────────────────────────────────────

  async createCanvas(title?: string, markdown?: string, channelId?: string) {
    const params: Record<string, unknown> = {};
    if (title) params.title = title;
    if (markdown) {
      params.document_content = { type: "markdown", markdown };
    }
    if (channelId) params.channel_id = channelId;
    return this.api("canvases.create", params, "user", "POST");
  }

  async editCanvas(
    canvasId: string,
    operation: string,
    markdown?: string,
    sectionId?: string
  ) {
    const change: Record<string, unknown> = { operation };

    if (operation === "rename" && markdown) {
      change.title_content = { type: "markdown", markdown };
    } else if (operation !== "delete" && markdown) {
      change.document_content = { type: "markdown", markdown };
    }

    if (sectionId) change.section_id = sectionId;

    return this.api(
      "canvases.edit",
      { canvas_id: canvasId, changes: [change] },
      "user",
      "POST"
    );
  }

  async lookupCanvasSections(
    canvasId: string,
    sectionTypes?: string[],
    containsText?: string
  ) {
    const criteria: Record<string, unknown> = {};
    if (sectionTypes?.length) criteria.section_types = sectionTypes;
    if (containsText) criteria.contains_text = containsText;

    return this.api(
      "canvases.sections.lookup",
      { canvas_id: canvasId, criteria },
      "user",
      "POST"
    );
  }

  async deleteCanvas(canvasId: string) {
    return this.api(
      "canvases.delete",
      { canvas_id: canvasId },
      "user",
      "POST"
    );
  }
}

