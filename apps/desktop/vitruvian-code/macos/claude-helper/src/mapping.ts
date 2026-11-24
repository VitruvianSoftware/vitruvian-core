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

import { basename } from "node:path";

import {
  RequestError,
  type AvailableCommand,
  type PlanEntry,
  type PlanEntryStatus,
  type SessionNotification,
  type SessionUpdate,
  type StopReason,
  type ToolCallContent,
  type ToolCallLocation,
  type ToolKind,
} from "@agentclientprotocol/sdk";
import type {
  ModelUsage,
  SDKAssistantMessage,
  SDKMessage,
  SDKPartialAssistantMessage,
  SDKResultMessage,
  SDKSystemMessage,
  SDKUserMessage,
} from "@anthropic-ai/claude-agent-sdk";

import {
  mergeAvailableCommands,
  type AvailableSlashCommand,
} from "./skills.js";

const ROOT_STREAM_SCOPE = "__root__";
const DEFAULT_CONTEXT_WINDOW_TOKENS = 200_000;
const AUTH_ERROR_PATTERN =
  /authentication_failed|auth_required|not logged in|invalid api key|claude auth login|unauthorized|oauth token.*expired/i;

const TOOL_KIND_BY_NAME: Readonly<Record<string, ToolKind>> = {
  Read: "read",
  NotebookRead: "read",
  Edit: "edit",
  MultiEdit: "edit",
  Write: "edit",
  NotebookEdit: "edit",
  Bash: "execute",
  BashOutput: "execute",
  KillShell: "execute",
  Grep: "search",
  Glob: "search",
  LS: "search",
  WebFetch: "fetch",
  WebSearch: "fetch",
  ExitPlanMode: "switch_mode",
  Task: "other",
  Agent: "other",
};

/** Per-turn state for deduplicating streamed text/thinking and tracking turn outcomes. */
export interface MappingState {
  readonly currentStreamMessageIdByScope: Map<string, string>;
  readonly streamedTextByMessageId: Set<string>;
  readonly streamedThinkingByMessageId: Set<string>;
  readonly unkeyedStreamedTextScopes: Set<string>;
  readonly unkeyedStreamedThinkingScopes: Set<string>;
  readonly emittedToolCallIds: Set<string>;
  authErrorDetected: boolean;
  lastAssistantStopReason: string | null;
  activeCompactionId: string | null;
  compactionSeq: number;
  /**
   * The newest root model call this turn: what it sent and got back. Claude
   * Code resends the whole conversation on every call, so the latest call
   * alone is the context size; the `result` message's `usage` is the sum over
   * every call of the turn and would count the history once per call.
   */
  lastCallUsage: CallUsage | null;
}

/** One model call's token counts, as the SDK reports them on an assistant message. */
interface CallUsage {
  readonly inputTokens: number;
  readonly outputTokens: number;
  readonly cacheReadTokens: number;
  readonly cacheWriteTokens: number;
}

export interface MapSdkMessageOptions {
  readonly diskCommands?: readonly AvailableSlashCommand[];
}

export type ClassifiedSdkResult =
  | { readonly kind: "stop"; readonly stopReason: StopReason }
  | { readonly kind: "error"; readonly error: RequestError };

export function createMappingState(): MappingState {
  return {
    currentStreamMessageIdByScope: new Map<string, string>(),
    streamedTextByMessageId: new Set<string>(),
    streamedThinkingByMessageId: new Set<string>(),
    unkeyedStreamedTextScopes: new Set<string>(),
    unkeyedStreamedThinkingScopes: new Set<string>(),
    emittedToolCallIds: new Set<string>(),
    authErrorDetected: false,
    lastAssistantStopReason: null,
    activeCompactionId: null,
    compactionSeq: 0,
    lastCallUsage: null,
  };
}

export function resetTurnMappingState(state: MappingState): void {
  state.currentStreamMessageIdByScope.clear();
  state.streamedTextByMessageId.clear();
  state.streamedThinkingByMessageId.clear();
  state.unkeyedStreamedTextScopes.clear();
  state.unkeyedStreamedThinkingScopes.clear();
  state.emittedToolCallIds.clear();
  state.authErrorDetected = false;
  state.lastAssistantStopReason = null;
  state.activeCompactionId = null;
  state.lastCallUsage = null;
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function nonEmptyString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0
    ? value
    : undefined;
}

function parentMetaForToolCallId(
  parentToolCallId: string | null,
): { readonly vitruvian: { readonly parentToolCallId: string } } | undefined {
  return parentToolCallId ? { vitruvian: { parentToolCallId } } : undefined;
}

function withNotificationParentMeta(
  sessionId: string,
  update: SessionUpdate,
  parentToolCallId: string | null,
): SessionNotification {
  const meta = parentMetaForToolCallId(parentToolCallId);
  return meta ? { sessionId, update, _meta: meta } : { sessionId, update };
}

export function mapToolKind(toolName: string): ToolKind {
  return TOOL_KIND_BY_NAME[toolName] ?? "other";
}

export function isSubagentTool(toolName: string): boolean {
  return toolName === "Task" || toolName === "Agent";
}

function extractInputPath(rawInput: unknown): string | undefined {
  if (!isPlainRecord(rawInput)) {
    return undefined;
  }
  return (
    nonEmptyString(rawInput.file_path) ??
    nonEmptyString(rawInput.notebook_path) ??
    nonEmptyString(rawInput.path)
  );
}

export function formatToolCallTitle(
  toolName: string,
  rawInput: unknown,
): string {
  const input = isPlainRecord(rawInput) ? rawInput : undefined;
  if (isSubagentTool(toolName)) {
    const desc = nonEmptyString(input?.description);
    return desc ? desc.trim() : toolName;
  }
  if (toolName === "Bash" && input) {
    const command = nonEmptyString(input.command);
    if (command) {
      return `Run Bash: ${command.trim().slice(0, 80)}`;
    }
  }
  const filePath = extractInputPath(rawInput);
  if (filePath) {
    const base = basename(filePath);
    return base.length > 0 ? `${toolName} ${base}` : `${toolName} ${filePath}`;
  }
  return toolName.trim().length > 0 ? toolName : "Tool";
}

export function extractToolCallLocations(
  rawInput: unknown,
): ToolCallLocation[] | undefined {
  const path = extractInputPath(rawInput);
  if (!path) {
    return undefined;
  }
  const input = isPlainRecord(rawInput) ? rawInput : undefined;
  const candidateLine = input?.line ?? input?.offset;
  const line =
    typeof candidateLine === "number" &&
    Number.isInteger(candidateLine) &&
    candidateLine >= 1
      ? candidateLine
      : undefined;
  return [line !== undefined ? { path, line } : { path }];
}

export function extractToolCallContent(
  toolName: string,
  rawInput: unknown,
): ToolCallContent[] | undefined {
  if (!isPlainRecord(rawInput)) {
    return undefined;
  }
  const path = extractInputPath(rawInput);
  if (!path) {
    return undefined;
  }
  if (toolName === "Edit" && typeof rawInput.new_string === "string") {
    return [
      {
        type: "diff",
        path,
        oldText:
          typeof rawInput.old_string === "string" ? rawInput.old_string : null,
        newText: rawInput.new_string,
      },
    ];
  }
  if (toolName === "Write" && typeof rawInput.content === "string") {
    return [
      {
        type: "diff",
        path,
        oldText: null,
        newText: rawInput.content,
      },
    ];
  }
  if (toolName === "MultiEdit" && Array.isArray(rawInput.edits)) {
    const diffs: ToolCallContent[] = [];
    for (const entry of rawInput.edits) {
      if (!isPlainRecord(entry) || typeof entry.new_string !== "string") {
        continue;
      }
      diffs.push({
        type: "diff",
        path,
        oldText: typeof entry.old_string === "string" ? entry.old_string : null,
        newText: entry.new_string,
      });
    }
    return diffs.length > 0 ? diffs : undefined;
  }
  return undefined;
}

/**
 * Converts TodoWrite `{ todos }` input into ACP plan entries.
 * Mirrors T3 `claudeTodoSteps` (`ClaudeAdapterV2.ts:4739-4768`), mapping
 * `"running"` -> `"in_progress"` for ACP `PlanEntryStatus`.
 */
export function extractTodoPlanEntries(rawInput: unknown): PlanEntry[] {
  if (!isPlainRecord(rawInput) || !Array.isArray(rawInput.todos)) {
    return [];
  }
  const entries: PlanEntry[] = [];
  for (const todo of rawInput.todos) {
    if (!isPlainRecord(todo)) {
      continue;
    }
    const content = typeof todo.content === "string" ? todo.content.trim() : "";
    if (content.length === 0) {
      continue;
    }
    const status: PlanEntryStatus =
      todo.status === "completed"
        ? "completed"
        : todo.status === "in_progress"
          ? "in_progress"
          : "pending";
    entries.push({
      content,
      priority: "medium",
      status,
    });
  }
  return entries;
}

function recordStreamedText(state: MappingState, scope: string): void {
  const messageId = state.currentStreamMessageIdByScope.get(scope);
  if (messageId) {
    state.streamedTextByMessageId.add(messageId);
  } else {
    state.unkeyedStreamedTextScopes.add(scope);
  }
}

function recordStreamedThinking(state: MappingState, scope: string): void {
  const messageId = state.currentStreamMessageIdByScope.get(scope);
  if (messageId) {
    state.streamedThinkingByMessageId.add(messageId);
  } else {
    state.unkeyedStreamedThinkingScopes.add(scope);
  }
}

/** Maps incremental `stream_event` deltas (T3 `ClaudeAdapterV2.ts:9305-9360`). */
function mapStreamEventMessage(
  sessionId: string,
  message: SDKPartialAssistantMessage,
  state: MappingState,
): SessionNotification[] {
  const parentToolCallId = nonEmptyString(message.parent_tool_use_id) ?? null;
  const scope = parentToolCallId ?? ROOT_STREAM_SCOPE;
  const event = message.event;
  const out: SessionNotification[] = [];

  if (event.type === "message_start") {
    const streamMsgId = nonEmptyString(event.message?.id);
    if (streamMsgId) {
      state.currentStreamMessageIdByScope.set(scope, streamMsgId);
    }
    state.unkeyedStreamedTextScopes.delete(scope);
    state.unkeyedStreamedThinkingScopes.delete(scope);
    return out;
  }

  if (event.type === "message_stop") {
    state.currentStreamMessageIdByScope.delete(scope);
    return out;
  }

  if (event.type === "content_block_start") {
    const block = event.content_block;
    if (block.type === "text" && block.text.length > 0) {
      recordStreamedText(state, scope);
      out.push(
        withNotificationParentMeta(
          sessionId,
          {
            sessionUpdate: "agent_message_chunk",
            content: { type: "text", text: block.text },
          },
          parentToolCallId,
        ),
      );
    } else if (block.type === "thinking" && block.thinking.length > 0) {
      recordStreamedThinking(state, scope);
      out.push(
        withNotificationParentMeta(
          sessionId,
          {
            sessionUpdate: "agent_thought_chunk",
            content: { type: "text", text: block.thinking },
          },
          parentToolCallId,
        ),
      );
    }
    return out;
  }

  if (event.type === "content_block_delta") {
    const delta = event.delta;
    if (delta.type === "text_delta" && delta.text.length > 0) {
      recordStreamedText(state, scope);
      out.push(
        withNotificationParentMeta(
          sessionId,
          {
            sessionUpdate: "agent_message_chunk",
            content: { type: "text", text: delta.text },
          },
          parentToolCallId,
        ),
      );
    } else if (delta.type === "thinking_delta" && delta.thinking.length > 0) {
      recordStreamedThinking(state, scope);
      out.push(
        withNotificationParentMeta(
          sessionId,
          {
            sessionUpdate: "agent_thought_chunk",
            content: { type: "text", text: delta.thinking },
          },
          parentToolCallId,
        ),
      );
    }
  }

  return out;
}

/**
 * Maps snapshot `assistant` messages (T3 `ClaudeAdapterV2.ts:3646-3653, 9362-9445, 10013-10045`).
 * Avoids re-sending text/thinking blocks already streamed via `stream_event`.
 */
function mapAssistantMessage(
  sessionId: string,
  message: SDKAssistantMessage,
  state: MappingState,
): SessionNotification[] {
  const parentToolCallId = nonEmptyString(message.parent_tool_use_id) ?? null;
  const scope = parentToolCallId ?? ROOT_STREAM_SCOPE;
  const out: SessionNotification[] = [];

  if (parentToolCallId === null) {
    // T3 `ClaudeAdapterV2.ts:9439-9444`: record auth error flagged on synthetic assistant message.
    if (message.error === "authentication_failed") {
      state.authErrorDetected = true;
    }
    const stopReason = nonEmptyString(message.message?.stop_reason);
    if (stopReason) {
      state.lastAssistantStopReason = stopReason;
    }
    // Only the main agent's calls size the context; a subagent has its own window.
    const callUsage = readCallUsage(message.message);
    if (callUsage) {
      state.lastCallUsage = callUsage;
    }
  }

  const msgId = nonEmptyString(message.message?.id);
  const hadKeyedText =
    msgId !== undefined && state.streamedTextByMessageId.has(msgId);
  const hadUnkeyedText = state.unkeyedStreamedTextScopes.has(scope);
  const alreadyStreamedText = hadKeyedText || hadUnkeyedText;
  if (hadUnkeyedText) {
    state.unkeyedStreamedTextScopes.delete(scope);
    if (msgId) {
      state.streamedTextByMessageId.add(msgId);
    }
  }

  const hadKeyedThinking =
    msgId !== undefined && state.streamedThinkingByMessageId.has(msgId);
  const hadUnkeyedThinking = state.unkeyedStreamedThinkingScopes.has(scope);
  const alreadyStreamedThinking = hadKeyedThinking || hadUnkeyedThinking;
  if (hadUnkeyedThinking) {
    state.unkeyedStreamedThinkingScopes.delete(scope);
    if (msgId) {
      state.streamedThinkingByMessageId.add(msgId);
    }
  }

  const content = Array.isArray(message.message?.content)
    ? message.message.content
    : [];

  for (const block of content) {
    if (!isPlainRecord(block) || typeof block.type !== "string") {
      continue;
    }

    if (
      block.type === "text" &&
      typeof block.text === "string" &&
      block.text.length > 0 &&
      !alreadyStreamedText
    ) {
      if (msgId) {
        state.streamedTextByMessageId.add(msgId);
      }
      out.push(
        withNotificationParentMeta(
          sessionId,
          {
            sessionUpdate: "agent_message_chunk",
            content: { type: "text", text: block.text },
          },
          parentToolCallId,
        ),
      );
      continue;
    }

    if (
      block.type === "thinking" &&
      typeof block.thinking === "string" &&
      block.thinking.length > 0 &&
      !alreadyStreamedThinking
    ) {
      if (msgId) {
        state.streamedThinkingByMessageId.add(msgId);
      }
      out.push(
        withNotificationParentMeta(
          sessionId,
          {
            sessionUpdate: "agent_thought_chunk",
            content: { type: "text", text: block.thinking },
          },
          parentToolCallId,
        ),
      );
      continue;
    }

    if (
      block.type === "tool_use" &&
      typeof block.id === "string" &&
      typeof block.name === "string"
    ) {
      if (state.emittedToolCallIds.has(block.id)) {
        continue;
      }
      state.emittedToolCallIds.add(block.id);

      // T3 `ClaudeAdapterV2.ts:10026`: only top-level TodoWrite updates the live plan.
      if (
        block.name === "TodoWrite" &&
        parentToolCallId === null &&
        isPlainRecord(block.input) &&
        Array.isArray(block.input.todos)
      ) {
        out.push({
          sessionId,
          update: {
            sessionUpdate: "plan",
            entries: extractTodoPlanEntries(block.input),
          },
        });
      }

      const locations = extractToolCallLocations(block.input);
      const toolContent = extractToolCallContent(block.name, block.input);
      const subagent = isSubagentTool(block.name);
      const vitruvianMeta: Record<string, unknown> = {};
      if (subagent) {
        vitruvianMeta.subagent = true;
      }
      if (parentToolCallId) {
        vitruvianMeta.parentToolCallId = parentToolCallId;
      }

      const toolCallUpdate: SessionUpdate = {
        sessionUpdate: "tool_call",
        toolCallId: block.id,
        title: formatToolCallTitle(block.name, block.input),
        kind: mapToolKind(block.name),
        status: "pending",
        rawInput: block.input,
        ...(locations ? { locations } : {}),
        ...(toolContent ? { content: toolContent } : {}),
        ...(Object.keys(vitruvianMeta).length > 0
          ? { _meta: { vitruvian: vitruvianMeta } }
          : {}),
      };

      out.push(
        withNotificationParentMeta(sessionId, toolCallUpdate, parentToolCallId),
      );
    }
  }

  return out;
}

function extractToolResultText(content: unknown): string {
  if (typeof content === "string") {
    return content;
  }
  if (!Array.isArray(content)) {
    return "";
  }
  const parts: string[] = [];
  for (const item of content) {
    if (typeof item === "string") {
      parts.push(item);
    } else if (
      isPlainRecord(item) &&
      item.type === "text" &&
      typeof item.text === "string"
    ) {
      parts.push(item.text);
    }
  }
  return parts.join("\n");
}

/** Maps `user` `tool_result` blocks (T3 `ClaudeAdapterV2.ts:3695-3727, 10058-10095`). */
function mapUserMessage(
  sessionId: string,
  message: SDKUserMessage,
): SessionNotification[] {
  const content = message.message?.content;
  if (!Array.isArray(content)) {
    return [];
  }
  const parentToolCallId = nonEmptyString(message.parent_tool_use_id) ?? null;
  const out: SessionNotification[] = [];

  for (const block of content) {
    if (
      !isPlainRecord(block) ||
      block.type !== "tool_result" ||
      typeof block.tool_use_id !== "string" ||
      block.tool_use_id.length === 0
    ) {
      continue;
    }
    // T3 `ClaudeAdapterV2.ts:10060`: skip placeholder launch ack echoing parent id.
    if (parentToolCallId === block.tool_use_id) {
      continue;
    }

    const text = extractToolResultText(block.content);
    const meta = parentMetaForToolCallId(parentToolCallId);
    const update: SessionUpdate = {
      sessionUpdate: "tool_call_update",
      toolCallId: block.tool_use_id,
      status: block.is_error === true ? "failed" : "completed",
      ...(text.length > 0
        ? {
            content: [
              {
                type: "content",
                content: { type: "text", text },
              },
            ],
          }
        : {}),
      ...(meta ? { _meta: meta } : {}),
    };

    out.push(withNotificationParentMeta(sessionId, update, parentToolCallId));
  }

  return out;
}

function nonNegativeInt(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0
    ? Math.trunc(value)
    : 0;
}

/** Token counts of one assistant message; null for a call that reports none (synthetic messages). */
function readCallUsage(message: unknown): CallUsage | null {
  if (!isPlainRecord(message) || !isPlainRecord(message.usage)) {
    return null;
  }
  const usage = message.usage;
  const call: CallUsage = {
    inputTokens: nonNegativeInt(usage.input_tokens),
    outputTokens: nonNegativeInt(usage.output_tokens),
    cacheReadTokens: nonNegativeInt(usage.cache_read_input_tokens),
    cacheWriteTokens: nonNegativeInt(usage.cache_creation_input_tokens),
  };
  return call.inputTokens + call.cacheReadTokens + call.cacheWriteTokens > 0
    ? call
    : null;
}

function resolveContextWindowSize(
  modelUsage: Record<string, ModelUsage> | undefined,
): number {
  if (!modelUsage) {
    return DEFAULT_CONTEXT_WINDOW_TOKENS;
  }
  let maxWindow = 0;
  for (const entry of Object.values(modelUsage)) {
    if (
      entry &&
      typeof entry.contextWindow === "number" &&
      Number.isFinite(entry.contextWindow) &&
      entry.contextWindow > maxWindow
    ) {
      maxWindow = Math.trunc(entry.contextWindow);
    }
  }
  return maxWindow > 0 ? maxWindow : DEFAULT_CONTEXT_WINDOW_TOKENS;
}

/**
 * Maps a turn's end into an ACP `usage_update` carrying the context size: the
 * newest model call's tokens, never the turn's sum. A turn with no model call
 * (a local command such as `/context`, or a background-task wake-up) reports
 * zeros, and sending those would blank the app's meter, so it sends nothing
 * and the app keeps the last real size.
 */
function mapResultUsageNotification(
  sessionId: string,
  message: SDKResultMessage,
  state: MappingState,
): SessionNotification[] {
  // A one-call turn has no assistant message to read only when the stream
  // dropped it; then the result's own usage is that one call.
  const call =
    state.lastCallUsage ??
    (message.num_turns <= 1
      ? readCallUsage({ usage: message.usage })
      : null);
  if (!call) {
    return [];
  }
  const {
    inputTokens,
    outputTokens,
    cacheReadTokens,
    cacheWriteTokens,
  } = call;

  const cachedTokens = cacheReadTokens + cacheWriteTokens;
  const used = inputTokens + outputTokens + cachedTokens;
  const size = resolveContextWindowSize(message.modelUsage);
  const cost =
    typeof message.total_cost_usd === "number" &&
    Number.isFinite(message.total_cost_usd) &&
    message.total_cost_usd >= 0
      ? { amount: message.total_cost_usd, currency: "USD" }
      : undefined;

  // The ACP TS schema omits the Vitruvian top-level token fields that protocol/schema.json declares.
  const update = {
    sessionUpdate: "usage_update",
    used,
    size,
    ...(cost ? { cost } : {}),
    inputTokens,
    outputTokens,
    cachedTokens,
    _meta: {
      vitruvian: {
        inputTokens,
        outputTokens,
        cacheReadTokens,
        cacheWriteTokens,
      },
    },
  } as unknown as SessionUpdate;

  return [{ sessionId, update }];
}

export function buildAvailableCommandsUpdate(
  sessionId: string,
  sdkSlashCommands: readonly string[],
  diskCommands: readonly AvailableSlashCommand[] = [],
): SessionNotification {
  const availableCommands: AvailableCommand[] = mergeAvailableCommands(
    sdkSlashCommands,
    diskCommands,
  );
  return {
    sessionId,
    update: {
      sessionUpdate: "available_commands_update",
      availableCommands,
    },
  };
}

function mapSystemInitMessage(
  sessionId: string,
  message: SDKSystemMessage,
  options?: MapSdkMessageOptions,
): SessionNotification[] {
  const sdkCommands = Array.isArray(message.slash_commands)
    ? message.slash_commands
    : [];
  return [
    buildAvailableCommandsUpdate(
      sessionId,
      sdkCommands,
      options?.diskCommands ?? [],
    ),
  ];
}

function extractCompactionSummary(
  raw: Record<string, unknown>,
): string | undefined {
  if (!isPlainRecord(raw.compact_metadata)) {
    return undefined;
  }
  const meta = raw.compact_metadata;
  const explicit = nonEmptyString(meta.summary);
  if (explicit) {
    return explicit;
  }
  const preTokens =
    typeof meta.pre_tokens === "number" &&
    Number.isFinite(meta.pre_tokens) &&
    meta.pre_tokens > 0
      ? Math.round(meta.pre_tokens)
      : undefined;
  const postTokens =
    typeof meta.post_tokens === "number" &&
    Number.isFinite(meta.post_tokens) &&
    meta.post_tokens > 0
      ? Math.round(meta.post_tokens)
      : undefined;
  if (preTokens !== undefined && postTokens !== undefined) {
    return `${preTokens} -> ${postTokens} tokens`;
  }
  if (preTokens !== undefined) {
    return `${preTokens} tokens compacted`;
  }
  return undefined;
}

/**
 * Maps SDK `system` compaction status and boundary messages into ACP `compaction_update` notifications.
 * Follows T3 `ClaudeAdapterV2.ts:11465-11610`.
 */
function mapSystemCompactionMessage(
  sessionId: string,
  message: SDKMessage,
  state: MappingState,
): SessionNotification[] {
  const raw = message as unknown as Record<string, unknown>;
  if (raw.subtype === "status") {
    if (raw.status === "compacting") {
      if (state.activeCompactionId !== null) {
        return [];
      }
      const compactionId =
        nonEmptyString(raw.uuid) ?? `compaction-${++state.compactionSeq}`;
      state.activeCompactionId = compactionId;
      return [
        {
          sessionId,
          update: {
            sessionUpdate: "compaction_update",
            compactionId,
            status: "running",
          } as unknown as SessionUpdate,
        },
      ];
    }

    if (
      raw.compact_result !== undefined ||
      (raw.status === null && raw.permissionMode === undefined)
    ) {
      if (state.activeCompactionId === null) {
        return [];
      }
      const compactionId = state.activeCompactionId;
      const compactResult = raw.compact_result;
      const compactError = nonEmptyString(raw.compact_error);
      if (compactResult === "success") {
        return [
          {
            sessionId,
            update: {
              sessionUpdate: "compaction_update",
              compactionId,
              status: "completed",
            } as unknown as SessionUpdate,
          },
        ];
      }
      if (compactResult === "failed") {
        state.activeCompactionId = null;
        return [
          {
            sessionId,
            update: {
              sessionUpdate: "compaction_update",
              compactionId,
              status: "failed",
              ...(compactError ? { summary: compactError } : {}),
            } as unknown as SessionUpdate,
          },
        ];
      }
      state.activeCompactionId = null;
      return [
        {
          sessionId,
          update: {
            sessionUpdate: "compaction_update",
            compactionId,
            status: "interrupted",
          } as unknown as SessionUpdate,
        },
      ];
    }
    return [];
  }

  if (raw.subtype === "compact_boundary") {
    const compactionId =
      state.activeCompactionId ??
      nonEmptyString(raw.uuid) ??
      `compaction-${++state.compactionSeq}`;
    state.activeCompactionId = null;
    const summary = extractCompactionSummary(raw);
    return [
      {
        sessionId,
        update: {
          sessionUpdate: "compaction_update",
          compactionId,
          status: "completed",
          ...(summary ? { summary } : {}),
        } as unknown as SessionUpdate,
      },
    ];
  }

  return [];
}

/** Pure mapper from a single Claude Agent SDK message to ACP `session/update` notifications. */
export function mapSdkMessageToNotifications(
  sessionId: string,
  message: SDKMessage,
  state: MappingState,
  options?: MapSdkMessageOptions,
): SessionNotification[] {
  switch (message.type) {
    case "stream_event":
      return mapStreamEventMessage(sessionId, message, state);
    case "assistant":
      return mapAssistantMessage(sessionId, message, state);
    case "user":
      return mapUserMessage(sessionId, message);
    case "result":
      return mapResultUsageNotification(sessionId, message, state);
    case "system":
      if (message.subtype === "init") {
        return mapSystemInitMessage(sessionId, message, options);
      }
      return mapSystemCompactionMessage(sessionId, message, state);
    default:
      return [];
  }
}

function mapSuccessStopReason(rawStopReason: string | null): StopReason {
  switch (rawStopReason) {
    case "max_tokens":
      return "max_tokens";
    case "max_turn_requests":
      return "max_turn_requests";
    case "refusal":
      return "refusal";
    case "cancelled":
      return "cancelled";
    default:
      return "end_turn";
  }
}

function extractResultErrorText(message: SDKResultMessage): string {
  if (message.subtype !== "success") {
    // T3 `ClaudeAdapterV2.ts:3948-3955`: skip internal `[ede_diagnostic]` lines.
    const userFacing = message.errors.find(
      (entry) =>
        typeof entry === "string" &&
        entry.trim().length > 0 &&
        !entry.startsWith("[ede_diagnostic]"),
    );
    if (userFacing) {
      return userFacing;
    }
    const joined = message.errors.filter(Boolean).join("; ").trim();
    return joined.length > 0 ? joined : message.subtype;
  }
  const resultText =
    typeof message.result === "string" ? message.result.trim() : "";
  return resultText.length > 0 ? resultText : "Claude SDK request failed";
}

function isAuthErrorResult(
  message: SDKResultMessage,
  state: MappingState,
  errorText: string,
): boolean {
  if (message.subtype === "success" && message.api_error_status === 403) {
    return false;
  }
  if (state.authErrorDetected) {
    return true;
  }
  if (message.subtype === "success" && message.api_error_status === 401) {
    return true;
  }
  return AUTH_ERROR_PATTERN.test(errorText);
}

/**
 * Classifies a terminal SDK `result` message into an ACP `stopReason` or JSON-RPC error.
 * Follows T3 `ClaudeAdapterV2.ts:3948-4035, 9439-9444, 10331-10365`.
 */
export function classifySdkResult(
  message: SDKResultMessage,
  state: MappingState,
  cancelled: boolean,
): ClassifiedSdkResult {
  if (
    cancelled ||
    message.terminal_reason === "aborted_streaming" ||
    message.terminal_reason === "aborted_tools"
  ) {
    return { kind: "stop", stopReason: "cancelled" };
  }

  if (
    message.subtype === "error_max_turns" ||
    message.terminal_reason === "max_turns"
  ) {
    return { kind: "stop", stopReason: "max_turn_requests" };
  }

  const effectiveStopReason =
    nonEmptyString(message.stop_reason) ?? state.lastAssistantStopReason;

  if (message.subtype === "success" && !message.is_error) {
    if (message.terminal_reason === ("max_tokens" as unknown)) {
      return { kind: "stop", stopReason: "max_tokens" };
    }
    return {
      kind: "stop",
      stopReason: mapSuccessStopReason(effectiveStopReason),
    };
  }

  const errorText = extractResultErrorText(message);
  if (
    message.subtype !== "success" &&
    errorText.toLowerCase().includes("cancel")
  ) {
    return { kind: "stop", stopReason: "cancelled" };
  }

  if (isAuthErrorResult(message, state, errorText)) {
    return {
      kind: "error",
      error: RequestError.authRequired(
        { reason: "auth_required" },
        "Run `claude auth login` in your terminal and try again.",
      ),
    };
  }

  return {
    kind: "error",
    error: new RequestError(-32603, errorText),
  };
}
