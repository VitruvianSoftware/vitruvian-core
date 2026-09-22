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
// Tool dispatch
// ---------------------------------------------------------------------------
//
// One handler per advertised tool, keyed by name. This replaces a switch in
// index.ts that could only be exercised by starting a server, and it is typed
// against the tool list so a tool without a handler is a compile error here
// and a test failure in dispatch.test.ts — rather than a `default:` branch
// that fires in production.
//
// Handlers do two things and nothing else: read arguments into the shape the
// client wants, and resolve anything that names a channel indirectly (a
// permalink) into a channel ID *before* calling the client. The second point
// is the security-relevant one — the allow-list is enforced in the client on
// `channel`/`channel_id` parameters, so a handler that forwarded a URL would
// hand the guard something it cannot inspect.

import type { SlackClient } from "./slackClient.js";
import { parseFileReference, parsePermalink } from "./permalink.js";
import type { tools } from "./tools.js";

export type ToolName = (typeof tools)[number]["name"];
export type ToolArgs = Record<string, unknown>;
export type ToolHandler = (
  client: SlackClient,
  args: ToolArgs,
) => Promise<unknown>;

// ── Argument readers ───────────────────────────────────────────────────
//
// The tool schemas are advisory: clients are not obliged to validate against
// them, and a missing required string used to reach Slack as the literal
// string "undefined". These fail locally, naming the argument.

function str(args: ToolArgs, name: string): string {
  const value = args[name];
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(
      `Argument ${name} is required and must be a non-empty string.`,
    );
  }
  return value;
}

function optStr(args: ToolArgs, name: string): string | undefined {
  const value = args[name];
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string") {
    throw new Error(`Argument ${name} must be a string when present.`);
  }
  return value;
}

function optNum(args: ToolArgs, name: string): number | undefined {
  const value = args[name];
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new Error(`Argument ${name} must be a number when present.`);
  }
  return value;
}

function optBool(args: ToolArgs, name: string): boolean | undefined {
  const value = args[name];
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "boolean") {
    throw new Error(`Argument ${name} must be a boolean when present.`);
  }
  return value;
}

function strArray(args: ToolArgs, name: string): string[] {
  const value = args[name];
  if (
    !Array.isArray(value) ||
    value.length === 0 ||
    !value.every((v) => typeof v === "string" && v.length > 0)
  ) {
    throw new Error(
      `Argument ${name} is required and must be a non-empty array of strings.`,
    );
  }
  return value as string[];
}

function optStrArray(args: ToolArgs, name: string): string[] | undefined {
  const value = args[name];
  if (value === undefined || value === null) return undefined;
  if (!Array.isArray(value) || !value.every((v) => typeof v === "string")) {
    throw new Error(
      `Argument ${name} must be an array of strings when present.`,
    );
  }
  return value as string[];
}

function tokenChoice(args: ToolArgs, name: string): "bot" | "user" {
  const value = optStr(args, name) ?? "bot";
  if (value !== "bot" && value !== "user") {
    throw new Error(`Argument ${name} must be "bot" or "user".`);
  }
  return value;
}

/**
 * A message named either by permalink or by channel + timestamp.
 *
 * The permalink is parsed here, not in the client, so the channel it names
 * is a plain ID by the time the guard runs.
 */
function messageRef(args: ToolArgs): {
  channelId: string;
  ts: string;
  threadTs?: string;
} {
  const permalink = optStr(args, "permalink");
  if (permalink) return parsePermalink(permalink);
  const channelId = optStr(args, "channel_id");
  const ts = optStr(args, "timestamp");
  if (!channelId || !ts) {
    throw new Error(
      "Provide either permalink, or both channel_id and timestamp.",
    );
  }
  const threadTs = optStr(args, "thread_ts");
  return threadTs && threadTs !== ts
    ? { channelId, ts, threadTs }
    : { channelId, ts };
}

/** A file named either by ID or by Slack file URL. */
function fileId(args: ToolArgs): string {
  return parseFileReference(str(args, "file"));
}

// ── Handlers ───────────────────────────────────────────────────────────

export const handlers: Readonly<Record<ToolName, ToolHandler>> = {
  // Channels
  slack_list_channels: (c, a) =>
    c.listChannels(optNum(a, "limit"), optStr(a, "cursor")),
  slack_get_channel_info: (c, a) => c.getChannelInfo(str(a, "channel_id")),
  slack_get_channel_history: (c, a) =>
    c.getChannelHistory(str(a, "channel_id"), optNum(a, "limit")),
  slack_get_thread_replies: (c, a) =>
    c.getThreadReplies(str(a, "channel_id"), str(a, "thread_ts")),
  slack_set_channel_topic: (c, a) =>
    c.setChannelTopic(str(a, "channel_id"), str(a, "topic")),
  slack_get_message: (c, a) => {
    const ref = messageRef(a);
    return c.getMessage(ref.channelId, ref.ts, ref.threadTs);
  },
  slack_get_permalink: (c, a) =>
    c.getPermalink(str(a, "channel_id"), str(a, "timestamp")),

  // Channel membership
  slack_join_channel: (c, a) =>
    c.joinChannel(str(a, "channel_id"), tokenChoice(a, "as")),
  slack_leave_channel: (c, a) =>
    c.leaveChannel(str(a, "channel_id"), tokenChoice(a, "as")),
  slack_list_channel_members: (c, a) =>
    c.listChannelMembers(
      str(a, "channel_id"),
      optNum(a, "limit"),
      optStr(a, "cursor"),
    ),
  slack_invite_to_channel: (c, a) =>
    c.inviteToChannel(str(a, "channel_id"), strArray(a, "user_ids")),

  // Users
  slack_get_users: (c, a) =>
    c.getUsers(optNum(a, "limit"), optStr(a, "cursor")),
  slack_get_user_profile: (c, a) => c.getUserProfile(str(a, "user_id")),

  // Search
  slack_search_messages: (c, a) =>
    c.searchMessages(str(a, "query"), optNum(a, "count"), optStr(a, "sort")),
  slack_search_files: (c, a) =>
    c.searchFiles(str(a, "query"), optNum(a, "count"), optStr(a, "sort")),

  // Messaging
  slack_post_message: (c, a) =>
    c.postMessage(str(a, "channel_id"), str(a, "text")),
  slack_reply_to_thread: (c, a) =>
    c.replyToThread(str(a, "channel_id"), str(a, "thread_ts"), str(a, "text")),
  slack_update_message: (c, a) =>
    c.updateMessage(str(a, "channel_id"), str(a, "timestamp"), str(a, "text")),
  slack_add_reaction: (c, a) =>
    c.addReaction(
      str(a, "channel_id"),
      str(a, "timestamp"),
      str(a, "reaction"),
    ),

  // Pins
  slack_list_pins: (c, a) => c.listPins(str(a, "channel_id")),
  slack_pin_message: (c, a) =>
    c.pinMessage(str(a, "channel_id"), str(a, "timestamp")),
  slack_unpin_message: (c, a) =>
    c.unpinMessage(str(a, "channel_id"), str(a, "timestamp")),

  // Bookmarks
  slack_list_bookmarks: (c, a) => c.listBookmarks(str(a, "channel_id")),
  slack_add_bookmark: (c, a) =>
    c.addBookmark(
      str(a, "channel_id"),
      str(a, "title"),
      str(a, "link"),
      optStr(a, "emoji"),
    ),

  // Canvases
  slack_create_canvas: (c, a) =>
    c.createCanvas(
      optStr(a, "title"),
      optStr(a, "markdown"),
      optStr(a, "channel_id"),
    ),
  slack_edit_canvas: (c, a) =>
    c.editCanvas(
      str(a, "canvas_id"),
      str(a, "operation"),
      optStr(a, "markdown"),
      optStr(a, "section_id"),
    ),
  slack_lookup_canvas_sections: (c, a) =>
    c.lookupCanvasSections(
      str(a, "canvas_id"),
      optStrArray(a, "section_types"),
      optStr(a, "contains_text"),
    ),
  slack_delete_canvas: (c, a) => c.deleteCanvas(str(a, "canvas_id")),

  // Emoji
  slack_list_emoji: (c, a) =>
    c.listEmoji(optStr(a, "query"), optBool(a, "include_aliases")),

  // Files
  slack_get_file_info: (c, a) => c.getFileInfo(fileId(a)),
  slack_read_file: (c, a) => c.readFile(fileId(a), optNum(a, "max_bytes")),
  slack_upload_file: (c, a) =>
    c.uploadFile({
      channelId: str(a, "channel_id"),
      filename: str(a, "filename"),
      content: optStr(a, "content"),
      contentBase64: optStr(a, "content_base64"),
      title: optStr(a, "title"),
      initialComment: optStr(a, "initial_comment"),
      threadTs: optStr(a, "thread_ts"),
    }),
  slack_download_file: (c, a) =>
    c.downloadFile(fileId(a), str(a, "output_path")),

  // User groups
  slack_list_user_groups: (c, a) =>
    c.listUserGroups(optBool(a, "include_disabled")),
  slack_list_user_group_members: (c, a) =>
    c.listUserGroupMembers(str(a, "usergroup_id")),
  slack_create_user_group: (c, a) =>
    c.createUserGroup({
      name: str(a, "name"),
      handle: str(a, "handle"),
      description: optStr(a, "description"),
      channelIds: optStrArray(a, "channel_ids"),
    }),
  slack_update_user_group: (c, a) =>
    c.updateUserGroup(str(a, "usergroup_id"), {
      name: optStr(a, "name"),
      handle: optStr(a, "handle"),
      description: optStr(a, "description"),
    }),
  slack_set_user_group_members: (c, a) =>
    c.setUserGroupMembers(str(a, "usergroup_id"), strArray(a, "user_ids")),
  slack_set_user_group_enabled: (c, a) => {
    const enabled = optBool(a, "enabled");
    if (enabled === undefined) throw new Error("Argument enabled is required.");
    return c.setUserGroupEnabled(str(a, "usergroup_id"), enabled);
  },
};

/** Runs the handler for `name`, or throws if no such tool exists. */
export async function dispatch(
  client: SlackClient,
  name: string,
  args: ToolArgs,
): Promise<unknown> {
  const handler = Object.prototype.hasOwnProperty.call(handlers, name)
    ? handlers[name as ToolName]
    : undefined;
  if (!handler) throw new Error(`Unknown tool: ${name}`);
  return handler(client, args);
}
