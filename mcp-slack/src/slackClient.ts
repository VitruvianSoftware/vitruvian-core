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
      throw new Error(
        `Slack method ${method} requires the user token, which is not ` +
          `available on this transport.`
      );
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
      })) as { ok: boolean; channel?: { is_archived: boolean } };
      if (data.ok && data.channel && !data.channel.is_archived) {
        channels.push(data.channel);
      }
    }
    return { ok: true, channels, response_metadata: { next_cursor: "" } };
  }

  async getChannelInfo(channelId: string) {
    return this.api("conversations.info", {
      channel: channelId,
      include_num_members: "true",
    });
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

