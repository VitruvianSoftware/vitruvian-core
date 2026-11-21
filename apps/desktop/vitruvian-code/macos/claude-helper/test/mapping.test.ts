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

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import type {
  SDKAssistantMessage,
  SDKMessage,
  SDKPartialAssistantMessage,
  SDKResultMessage,
  SDKSystemMessage,
  SDKUserMessage,
} from "@anthropic-ai/claude-agent-sdk";
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";

import {
  classifySdkResult,
  createMappingState,
  mapSdkMessageToNotifications,
  mapToolKind,
} from "../src/mapping.js";

const SCHEMA_URI = "https://vitruviansoftware.dev/schemas/claude-helper.json";
const schema = JSON.parse(
  readFileSync(
    join(
      dirname(fileURLToPath(import.meta.url)),
      "..",
      "protocol",
      "schema.json",
    ),
    "utf8",
  ),
) as Record<string, unknown>;

const ajv = new Ajv2020({ allErrors: true, strict: false });
addFormats(ajv);
ajv.addSchema(schema, SCHEMA_URI);
const validateWireMessage = ajv.getSchema(SCHEMA_URI)!;

const SESSION_ID = "550e8400-e29b-41d4-a716-446655440000";
const UUID_1 = "11111111-1111-4111-8111-111111111111";

function assertValidWireNotifications(
  notifications: ReturnType<typeof mapSdkMessageToNotifications>,
): void {
  for (const notification of notifications) {
    const envelope = {
      jsonrpc: "2.0",
      method: "session/update",
      params: notification,
    };
    const ok = validateWireMessage(envelope);
    if (!ok) {
      throw new Error(
        `Notification failed schema validation: ${ajv.errorsText(validateWireMessage.errors)}\n${JSON.stringify(envelope, null, 2)}`,
      );
    }
  }
}

function makeStreamMessage(
  event: SDKPartialAssistantMessage["event"],
  parentToolUseId: string | null = null,
): SDKPartialAssistantMessage {
  return {
    type: "stream_event",
    event,
    parent_tool_use_id: parentToolUseId,
    uuid: UUID_1,
    session_id: SESSION_ID,
  };
}

function makeAssistantMessage(
  blocks: Array<Record<string, unknown>>,
  opts?: {
    readonly id?: string;
    readonly parentToolUseId?: string | null;
    readonly stopReason?: string | null;
    readonly error?: SDKAssistantMessage["error"];
  },
): SDKAssistantMessage {
  return {
    type: "assistant",
    message: {
      id: opts?.id ?? "msg_1",
      type: "message",
      role: "assistant",
      model: "claude-sonnet-4-5",
      content: blocks as unknown as SDKAssistantMessage["message"]["content"],
      stop_reason: (opts?.stopReason ??
        null) as SDKAssistantMessage["message"]["stop_reason"],
      stop_sequence: null,
      usage: {
        input_tokens: 10,
        output_tokens: 5,
        cache_creation_input_tokens: 0,
        cache_read_input_tokens: 0,
      },
    } as unknown as SDKAssistantMessage["message"],
    parent_tool_use_id: opts?.parentToolUseId ?? null,
    error: opts?.error,
    uuid: UUID_1,
    session_id: SESSION_ID,
  };
}

function makeUserToolResult(
  blocks: Array<Record<string, unknown>>,
  parentToolUseId: string | null = null,
): SDKUserMessage {
  return {
    type: "user",
    message: {
      role: "user",
      content: blocks as unknown as SDKUserMessage["message"]["content"],
    },
    parent_tool_use_id: parentToolUseId,
  };
}

function makeSuccessResult(
  overrides?: Partial<Extract<SDKResultMessage, { subtype: "success" }>>,
): SDKResultMessage {
  return {
    type: "result",
    subtype: "success",
    duration_ms: 100,
    duration_api_ms: 80,
    is_error: false,
    num_turns: 1,
    result: "Done.",
    stop_reason: "end_turn",
    total_cost_usd: 0.0142,
    usage: {
      input_tokens: 1800,
      output_tokens: 450,
      cache_read_input_tokens: 150,
      cache_creation_input_tokens: 50,
    } as unknown as SDKResultMessage["usage"],
    modelUsage: {
      "claude-sonnet-4-5": {
        inputTokens: 1800,
        outputTokens: 450,
        cacheReadInputTokens: 150,
        cacheCreationInputTokens: 50,
        webSearchRequests: 0,
        costUSD: 0.0142,
        contextWindow: 200_000,
        maxOutputTokens: 16_384,
      },
    },
    permission_denials: [],
    uuid: UUID_1,
    session_id: SESSION_ID,
    ...overrides,
  };
}

describe("SDK -> ACP mapping", () => {
  test("maps streamed thinking and text deltas and suppresses duplicate assistant snapshot text/thinking", () => {
    const state = createMappingState();
    const emitted: ReturnType<typeof mapSdkMessageToNotifications> = [];

    const streamFrames: SDKMessage[] = [
      makeStreamMessage({
        type: "message_start",
        message: { id: "msg_stream_1" } as unknown as Extract<
          SDKPartialAssistantMessage["event"],
          { type: "message_start" }
        >["message"],
      }),
      makeStreamMessage({
        type: "content_block_delta",
        index: 0,
        delta: {
          type: "thinking_delta",
          thinking: "Analyzing ",
          estimated_tokens: null,
        },
      }),
      makeStreamMessage({
        type: "content_block_delta",
        index: 0,
        delta: {
          type: "thinking_delta",
          thinking: "schema.",
          estimated_tokens: null,
        },
      }),
      makeStreamMessage({
        type: "content_block_delta",
        index: 1,
        delta: { type: "text_delta", text: "Hello " },
      }),
      makeStreamMessage({
        type: "content_block_delta",
        index: 1,
        delta: { type: "text_delta", text: "world!" },
      }),
      makeStreamMessage({ type: "message_stop" }),
      // Complete assistant snapshot for the same message must NOT re-emit text or thinking.
      makeAssistantMessage(
        [
          { type: "thinking", thinking: "Analyzing schema.", signature: "sig" },
          { type: "text", text: "Hello world!" },
        ],
        { id: "msg_stream_1", stopReason: "end_turn" },
      ),
    ];

    for (const frame of streamFrames) {
      const notes = mapSdkMessageToNotifications(SESSION_ID, frame, state);
      assertValidWireNotifications(notes);
      emitted.push(...notes);
    }

    expect(emitted).toEqual([
      {
        sessionId: SESSION_ID,
        update: {
          sessionUpdate: "agent_thought_chunk",
          content: { type: "text", text: "Analyzing " },
        },
      },
      {
        sessionId: SESSION_ID,
        update: {
          sessionUpdate: "agent_thought_chunk",
          content: { type: "text", text: "schema." },
        },
      },
      {
        sessionId: SESSION_ID,
        update: {
          sessionUpdate: "agent_message_chunk",
          content: { type: "text", text: "Hello " },
        },
      },
      {
        sessionId: SESSION_ID,
        update: {
          sessionUpdate: "agent_message_chunk",
          content: { type: "text", text: "world!" },
        },
      },
    ]);
  });

  test("emits assistant text and thinking when no stream_event deltas preceded the snapshot", () => {
    const state = createMappingState();
    const notes = mapSdkMessageToNotifications(
      SESSION_ID,
      makeAssistantMessage([
        { type: "thinking", thinking: "Step 1", signature: "sig" },
        { type: "text", text: "Final answer" },
      ]),
      state,
    );
    assertValidWireNotifications(notes);
    expect(notes).toHaveLength(2);
    expect(notes[0].update.sessionUpdate).toBe("agent_thought_chunk");
    expect(notes[1].update.sessionUpdate).toBe("agent_message_chunk");
  });

  test("maps every tool kind, Edit/Write diffs, locations, and subagent/child metadata", () => {
    const expectedKinds: Array<[string, string]> = [
      ["Read", "read"],
      ["NotebookRead", "read"],
      ["Edit", "edit"],
      ["MultiEdit", "edit"],
      ["Write", "edit"],
      ["NotebookEdit", "edit"],
      ["Bash", "execute"],
      ["BashOutput", "execute"],
      ["KillShell", "execute"],
      ["Grep", "search"],
      ["Glob", "search"],
      ["LS", "search"],
      ["WebFetch", "fetch"],
      ["WebSearch", "fetch"],
      ["Task", "other"],
      ["Agent", "other"],
      ["ExitPlanMode", "switch_mode"],
      ["CustomMcpTool", "other"],
    ];

    for (const [toolName, expectedKind] of expectedKinds) {
      expect(mapToolKind(toolName)).toBe(expectedKind);
    }

    const state = createMappingState();
    const notes = mapSdkMessageToNotifications(
      SESSION_ID,
      makeAssistantMessage([
        {
          type: "tool_use",
          id: "toolu_edit",
          name: "Edit",
          input: {
            file_path: "/repo/README.md",
            old_string: "old",
            new_string: "new",
          },
        },
        {
          type: "tool_use",
          id: "toolu_write",
          name: "Write",
          input: {
            file_path: "/repo/notes.txt",
            content: "hello",
          },
        },
        {
          type: "tool_use",
          id: "toolu_agent",
          name: "Agent",
          input: { description: "Explore repository", prompt: "Search" },
        },
        {
          type: "tool_use",
          id: "toolu_exit_plan",
          name: "ExitPlanMode",
          input: {},
        },
      ]),
      state,
    );

    const childRead = mapSdkMessageToNotifications(
      SESSION_ID,
      makeAssistantMessage(
        [
          {
            type: "tool_use",
            id: "toolu_child_read",
            name: "Read",
            input: { file_path: "/repo/Sources/App.swift", line: 10 },
          },
        ],
        { id: "msg_child", parentToolUseId: "toolu_agent" },
      ),
      state,
    );

    const toolResults = mapSdkMessageToNotifications(
      SESSION_ID,
      makeUserToolResult(
        [
          {
            type: "tool_result",
            tool_use_id: "toolu_edit",
            content: "Updated README.md",
          },
          {
            type: "tool_result",
            tool_use_id: "toolu_child_read",
            is_error: true,
            content: [{ type: "text", text: "File not found" }],
          },
        ],
        "toolu_agent",
      ),
      state,
    );

    assertValidWireNotifications([...notes, ...childRead, ...toolResults]);

    expect(notes[0].update).toMatchObject({
      sessionUpdate: "tool_call",
      toolCallId: "toolu_edit",
      kind: "edit",
      status: "pending",
      locations: [{ path: "/repo/README.md" }],
      content: [
        {
          type: "diff",
          path: "/repo/README.md",
          oldText: "old",
          newText: "new",
        },
      ],
    });
    expect(notes[1].update).toMatchObject({
      sessionUpdate: "tool_call",
      toolCallId: "toolu_write",
      kind: "edit",
      content: [
        {
          type: "diff",
          path: "/repo/notes.txt",
          oldText: null,
          newText: "hello",
        },
      ],
    });
    expect(notes[2].update).toMatchObject({
      sessionUpdate: "tool_call",
      toolCallId: "toolu_agent",
      title: "Explore repository",
      kind: "other",
      _meta: { vitruvian: { subagent: true } },
    });
    expect(notes[3].update).toMatchObject({
      sessionUpdate: "tool_call",
      toolCallId: "toolu_exit_plan",
      kind: "switch_mode",
    });

    expect(childRead[0]).toMatchObject({
      sessionId: SESSION_ID,
      _meta: { vitruvian: { parentToolCallId: "toolu_agent" } },
      update: {
        sessionUpdate: "tool_call",
        toolCallId: "toolu_child_read",
        kind: "read",
        locations: [{ path: "/repo/Sources/App.swift", line: 10 }],
        _meta: { vitruvian: { parentToolCallId: "toolu_agent" } },
      },
    });

    expect(toolResults[0].update).toMatchObject({
      sessionUpdate: "tool_call_update",
      toolCallId: "toolu_edit",
      status: "completed",
      content: [
        {
          type: "content",
          content: { type: "text", text: "Updated README.md" },
        },
      ],
    });
    expect(toolResults[1]).toMatchObject({
      _meta: { vitruvian: { parentToolCallId: "toolu_agent" } },
      update: {
        sessionUpdate: "tool_call_update",
        toolCallId: "toolu_child_read",
        status: "failed",
        content: [
          {
            type: "content",
            content: { type: "text", text: "File not found" },
          },
        ],
      },
    });
  });

  test("maps top-level TodoWrite to plan update and ignores subagent TodoWrite for plan", () => {
    const state = createMappingState();

    const topLevel = mapSdkMessageToNotifications(
      SESSION_ID,
      makeAssistantMessage([
        {
          type: "tool_use",
          id: "toolu_todo_root",
          name: "TodoWrite",
          input: {
            todos: [
              { content: "Inspect schema", status: "completed" },
              { content: "Implement mapper", status: "in_progress" },
              { content: "Run tests", status: "pending" },
            ],
          },
        },
      ]),
      state,
    );

    const subagent = mapSdkMessageToNotifications(
      SESSION_ID,
      makeAssistantMessage(
        [
          {
            type: "tool_use",
            id: "toolu_todo_child",
            name: "TodoWrite",
            input: {
              todos: [{ content: "Child task", status: "in_progress" }],
            },
          },
        ],
        { id: "msg_child", parentToolUseId: "toolu_agent" },
      ),
      state,
    );

    assertValidWireNotifications([...topLevel, ...subagent]);

    expect(topLevel[0]).toEqual({
      sessionId: SESSION_ID,
      update: {
        sessionUpdate: "plan",
        entries: [
          {
            content: "Inspect schema",
            priority: "medium",
            status: "completed",
          },
          {
            content: "Implement mapper",
            priority: "medium",
            status: "in_progress",
          },
          { content: "Run tests", priority: "medium", status: "pending" },
        ],
      },
    });
    expect(subagent.some((n) => n.update.sessionUpdate === "plan")).toBe(false);
  });

  test("maps result usage to usage_update and system init to deduped available_commands_update", () => {
    const state = createMappingState();
    const initMessage: SDKSystemMessage = {
      type: "system",
      subtype: "init",
      apiKeySource: "none",
      claude_code_version: "2.1.45",
      cwd: "/repo",
      tools: ["Read", "Bash"],
      mcp_servers: [],
      model: "claude-sonnet-4-5",
      permissionMode: "default",
      slash_commands: ["/compact", "review", "/review"],
      output_style: "default",
      skills: ["review"],
      plugins: [],
      uuid: UUID_1,
      session_id: SESSION_ID,
    };

    const initNotes = mapSdkMessageToNotifications(
      SESSION_ID,
      initMessage,
      state,
      {
        diskCommands: [
          {
            name: "review",
            description: "Review workspace changes",
            input: { hint: "Optional focus area" },
          },
          {
            name: "/deploy",
            description: "Deploy target",
          },
        ],
      },
    );
    const usageNotes = mapSdkMessageToNotifications(
      SESSION_ID,
      makeSuccessResult(),
      state,
    );

    assertValidWireNotifications([...initNotes, ...usageNotes]);

    expect(initNotes).toEqual([
      {
        sessionId: SESSION_ID,
        update: {
          sessionUpdate: "available_commands_update",
          availableCommands: [
            { name: "compact", description: "" },
            {
              name: "review",
              description: "Review workspace changes",
              input: { hint: "Optional focus area" },
            },
            { name: "deploy", description: "Deploy target" },
          ],
        },
      },
    ]);

    expect(usageNotes).toEqual([
      {
        sessionId: SESSION_ID,
        update: {
          sessionUpdate: "usage_update",
          used: 2450,
          size: 200_000,
          cost: { amount: 0.0142, currency: "USD" },
          inputTokens: 1800,
          outputTokens: 450,
          cachedTokens: 200,
          _meta: {
            vitruvian: {
              inputTokens: 1800,
              outputTokens: 450,
              cacheReadTokens: 150,
              cacheWriteTokens: 50,
            },
          },
        },
      },
    ]);
  });

  test("classifies stop reasons, SDK errors, and auth_required (-32000)", () => {
    const state = createMappingState();

    expect(classifySdkResult(makeSuccessResult(), state, false)).toEqual({
      kind: "stop",
      stopReason: "end_turn",
    });
    expect(
      classifySdkResult(
        makeSuccessResult({ stop_reason: "max_tokens" }),
        state,
        false,
      ),
    ).toEqual({ kind: "stop", stopReason: "max_tokens" });
    expect(
      classifySdkResult(
        makeSuccessResult({ stop_reason: "refusal" }),
        state,
        false,
      ),
    ).toEqual({ kind: "stop", stopReason: "refusal" });
    expect(
      classifySdkResult(
        makeSuccessResult({
          subtype: "error_max_turns",
          errors: [],
        } as unknown as Partial<
          Extract<SDKResultMessage, { subtype: "success" }>
        >),
        state,
        false,
      ),
    ).toEqual({ kind: "stop", stopReason: "max_turn_requests" });
    expect(classifySdkResult(makeSuccessResult(), state, true)).toEqual({
      kind: "stop",
      stopReason: "cancelled",
    });

    const errOutcome = classifySdkResult(
      {
        ...makeSuccessResult(),
        subtype: "error_during_execution",
        is_error: true,
        errors: ["[ede_diagnostic] internal", "Tool runner crashed"],
      },
      state,
      false,
    );
    expect(errOutcome.kind).toBe("error");
    if (errOutcome.kind === "error") {
      expect(errOutcome.error.code).toBe(-32603);
      expect(errOutcome.error.message).toBe("Tool runner crashed");
    }

    // Auth error flagged on assistant frame followed by error result -> -32000 with claude auth login
    mapSdkMessageToNotifications(
      SESSION_ID,
      makeAssistantMessage([{ type: "text", text: "Invalid API key" }], {
        error: "authentication_failed",
      }),
      state,
    );
    const authOutcome = classifySdkResult(
      makeSuccessResult({
        is_error: true,
        result: "Authentication failed",
      }),
      state,
      false,
    );
    expect(authOutcome.kind).toBe("error");
    if (authOutcome.kind === "error") {
      expect(authOutcome.error.code).toBe(-32000);
      expect(authOutcome.error.message).toContain("claude auth login");
    }
  });
});
