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

import { open } from "node:fs/promises";

import {
  assertFileShareAllowed,
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
        `available on this transport.`,
    );
    this.name = "UserTokenUnavailableError";
  }
}

interface SlackFile {
  id: string;
  name?: string;
  title?: string;
  mimetype?: string;
  filetype?: string;
  size?: number;
  url_private?: string;
  channels?: unknown;
  groups?: unknown;
  ims?: unknown;
  [key: string]: unknown;
}

interface FileInfoResponse {
  ok?: boolean;
  error?: string;
  file?: SlackFile;
}

/** 1 MiB. Enough for logs and source; anything larger is a download. */
const DEFAULT_READ_CAP = 1_048_576;

const TEXT_MIMETYPES = new Set([
  "application/json",
  "application/xml",
  "application/javascript",
  "application/x-javascript",
  "application/x-sh",
  "application/x-yaml",
  "application/yaml",
  "application/toml",
  "application/csv",
  "application/x-ndjson",
  "application/sql",
]);

function isTextFile(file: SlackFile): boolean {
  const mimetype = file.mimetype?.toLowerCase() ?? "";
  if (mimetype.startsWith("text/")) return true;
  if (TEXT_MIMETYPES.has(mimetype)) return true;
  // Slack's own classification. Snippets report mimetype text/plain already;
  // this catches code files Slack typed by extension but served as octet-stream.
  return file.filetype === "text" || file.filetype === "markdown";
}

export class SlackClient {
  private botHeaders: Record<string, string>;
  private userHeaders: Record<string, string> | undefined;
  private teamId: string;
  private channelGuard: ChannelGuard;
  private writeToken: WriteTokenPreference;

  constructor(
    slack: SlackCredentials,
    options: { channelGuard: ChannelGuard; writeToken: WriteTokenPreference },
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
    httpMethod: "GET" | "POST" = "GET",
  ): Promise<unknown> {
    this.guardParams(params);

    const headers = token === "bot" ? this.botHeaders : this.userHeaders;
    if (!headers) {
      // Reached only if a user-token tool is invoked on the HTTP transport.
      // Those tools are withheld from the HTTP tool list, so this is a
      // defence-in-depth backstop, not an expected path.
      throw new UserTokenUnavailableError(method);
    }

    let res: Response;
    if (httpMethod === "GET") {
      const qs = new URLSearchParams();
      for (const [k, v] of Object.entries(params)) {
        if (v !== undefined && v !== null) qs.append(k, String(v));
      }
      res = await fetch(`https://slack.com/api/${method}?${qs}`, {
        headers,
      });
    } else {
      res = await fetch(`https://slack.com/api/${method}`, {
        method: "POST",
        headers,
        body: JSON.stringify(params),
      });
    }

    const data = (await res.json()) as { ok?: boolean; error?: string };

    // Fallback: if a bot token read fails with not_in_channel or
    // channel_not_found, retry with user token when available (e.g. for DMs,
    // private channels, or channels the bot hasn't joined).
    if (
      !data.ok &&
      token === "bot" &&
      this.userHeaders &&
      (data.error === "not_in_channel" || data.error === "channel_not_found")
    ) {
      return this.api(method, params, "user", httpMethod);
    }

    return data;
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
        types: this.userHeaders
          ? "public_channel,private_channel,im,mpim"
          : "public_channel",
        exclude_archived: "true",
        limit: Math.min(limit, 200),
        team_id: this.teamId,
      };
      if (cursor) params.cursor = cursor;
      return this.api(
        "conversations.list",
        params,
        this.userHeaders ? "user" : "bot",
      );
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
          data.channel.is_private,
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
            `the thing to read, not this sentence.`,
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
            `and SLACK_PRIVATE_CHANNEL_IDS must be readable by this bot.${remedy}`,
        );
      }
      this.channelGuard.assertVisibilityMatches(
        channelId,
        data.channel.is_private,
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

  /**
   * Fetches one message. A top-level message is read through
   * `conversations.history` bounded to its own timestamp; a reply has to go
   * through `conversations.replies` on its parent, because history does not
   * return replies. Which of the two applies is decided by the caller —
   * usually from a permalink's `thread_ts` — not guessed here.
   */
  async getMessage(channelId: string, ts: string, threadTs?: string) {
    if (threadTs) {
      const data = (await this.api("conversations.replies", {
        channel: channelId,
        ts: threadTs,
      })) as { ok?: boolean; error?: string; messages?: { ts?: string }[] };
      if (!data.ok) return data;
      const message = data.messages?.find((m) => m.ts === ts);
      return message
        ? { ok: true, message }
        : { ok: false, error: "message_not_found" };
    }
    const data = (await this.api("conversations.history", {
      channel: channelId,
      latest: ts,
      oldest: ts,
      inclusive: "true",
      limit: 1,
    })) as { ok?: boolean; error?: string; messages?: { ts?: string }[] };
    if (!data.ok) return data;
    const message = data.messages?.find((m) => m.ts === ts);
    return message
      ? { ok: true, message }
      : { ok: false, error: "message_not_found" };
  }

  async getPermalink(channelId: string, ts: string) {
    return this.api("chat.getPermalink", {
      channel: channelId,
      message_ts: ts,
    });
  }

  async setChannelTopic(channelId: string, topic: string) {
    return this.api(
      "conversations.setTopic",
      { channel: channelId, topic },
      "user",
      "POST",
    );
  }

  // ── Channel membership ─────────────────────────────────────────────
  //
  // Every call here names a channel, so the allow-list binds all of them
  // through api(). The token is the caller's choice for join and leave —
  // "bot" by default, so the bot can put itself into a public channel without
  // the human being made to join anything — and fixed for the others.

  async joinChannel(channelId: string, as: "bot" | "user" = "bot") {
    return this.api("conversations.join", { channel: channelId }, as, "POST");
  }

  async leaveChannel(channelId: string, as: "bot" | "user" = "bot") {
    return this.api("conversations.leave", { channel: channelId }, as, "POST");
  }

  async listChannelMembers(channelId: string, limit = 100, cursor?: string) {
    const params: Record<string, unknown> = {
      channel: channelId,
      limit: Math.min(limit, 200),
    };
    if (cursor) params.cursor = cursor;
    return this.api("conversations.members", params);
  }

  async inviteToChannel(channelId: string, userIds: string[]) {
    return this.api(
      "conversations.invite",
      { channel: channelId, users: userIds.join(",") },
      "user",
      "POST",
    );
  }

  // ── Custom emoji (Bot Token) ───────────────────────────────────────

  /**
   * Lists the workspace's custom emoji. Filtering is client-side because
   * `emoji.list` has no query parameter; aliases are the entries whose value
   * is `alias:<name>` rather than a URL.
   */
  async listEmoji(query?: string, includeAliases = true) {
    const data = (await this.api("emoji.list", {})) as {
      ok?: boolean;
      emoji?: Record<string, string>;
    };
    if (!data.ok || !data.emoji) return data;
    const needle = query?.toLowerCase();
    const emoji: Record<string, string> = {};
    for (const [name, value] of Object.entries(data.emoji)) {
      if (!includeAliases && value.startsWith("alias:")) continue;
      if (needle && !name.toLowerCase().includes(needle)) continue;
      emoji[name] = value;
    }
    return { ...data, emoji };
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
      "user",
    );
  }

  async searchFiles(query: string, count = 20, sort = "score") {
    return this.api(
      "search.files",
      { query, count: Math.min(count, 100), sort },
      "user",
    );
  }

  // ── Messaging (User Token) ─────────────────────────────────────────

  async postMessage(channelId: string, text: string) {
    return this.api(
      "chat.postMessage",
      { channel: channelId, text },
      this.writeToken,
      "POST",
    );
  }

  async replyToThread(channelId: string, threadTs: string, text: string) {
    return this.api(
      "chat.postMessage",
      { channel: channelId, thread_ts: threadTs, text },
      this.writeToken,
      "POST",
    );
  }

  async updateMessage(channelId: string, ts: string, text: string) {
    return this.api(
      "chat.update",
      { channel: channelId, ts, text },
      this.writeToken,
      "POST",
    );
  }

  async addReaction(channelId: string, timestamp: string, reaction: string) {
    return this.api(
      "reactions.add",
      { channel: channelId, timestamp, name: reaction },
      "user",
      "POST",
    );
  }

  // ── Pins (User Token) ──────────────────────────────────────────────

  async listPins(channelId: string) {
    return this.api(
      "pins.list",
      { channel: channelId },
      this.userHeaders ? "user" : "bot",
    );
  }

  async pinMessage(channelId: string, timestamp: string) {
    return this.api(
      "pins.add",
      { channel: channelId, timestamp },
      "user",
      "POST",
    );
  }

  async unpinMessage(channelId: string, timestamp: string) {
    return this.api(
      "pins.remove",
      { channel: channelId, timestamp },
      "user",
      "POST",
    );
  }

  // ── Bookmarks (Bot Token for read, User Token for write) ───────────

  async listBookmarks(channelId: string) {
    return this.api(
      "bookmarks.list",
      { channel_id: channelId },
      this.userHeaders ? "user" : "bot",
    );
  }

  async addBookmark(
    channelId: string,
    title: string,
    link: string,
    emoji?: string,
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
    sectionId?: string,
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
      "POST",
    );
  }

  async lookupCanvasSections(
    canvasId: string,
    sectionTypes?: string[],
    containsText?: string,
  ) {
    const criteria: Record<string, unknown> = {};
    if (sectionTypes?.length) criteria.section_types = sectionTypes;
    if (containsText) criteria.contains_text = containsText;

    return this.api(
      "canvases.sections.lookup",
      { canvas_id: canvasId, criteria },
      "user",
      "POST",
    );
  }

  async deleteCanvas(canvasId: string) {
    return this.api("canvases.delete", { canvas_id: canvasId }, "user", "POST");
  }
  // ── Files ──────────────────────────────────────────────────────────
  //
  // Files are the one object a caller can name without naming a channel, so
  // the parameter guard in api() has nothing to check on `files.info`. Every
  // method here therefore goes through fetchFileInfo(), which applies the
  // allow-list to the *answer* — the conversations the file is shared into —
  // and refuses before any bytes move. The private URL Slack returns is
  // stripped from what callers see; it is a bearer-authenticated download
  // link and has no business in a tool result.

  private async fetchFileInfo(fileId: string): Promise<{
    file: SlackFile;
    token: "bot" | "user";
  }> {
    let token: "bot" | "user" = "bot";
    let data = (await this.api("files.info", {
      file: fileId,
    })) as FileInfoResponse;
    // The bot cannot see files in conversations it is not in. Same fallback
    // api() applies to not_in_channel, for the file-shaped error.
    if (!data.ok && data.error === "file_not_found" && this.userHeaders) {
      token = "user";
      data = (await this.api(
        "files.info",
        { file: fileId },
        "user",
      )) as FileInfoResponse;
    }
    if (!data.ok || !data.file) {
      throw new Error(`files.info failed: ${data.error ?? "no file returned"}`);
    }
    assertFileShareAllowed(this.channelGuard, data.file);
    return { file: data.file, token };
  }

  private async fetchFileBytes(
    file: SlackFile,
    token: "bot" | "user",
  ): Promise<Uint8Array> {
    if (!file.url_private) {
      throw new Error(`File ${file.id} has no downloadable content.`);
    }
    const headers = token === "bot" ? this.botHeaders : this.userHeaders;
    if (!headers) throw new UserTokenUnavailableError("files download");
    const res = await fetch(file.url_private, {
      headers: { Authorization: headers.Authorization! },
    });
    if (!res.ok) {
      throw new Error(`Downloading file ${file.id} failed: HTTP ${res.status}`);
    }
    return new Uint8Array(await res.arrayBuffer());
  }

  /** What a caller gets to see of a file: everything but the private URLs. */
  private static publicFile(file: SlackFile): Record<string, unknown> {
    const shown: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(file)) {
      if (key.startsWith("url_private") || key === "permalink_public") continue;
      shown[key] = value;
    }
    return shown;
  }

  async getFileInfo(fileId: string) {
    const { file } = await this.fetchFileInfo(fileId);
    return { ok: true, file: SlackClient.publicFile(file) };
  }

  /**
   * Returns a text file's content. Binary files are refused rather than
   * returned as mojibake; `slack_download_file` exists for those. The size
   * check runs on `files.info`'s answer, before the download.
   */
  async readFile(fileId: string, maxBytes = DEFAULT_READ_CAP) {
    const { file, token } = await this.fetchFileInfo(fileId);
    if (!isTextFile(file)) {
      throw new Error(
        `File ${file.id} (${file.mimetype ?? "unknown type"}) is not a text ` +
          `file. Use slack_download_file to save it locally instead.`,
      );
    }
    if (typeof file.size === "number" && file.size > maxBytes) {
      throw new Error(
        `File ${file.id} is ${file.size} bytes, larger than the ${maxBytes} ` +
          `byte cap. Raise max_bytes or use slack_download_file.`,
      );
    }
    const bytes = await this.fetchFileBytes(file, token);
    return {
      ok: true,
      id: file.id,
      name: file.name,
      title: file.title,
      mimetype: file.mimetype,
      size: bytes.byteLength,
      content: new TextDecoder("utf-8").decode(bytes),
    };
  }

  /**
   * Slack's three-step external upload: reserve a URL, send the bytes, then
   * complete the upload naming the channel it is shared into. The channel is
   * checked first, explicitly, because the first two steps name no channel
   * and would otherwise run before the guard had anything to see.
   */
  async uploadFile(input: {
    channelId: string;
    filename: string;
    content?: string;
    contentBase64?: string;
    title?: string;
    initialComment?: string;
    threadTs?: string;
  }) {
    this.guardParams({ channel_id: input.channelId });
    if ((input.content === undefined) === (input.contentBase64 === undefined)) {
      throw new Error("Provide exactly one of content and content_base64.");
    }
    const bytes =
      input.content !== undefined
        ? new TextEncoder().encode(input.content)
        : new Uint8Array(Buffer.from(input.contentBase64!, "base64"));

    const reserve = (await this.api(
      "files.getUploadURLExternal",
      { filename: input.filename, length: bytes.byteLength },
      this.writeToken,
    )) as {
      ok?: boolean;
      error?: string;
      upload_url?: string;
      file_id?: string;
    };
    if (!reserve.ok || !reserve.upload_url || !reserve.file_id) {
      throw new Error(
        `files.getUploadURLExternal failed: ${reserve.error ?? "no upload URL"}`,
      );
    }

    const put = await fetch(reserve.upload_url, {
      method: "POST",
      headers: { "Content-Type": "application/octet-stream" },
      body: bytes,
    });
    if (!put.ok) {
      throw new Error(`Uploading file bytes failed: HTTP ${put.status}`);
    }

    const fileEntry: Record<string, unknown> = { id: reserve.file_id };
    if (input.title) fileEntry.title = input.title;
    const params: Record<string, unknown> = {
      files: [fileEntry],
      channel_id: input.channelId,
    };
    if (input.initialComment) params.initial_comment = input.initialComment;
    if (input.threadTs) params.thread_ts = input.threadTs;
    return this.api(
      "files.completeUploadExternal",
      params,
      this.writeToken,
      "POST",
    );
  }

  /**
   * Saves a file to the local disk. Stdio-only by tool visibility: on the
   * HTTP transport "local disk" is the pod's, which no caller should be
   * writing to. Refuses to overwrite — `wx` fails if the path exists.
   */
  async downloadFile(fileId: string, outputPath: string) {
    const { file, token } = await this.fetchFileInfo(fileId);
    const bytes = await this.fetchFileBytes(file, token);
    let handle;
    try {
      handle = await open(outputPath, "wx");
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "EEXIST") {
        throw new Error(
          `${outputPath} already exists; refusing to overwrite it.`,
        );
      }
      throw error;
    }
    try {
      await handle.writeFile(bytes);
    } finally {
      await handle.close();
    }
    return {
      ok: true,
      path: outputPath,
      bytes: bytes.byteLength,
      name: file.name,
    };
  }

  // ── User groups ────────────────────────────────────────────────────
  //
  // Workspace-scoped, like users.list: nothing here names a channel, so the
  // allow-list has nothing to bind and tool visibility carries the control
  // instead. The one channel-shaped input — a group's default channels — is
  // spelled `channels` by Slack, which the parameter guard does not read, so
  // it is checked here by hand before the call.

  async listUserGroups(includeDisabled = false) {
    return this.api("usergroups.list", {
      include_disabled: includeDisabled ? "true" : "false",
      team_id: this.teamId,
    });
  }

  async listUserGroupMembers(usergroupId: string) {
    return this.api("usergroups.users.list", {
      usergroup: usergroupId,
      team_id: this.teamId,
    });
  }

  async createUserGroup(input: {
    name: string;
    handle: string;
    description?: string;
    channelIds?: string[];
  }) {
    for (const channelId of input.channelIds ?? []) {
      this.guardParams({ channel: channelId });
    }
    const params: Record<string, unknown> = {
      name: input.name,
      handle: input.handle,
    };
    if (input.description) params.description = input.description;
    if (input.channelIds?.length) params.channels = input.channelIds.join(",");
    params.team_id = this.teamId;
    return this.api("usergroups.create", params, "user", "POST");
  }

  async updateUserGroup(
    usergroupId: string,
    fields: { name?: string; handle?: string; description?: string },
  ) {
    const params: Record<string, unknown> = { usergroup: usergroupId };
    if (fields.name) params.name = fields.name;
    if (fields.handle) params.handle = fields.handle;
    if (fields.description !== undefined)
      params.description = fields.description;
    params.team_id = this.teamId;
    return this.api("usergroups.update", params, "user", "POST");
  }

  /** Replaces the full member list; Slack has no add/remove primitive. */
  async setUserGroupMembers(usergroupId: string, userIds: string[]) {
    return this.api(
      "usergroups.users.update",
      {
        usergroup: usergroupId,
        users: userIds.join(","),
        team_id: this.teamId,
      },
      "user",
      "POST",
    );
  }

  async setUserGroupEnabled(usergroupId: string, enabled: boolean) {
    return this.api(
      enabled ? "usergroups.enable" : "usergroups.disable",
      { usergroup: usergroupId, team_id: this.teamId },
      "user",
      "POST",
    );
  }
}
