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

import {
  client,
  ndJsonStream,
  RequestError,
  type AgentConnection,
  type ClientConnection,
  type SessionNotification,
} from "@agentclientprotocol/sdk";
import type {
  McpServerStatus,
  ModelInfo,
  Options as SdkQueryOptions,
  PermissionMode,
  Query as SdkQuery,
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
  createClaudeHelperApp,
  type ClaudeHelperAgentOptions,
  type ForkFn,
  type QueryFn,
} from "../src/agent.js";
import { parseArgs } from "../src/main.js";

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

const UUID_1 = "11111111-1111-4111-8111-111111111111";

interface Deferred<T> {
  readonly promise: Promise<T>;
  resolve: (value: T) => void;
  reject: (reason?: unknown) => void;
}

function createDeferred<T>(): Deferred<T> {
  let resolve!: (value: T) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

class AsyncQueue<T> {
  private readonly items: T[] = [];
  private readonly waiters: Array<(res: IteratorResult<T>) => void> = [];
  private ended = false;
  private failure: unknown = undefined;
  private hasFailure = false;

  push(item: T): void {
    if (this.ended || this.hasFailure) return;
    const waiter = this.waiters.shift();
    if (waiter) {
      waiter({ value: item, done: false });
      return;
    }
    this.items.push(item);
  }

  finish(): void {
    if (this.ended) return;
    this.ended = true;
    while (this.waiters.length > 0) {
      this.waiters.shift()!({ value: undefined as unknown as T, done: true });
    }
  }

  next(): Promise<IteratorResult<T>> {
    if (this.items.length > 0) {
      return Promise.resolve({ value: this.items.shift()!, done: false });
    }
    if (this.hasFailure) {
      return Promise.reject(this.failure);
    }
    if (this.ended) {
      return Promise.resolve({ value: undefined as unknown as T, done: true });
    }
    return new Promise<IteratorResult<T>>((resolve) => {
      this.waiters.push(resolve);
    });
  }
}

interface FakeQueryHandle {
  readonly options: SdkQueryOptions | undefined;
  readonly pushedUserMessages: SDKUserMessage[];
  readonly setPermissionModeCalls: PermissionMode[];
  readonly setModelCalls: Array<string | undefined>;
  interruptCalls: number;
  closeCalls: number;
  readonly emit: (message: SDKMessage) => void;
  readonly finishOutput: () => void;
}

function createFakeQuery(config: {
  readonly options: SdkQueryOptions | undefined;
  readonly promptInput: string | AsyncIterable<SDKUserMessage>;
  readonly models?: ModelInfo[] | Promise<ModelInfo[]>;
  readonly mcpServers?: McpServerStatus[];
  readonly onPromptMessage?: (
    userMsg: SDKUserMessage,
    handle: FakeQueryHandle,
  ) => void | Promise<void>;
  readonly onInterrupt?: (handle: FakeQueryHandle) => void;
}): { readonly sdkQuery: SdkQuery; readonly handle: FakeQueryHandle } {
  const outputQueue = new AsyncQueue<SDKMessage>();
  const pushedUserMessages: SDKUserMessage[] = [];
  const setPermissionModeCalls: PermissionMode[] = [];
  const setModelCalls: Array<string | undefined> = [];

  const handle: FakeQueryHandle = {
    options: config.options,
    pushedUserMessages,
    setPermissionModeCalls,
    setModelCalls,
    interruptCalls: 0,
    closeCalls: 0,
    emit: (message) => outputQueue.push(message),
    finishOutput: () => outputQueue.finish(),
  };

  if (typeof config.promptInput !== "string") {
    void (async () => {
      for await (const msg of config.promptInput) {
        pushedUserMessages.push(msg);
        await config.onPromptMessage?.(msg, handle);
      }
    })();
  }

  const sdkQuery: SdkQuery = {
    next: () => outputQueue.next(),
    return: async () => {
      outputQueue.finish();
      return { value: undefined, done: true };
    },
    throw: async (error) => {
      outputQueue.finish();
      throw error;
    },
    [Symbol.asyncIterator]() {
      return this;
    },
    [Symbol.asyncDispose]: async () => {
      outputQueue.finish();
    },
    interrupt: async () => {
      handle.interruptCalls += 1;
      config.onInterrupt?.(handle);
      return undefined;
    },
    setPermissionMode: async (mode: PermissionMode) => {
      setPermissionModeCalls.push(mode);
    },
    setMcpPermissionModeOverride: async () => ({}),
    setModel: async (model?: string) => {
      setModelCalls.push(model);
    },
    setMaxThinkingTokens: async () => undefined,
    applyFlagSettings: async () => undefined,
    updateSettings: async () => undefined,
    initializationResult: async () =>
      ({}) as Awaited<ReturnType<SdkQuery["initializationResult"]>>,
    reinitialize: async () =>
      ({}) as Awaited<ReturnType<SdkQuery["reinitialize"]>>,
    supportedCommands: async () => [],
    supportedModels: async () =>
      Array.isArray(config.models)
        ? config.models
        : config.models
          ? await config.models
          : [],
    supportedAgents: async () => [],
    mcpServerStatus: async () => config.mcpServers ?? [],
    getContextUsage: async () =>
      ({}) as Awaited<ReturnType<SdkQuery["getContextUsage"]>>,
    usage_EXPERIMENTAL_MAY_CHANGE_DO_NOT_RELY_ON_THIS_API_YET: async () =>
      ({}) as Awaited<
        ReturnType<
          SdkQuery["usage_EXPERIMENTAL_MAY_CHANGE_DO_NOT_RELY_ON_THIS_API_YET"]
        >
      >,
    readFile: async () => null,
    reloadPlugins: async () =>
      ({}) as Awaited<ReturnType<SdkQuery["reloadPlugins"]>>,
    reloadSkills: async () =>
      ({}) as Awaited<ReturnType<SdkQuery["reloadSkills"]>>,
    reloadOutputStyles: async () =>
      ({}) as Awaited<ReturnType<SdkQuery["reloadOutputStyles"]>>,
    accountInfo: async () => ({}),
    rewindFiles: async () => ({ canRewind: false }),
    seedReadState: async () => undefined,
    reconnectMcpServer: async () => undefined,
    toggleMcpServer: async () => undefined,
    readMcpResource: async () =>
      ({}) as Awaited<ReturnType<SdkQuery["readMcpResource"]>>,
    setMcpServers: async () => ({ added: [], removed: [], errors: {} }),
    streamInput: async () => undefined,
    stopTask: async () => undefined,
    backgroundTasks: async () => false,
    close: () => {
      handle.closeCalls += 1;
      outputQueue.finish();
    },
  };

  return { sdkQuery, handle };
}

interface Harness {
  readonly agentConnection: AgentConnection;
  readonly clientConnection: ClientConnection;
  readonly client: ClientConnection["agent"];
  readonly receivedUpdates: SessionNotification[];
  readonly receivedRawMessages: Array<Record<string, unknown>>;
  readonly receivedRawLines: string[];
  readonly close: () => Promise<void>;
}

function createConnectedHarness(options: ClaudeHelperAgentOptions): Harness {
  const { app } = createClaudeHelperApp(options);
  const receivedUpdates: SessionNotification[] = [];
  const receivedRawMessages: Array<Record<string, unknown>> = [];
  const receivedRawLines: string[] = [];

  const clientToAgent = new TransformStream<Uint8Array, Uint8Array>();
  const agentToClient = new TransformStream<Uint8Array, Uint8Array>();

  const decoder = new TextDecoder();
  let wireBuffer = "";
  const wireTap = new TransformStream<Uint8Array, Uint8Array>({
    transform(chunk, controller) {
      wireBuffer += decoder.decode(chunk, { stream: true });
      const lines = wireBuffer.split("\n");
      wireBuffer = lines.pop() ?? "";
      for (const line of lines) {
        if (line.trim().length > 0) {
          receivedRawLines.push(line);
          receivedRawMessages.push(JSON.parse(line) as Record<string, unknown>);
        }
      }
      controller.enqueue(chunk);
    },
  });

  const agentStream = ndJsonStream(
    agentToClient.writable,
    clientToAgent.readable,
  );
  const clientStream = ndJsonStream(
    clientToAgent.writable,
    agentToClient.readable.pipeThrough(wireTap),
  );

  const clientApp = client({ name: "test-acp-client" }).onNotification(
    "session/update",
    (ctx) => {
      receivedUpdates.push(ctx.params);
    },
  );

  const agentConn = app.connect(agentStream);
  const clientConn = clientApp.connect(clientStream);

  return {
    agentConnection: agentConn,
    clientConnection: clientConn,
    client: clientConn.agent,
    receivedUpdates,
    receivedRawMessages,
    receivedRawLines,
    close: async () => {
      clientConn.close();
      agentConn.close();
      await Promise.allSettled([clientConn.closed, agentConn.closed]);
    },
  };
}

function makeSuccessResult(
  sessionId: string,
  overrides?: Partial<Extract<SDKResultMessage, { subtype: "success" }>>,
): SDKResultMessage {
  return {
    type: "result",
    subtype: "success",
    duration_ms: 50,
    duration_api_ms: 40,
    is_error: false,
    num_turns: 1,
    result: "Completed",
    stop_reason: "end_turn",
    total_cost_usd: 0.01,
    usage: {
      input_tokens: 100,
      output_tokens: 40,
      cache_read_input_tokens: 10,
      cache_creation_input_tokens: 5,
    } as unknown as SDKResultMessage["usage"],
    modelUsage: {
      "claude-sonnet-4-5": {
        inputTokens: 100,
        outputTokens: 40,
        cacheReadInputTokens: 10,
        cacheCreationInputTokens: 5,
        webSearchRequests: 0,
        costUSD: 0.01,
        contextWindow: 200_000,
        maxOutputTokens: 16_384,
      },
    },
    permission_denials: [],
    uuid: UUID_1,
    session_id: sessionId,
    ...overrides,
  };
}

describe("ClaudeHelperAgent over real ACP streams", () => {
  test("initialize reports capabilities and Claude version (including null on failure)", async () => {
    const okHarness = createConnectedHarness({
      claudePath: "/usr/local/bin/claude",
      helperVersion: "0.1.0",
      detectVersionFn: async () => "2.1.45",
    });
    try {
      const res = await okHarness.client.request("initialize", {
        protocolVersion: 1,
        clientInfo: { name: "VitruvianCode", version: "1.0.0" },
        clientCapabilities: {},
      });
      expect(res.protocolVersion).toBe(1);
      expect(res.agentInfo?.name).toBe("vitruvian-claude-helper");
      expect(res.agentCapabilities?.loadSession).toBe(false);
      expect(res.agentCapabilities?.promptCapabilities).toMatchObject({
        image: true,
        embeddedContext: true,
      });
      expect(res.agentCapabilities?.sessionCapabilities?.resume).toEqual({});
      expect(res.agentCapabilities?.sessionCapabilities?.close).toEqual({});
      expect(res.authMethods).toEqual([]);
      expect(res._meta).toEqual({ vitruvian: { claudeVersion: "2.1.45" } });
    } finally {
      await okHarness.close();
    }

    const nullHarness = createConnectedHarness({
      claudePath: "/missing/claude",
      detectVersionFn: async () => {
        throw new Error("ENOENT");
      },
    });
    try {
      const res = await nullHarness.client.request("initialize", {
        protocolVersion: 1,
        clientCapabilities: {},
      });
      expect(res._meta).toEqual({ vitruvian: { claudeVersion: null } });
    } finally {
      await nullHarness.close();
    }
  });

  test("session/new passes generated UUID as sessionId, required SDK flags, and handles delayed supportedModels", async () => {
    const queryCalls: FakeQueryHandle[] = [];
    const deferredModels = createDeferred<ModelInfo[]>();
    const expectedSessionId = "550e8400-e29b-41d4-a716-446655440000";

    const queryFn: QueryFn = ({ prompt, options }) => {
      const { sdkQuery, handle } = createFakeQuery({
        options,
        promptInput: prompt,
        models: deferredModels.promise,
      });
      queryCalls.push(handle);
      return sdkQuery;
    };

    const harness = createConnectedHarness({
      claudePath: "/opt/bin/claude",
      baseEnv: { PATH: "/usr/bin", CLAUDE_CONFIG_DIR: "/custom/claude-dir" },
      generateSessionIdFn: () => expectedSessionId,
      supportedModelsTimeoutMs: 15,
      queryFn,
    });

    try {
      await harness.client.request("initialize", {
        protocolVersion: 1,
        clientCapabilities: {},
      });

      const created = await harness.client.request("session/new", {
        cwd: "/workspace/repo",
        mcpServers: [],
        additionalDirectories: ["/workspace/shared"],
      });

      expect(created.sessionId).toBe(expectedSessionId);
      expect(created.modes?.currentModeId).toBe("default");
      expect(created.modes?.availableModes.map((m) => m.id)).toEqual([
        "default",
        "acceptEdits",
        "plan",
        "bypassPermissions",
      ]);
      // Delayed models haven't arrived yet -> only mode configOption in initial result.
      expect(created.configOptions?.map((c) => c.id)).toEqual(["mode"]);

      expect(queryCalls).toHaveLength(1);
      const opts = queryCalls[0].options!;
      expect(opts.sessionId).toBe(expectedSessionId);
      expect(opts.resume).toBeUndefined();
      expect(opts.cwd).toBe("/workspace/repo");
      expect(opts.additionalDirectories).toEqual(["/workspace/shared"]);
      expect(opts.pathToClaudeCodeExecutable).toBe("/opt/bin/claude");
      expect(opts.includePartialMessages).toBe(true);
      expect(opts.settingSources).toEqual(["user", "project", "local"]);
      expect(typeof opts.canUseTool).toBe("function");
      expect(opts.permissionMode).toBe("default");
      expect(opts.allowDangerouslySkipPermissions).toBeUndefined();
      expect(opts.env?.CLAUDE_CODE_ENABLE_TODO_TOOLS).toBe("1");
      expect(opts.env?.CLAUDE_CONFIG_DIR).toBe("/custom/claude-dir");

      // Resolving supportedModels later triggers config_option_update with models.
      deferredModels.resolve([
        {
          value: "claude-sonnet-4-5",
          displayName: "Claude Sonnet 4.5",
          description: "Balanced",
        },
        {
          value: "claude-opus-4-1",
          displayName: "Claude Opus 4.1",
          description: "Deep reasoning",
        },
      ]);

      await new Promise((r) => setTimeout(r, 20));
      const configUpdates = harness.receivedUpdates.filter(
        (u) => u.update.sessionUpdate === "config_option_update",
      );
      expect(configUpdates).toHaveLength(1);
      expect(configUpdates[0].update).toMatchObject({
        sessionUpdate: "config_option_update",
        configOptions: [
          { id: "mode", currentValue: "default" },
          {
            id: "model",
            currentValue: "claude-sonnet-4-5",
            options: [
              { value: "claude-sonnet-4-5", name: "Claude Sonnet 4.5" },
              { value: "claude-opus-4-1", name: "Claude Opus 4.1" },
            ],
          },
        ],
      });
    } finally {
      await harness.close();
    }
  });

  test("session/resume passes resume option instead of sessionId and keeps required SDK invariants", async () => {
    const queryCalls: FakeQueryHandle[] = [];
    const harness = createConnectedHarness({
      claudePath: "/opt/bin/claude",
      baseEnv: { PATH: "/usr/bin" },
      queryFn: ({ prompt, options }) => {
        const { sdkQuery, handle } = createFakeQuery({
          options,
          promptInput: prompt,
          models: [
            {
              value: "claude-sonnet-4-5",
              displayName: "Claude Sonnet 4.5",
              description: "Fast",
            },
          ],
        });
        queryCalls.push(handle);
        return sdkQuery;
      },
    });

    try {
      await harness.client.request("initialize", {
        protocolVersion: 1,
        clientCapabilities: {},
      });

      const resumed = await harness.client.request("session/resume", {
        sessionId: "existing-session-123",
        cwd: "/workspace/repo",
        mcpServers: [],
      });

      expect(resumed.modes?.currentModeId).toBe("default");
      expect(resumed.configOptions?.map((c) => c.id)).toEqual([
        "mode",
        "model",
      ]);

      const opts = queryCalls[0].options!;
      expect(opts.resume).toBe("existing-session-123");
      expect(opts.sessionId).toBeUndefined();
      expect(opts.pathToClaudeCodeExecutable).toBe("/opt/bin/claude");
      expect(opts.env?.CLAUDE_CODE_ENABLE_TODO_TOOLS).toBe("1");
    } finally {
      await harness.close();
    }
  });

  test("replays full scripted SDK stream over ndJsonStream with single long-lived query, exact update order, and schema-valid wire frames", async () => {
    const queryHandles: FakeQueryHandle[] = [];
    let turnNumber = 0;
    const sid = "550e8400-e29b-41d4-a716-446655440000";

    const queryFn: QueryFn = ({ prompt, options }) => {
      const { sdkQuery, handle } = createFakeQuery({
        options,
        promptInput: prompt,
        onPromptMessage: async (_userMsg, h) => {
          turnNumber += 1;
          if (turnNumber === 1) {
            h.emit({
              type: "system",
              subtype: "init",
              apiKeySource: "none",
              claude_code_version: "2.1.45",
              cwd: "/repo",
              tools: [
                "Read",
                "Edit",
                "Bash",
                "Grep",
                "WebFetch",
                "Agent",
                "TodoWrite",
                "ExitPlanMode",
              ],
              mcp_servers: [],
              model: "claude-sonnet-4-5",
              permissionMode: "default",
              slash_commands: ["/compact", "review"],
              output_style: "default",
              skills: [],
              plugins: [],
              uuid: UUID_1,
              session_id: sid,
            } as SDKSystemMessage);
            h.emit({
              type: "stream_event",
              event: {
                type: "message_start",
                message: { id: "msg_turn_1" } as unknown as Extract<
                  SDKPartialAssistantMessage["event"],
                  { type: "message_start" }
                >["message"],
              },
              parent_tool_use_id: null,
              uuid: UUID_1,
              session_id: sid,
            });
            h.emit({
              type: "stream_event",
              event: {
                type: "content_block_delta",
                index: 0,
                delta: {
                  type: "thinking_delta",
                  thinking: "Checking files.",
                  estimated_tokens: null,
                },
              },
              parent_tool_use_id: null,
              uuid: UUID_1,
              session_id: sid,
            });
            h.emit({
              type: "stream_event",
              event: {
                type: "content_block_delta",
                index: 1,
                delta: { type: "text_delta", text: "Let me update README." },
              },
              parent_tool_use_id: null,
              uuid: UUID_1,
              session_id: sid,
            });
            h.emit({
              type: "stream_event",
              event: { type: "message_stop" },
              parent_tool_use_id: null,
              uuid: UUID_1,
              session_id: sid,
            });
            h.emit({
              type: "assistant",
              message: {
                id: "msg_turn_1",
                type: "message",
                role: "assistant",
                model: "claude-sonnet-4-5",
                content: [
                  {
                    type: "thinking",
                    thinking: "Checking files.",
                    signature: "sig",
                  },
                  { type: "text", text: "Let me update README." },
                  {
                    type: "tool_use",
                    id: "toolu_todo",
                    name: "TodoWrite",
                    input: {
                      todos: [
                        { content: "Edit README", status: "in_progress" },
                      ],
                    },
                  },
                  {
                    type: "tool_use",
                    id: "toolu_edit",
                    name: "Edit",
                    input: {
                      file_path: "/repo/README.md",
                      old_string: "before",
                      new_string: "after",
                    },
                  },
                  {
                    type: "tool_use",
                    id: "toolu_subagent",
                    name: "Task",
                    input: { description: "Inspect code", prompt: "Check" },
                  },
                ],
                stop_reason: "tool_use",
                stop_sequence: null,
                usage: {
                  input_tokens: 10,
                  output_tokens: 10,
                  cache_read_input_tokens: 0,
                  cache_creation_input_tokens: 0,
                },
              } as unknown as SDKAssistantMessage["message"],
              parent_tool_use_id: null,
              uuid: UUID_1,
              session_id: sid,
            });
            h.emit({
              type: "assistant",
              message: {
                id: "msg_child_1",
                type: "message",
                role: "assistant",
                model: "claude-sonnet-4-5",
                content: [
                  {
                    type: "tool_use",
                    id: "toolu_child_grep",
                    name: "Grep",
                    input: { pattern: "ACP", path: "/repo/src" },
                  },
                ],
                stop_reason: "tool_use",
                stop_sequence: null,
                usage: {
                  input_tokens: 5,
                  output_tokens: 5,
                  cache_read_input_tokens: 0,
                  cache_creation_input_tokens: 0,
                },
              } as unknown as SDKAssistantMessage["message"],
              parent_tool_use_id: "toolu_subagent",
              uuid: UUID_1,
              session_id: sid,
            });
            h.emit({
              type: "user",
              message: {
                role: "user",
                content: [
                  {
                    type: "tool_result",
                    tool_use_id: "toolu_edit",
                    content: "Edited README.md",
                  },
                ],
              },
              parent_tool_use_id: null,
            });
            h.emit(makeSuccessResult(sid));
          } else {
            h.emit({
              type: "assistant",
              message: {
                id: "msg_turn_2",
                type: "message",
                role: "assistant",
                model: "claude-sonnet-4-5",
                content: [{ type: "text", text: "Follow-up reply." }],
                stop_reason: "end_turn",
                stop_sequence: null,
                usage: {
                  input_tokens: 20,
                  output_tokens: 10,
                  cache_read_input_tokens: 0,
                  cache_creation_input_tokens: 0,
                },
              } as unknown as SDKAssistantMessage["message"],
              parent_tool_use_id: null,
              uuid: UUID_1,
              session_id: sid,
            });
            h.emit(makeSuccessResult(sid));
          }
        },
      });
      queryHandles.push(handle);
      return sdkQuery;
    };

    const harness = createConnectedHarness({
      claudePath: "/usr/local/bin/claude",
      generateSessionIdFn: () => sid,
      queryFn,
    });

    try {
      await harness.client.request("initialize", {
        protocolVersion: 1,
        clientCapabilities: {},
      });
      await harness.client.request("session/new", {
        cwd: "/repo",
        mcpServers: [],
      });

      const promptRes1 = await harness.client.request("session/prompt", {
        sessionId: sid,
        prompt: [
          { type: "text", text: "Update README" },
          { type: "image", data: "AAAA", mimeType: "image/png" },
          {
            type: "resource_link",
            uri: "file:///repo/README.md",
            name: "README.md",
          },
          {
            type: "resource",
            resource: {
              uri: "file:///repo/package.json",
              mimeType: "application/json",
              text: '{"name":"helper"}',
            },
          },
        ],
      });
      expect(promptRes1.stopReason).toBe("end_turn");

      // Verify converted prompt blocks sent into the single streaming query.
      expect(queryHandles).toHaveLength(1);
      expect(queryHandles[0].pushedUserMessages).toHaveLength(1);
      const sentContent = queryHandles[0].pushedUserMessages[0].message
        .content as Array<Record<string, unknown>>;
      expect(sentContent).toHaveLength(4);
      expect(sentContent[0]).toEqual({ type: "text", text: "Update README" });
      expect(sentContent[1]).toEqual({
        type: "image",
        source: { type: "base64", media_type: "image/png", data: "AAAA" },
      });
      expect(String(sentContent[2].text)).toContain("README.md");
      expect(String(sentContent[3].text)).toContain("package.json");

      // Exact ordered session/update sequence for turn 1.
      const updateKinds = harness.receivedUpdates.map(
        (u) => u.update.sessionUpdate,
      );
      expect(updateKinds).toEqual([
        "available_commands_update",
        "agent_thought_chunk",
        "agent_message_chunk",
        "plan",
        "tool_call", // TodoWrite
        "tool_call", // Edit
        "tool_call", // Task subagent
        "tool_call", // child Grep
        "tool_call_update", // Edit result
        "usage_update",
      ]);

      // Verify top-level token fields on raw wire JSON (Zod client parsing strips unknown keys).
      const rawUsageMsg = harness.receivedRawMessages.find(
        (m) =>
          m.method === "session/update" &&
          (m.params as Record<string, Record<string, unknown>>)?.update
            ?.sessionUpdate === "usage_update",
      );
      expect(rawUsageMsg).toBeDefined();
      const rawUsageUpdate = (
        rawUsageMsg!.params as Record<string, Record<string, unknown>>
      ).update;
      expect(rawUsageUpdate.inputTokens).toBe(100);
      expect(rawUsageUpdate.outputTokens).toBe(40);
      expect(rawUsageUpdate.cachedTokens).toBe(15);

      // Every raw JSON-RPC message sent by the helper must validate against protocol/schema.json.
      for (const wireMsg of harness.receivedRawMessages) {
        const valid = validateWireMessage(wireMsg);
        if (!valid) {
          throw new Error(
            `Wire message failed schema.json: ${ajv.errorsText(validateWireMessage.errors)}\n${JSON.stringify(wireMsg)}`,
          );
        }
      }

      // Second turn reuses the SAME long-lived SDK query.
      const promptRes2 = await harness.client.request("session/prompt", {
        sessionId: sid,
        prompt: [{ type: "text", text: "Second turn" }],
      });
      expect(promptRes2.stopReason).toBe("end_turn");
      expect(queryHandles).toHaveLength(1);
      expect(queryHandles[0].pushedUserMessages).toHaveLength(2);
    } finally {
      await harness.close();
    }
  });

  test("maps stopReason variants (max_tokens, max_turn_requests, refusal, cancelled) and JSON-RPC errors (auth -32000)", async () => {
    const sid = "550e8400-e29b-41d4-a716-446655440001";
    let step = 0;

    const harness = createConnectedHarness({
      claudePath: "/usr/local/bin/claude",
      generateSessionIdFn: () => sid,
      queryFn: ({ prompt, options }) => {
        const { sdkQuery } = createFakeQuery({
          options,
          promptInput: prompt,
          onPromptMessage: (_msg, h) => {
            step += 1;
            if (step === 1) {
              h.emit(makeSuccessResult(sid, { stop_reason: "max_tokens" }));
            } else if (step === 2) {
              h.emit({
                ...makeSuccessResult(sid),
                subtype: "error_max_turns",
                is_error: false,
                errors: [],
              } as unknown as SDKResultMessage);
            } else if (step === 3) {
              h.emit(makeSuccessResult(sid, { stop_reason: "refusal" }));
            } else if (step === 4) {
              // Wait for session/cancel -> onInterrupt finishes turn.
            } else if (step === 5) {
              h.emit({
                ...makeSuccessResult(sid),
                subtype: "error_during_execution",
                is_error: true,
                errors: ["Backend rate exceeded"],
              });
            } else if (step === 6) {
              h.emit({
                type: "assistant",
                message: {
                  id: "msg_auth",
                  type: "message",
                  role: "assistant",
                  model: "<synthetic>",
                  content: [{ type: "text", text: "Please log in" }],
                  stop_reason: null,
                  stop_sequence: null,
                  usage: {
                    input_tokens: 0,
                    output_tokens: 0,
                    cache_read_input_tokens: 0,
                    cache_creation_input_tokens: 0,
                  },
                } as unknown as SDKAssistantMessage["message"],
                parent_tool_use_id: null,
                error: "authentication_failed",
                uuid: UUID_1,
                session_id: sid,
              });
              h.emit(
                makeSuccessResult(sid, {
                  is_error: true,
                  result: "Invalid credentials",
                }),
              );
            }
          },
          onInterrupt: (h) => {
            h.emit(
              makeSuccessResult(sid, {
                terminal_reason: "aborted_streaming",
              }),
            );
          },
        });
        return sdkQuery;
      },
    });

    try {
      await harness.client.request("initialize", {
        protocolVersion: 1,
        clientCapabilities: {},
      });
      await harness.client.request("session/new", {
        cwd: "/repo",
        mcpServers: [],
      });

      expect(
        (
          await harness.client.request("session/prompt", {
            sessionId: sid,
            prompt: [{ type: "text", text: "1" }],
          })
        ).stopReason,
      ).toBe("max_tokens");

      expect(
        (
          await harness.client.request("session/prompt", {
            sessionId: sid,
            prompt: [{ type: "text", text: "2" }],
          })
        ).stopReason,
      ).toBe("max_turn_requests");

      expect(
        (
          await harness.client.request("session/prompt", {
            sessionId: sid,
            prompt: [{ type: "text", text: "3" }],
          })
        ).stopReason,
      ).toBe("refusal");

      const cancelPromptPromise = harness.client.request("session/prompt", {
        sessionId: sid,
        prompt: [{ type: "text", text: "4" }],
      });
      await new Promise((r) => setTimeout(r, 10));
      await harness.client.notify("session/cancel", { sessionId: sid });
      expect((await cancelPromptPromise).stopReason).toBe("cancelled");

      await expect(
        harness.client.request("session/prompt", {
          sessionId: sid,
          prompt: [{ type: "text", text: "5" }],
        }),
      ).rejects.toMatchObject({
        code: -32603,
        message: "Backend rate exceeded",
      });

      await expect(
        harness.client.request("session/prompt", {
          sessionId: sid,
          prompt: [{ type: "text", text: "6" }],
        }),
      ).rejects.toMatchObject({
        code: -32000,
        message: expect.stringContaining("claude auth login"),
      });
    } finally {
      await harness.close();
    }
  });

  test("modes and model changes apply live and bypassPermissions sets allowDangerouslySkipPermissions", async () => {
    const queryHandles: FakeQueryHandle[] = [];
    const harness = createConnectedHarness({
      claudePath: "/usr/local/bin/claude",
      defaultMode: "bypassPermissions",
      queryFn: ({ prompt, options }) => {
        const { sdkQuery, handle } = createFakeQuery({
          options,
          promptInput: prompt,
          models: [
            {
              value: "claude-sonnet-4-5",
              displayName: "Claude Sonnet 4.5",
              description: "Fast",
            },
            {
              value: "claude-opus-4-1",
              displayName: "Claude Opus 4.1",
              description: "Deep",
            },
          ],
        });
        queryHandles.push(handle);
        return sdkQuery;
      },
    });

    try {
      await harness.client.request("initialize", {
        protocolVersion: 1,
        clientCapabilities: {},
      });
      const created = await harness.client.request("session/new", {
        cwd: "/repo",
        mcpServers: [],
      });

      expect(queryHandles[0].options?.permissionMode).toBe("bypassPermissions");
      expect(queryHandles[0].options?.allowDangerouslySkipPermissions).toBe(
        true,
      );

      await harness.client.request("session/set_mode", {
        sessionId: created.sessionId,
        modeId: "acceptEdits",
      });
      expect(queryHandles[0].setPermissionModeCalls).toEqual(["acceptEdits"]);

      const modelConfigRes = await harness.client.request(
        "session/set_config_option",
        {
          sessionId: created.sessionId,
          configId: "model",
          value: "claude-opus-4-1",
        },
      );
      expect(queryHandles[0].setModelCalls).toEqual(["claude-opus-4-1"]);
      expect(modelConfigRes.configOptions).toMatchObject([
        { id: "mode", currentValue: "acceptEdits" },
        { id: "model", currentValue: "claude-opus-4-1" },
      ]);

      const modeConfigRes = await harness.client.request(
        "session/set_config_option",
        {
          sessionId: created.sessionId,
          configId: "mode",
          value: "plan",
        },
      );
      expect(queryHandles[0].setPermissionModeCalls).toEqual([
        "acceptEdits",
        "plan",
      ]);
      expect(modeConfigRes.configOptions).toMatchObject([
        { id: "mode", currentValue: "plan" },
        { id: "model", currentValue: "claude-opus-4-1" },
      ]);

      const updateTypes = harness.receivedUpdates.map(
        (u) => u.update.sessionUpdate,
      );
      expect(updateTypes).toEqual([
        "current_mode_update",
        "config_option_update",
        "config_option_update",
      ]);
    } finally {
      await harness.close();
    }
  });

  test("secrets reach SDK env and MCP config in memory, never argv/stdout/stderr, and sessions before secrets still work", async () => {
    const queryHandles: FakeQueryHandle[] = [];
    const stderrChunks: string[] = [];
    const origStderrWrite = process.stderr.write.bind(process.stderr);
    process.stderr.write = ((chunk: unknown, ...rest: unknown[]) => {
      stderrChunks.push(String(chunk));
      return (origStderrWrite as (...args: unknown[]) => boolean)(
        chunk,
        ...rest,
      );
    }) as typeof process.stderr.write;

    const canaryEnvSecret = "sk-ant-canary-env-99887766";
    const canaryStdioSecret = "stdio-canary-secret-445566"; // gitleaks:allow - test canary value, not a real secret; asserts it never reaches stdout/stderr
    const canaryHttpSecret = "Bearer http-canary-secret-112233";

    const harness = createConnectedHarness({
      claudePath: "/usr/local/bin/claude",
      baseEnv: { PATH: "/usr/bin" },
      queryFn: ({ prompt, options }) => {
        const { sdkQuery, handle } = createFakeQuery({
          options,
          promptInput: prompt,
        });
        queryHandles.push(handle);
        return sdkQuery;
      },
    });

    try {
      await harness.client.request("initialize", {
        protocolVersion: 1,
        clientCapabilities: {},
      });

      // Session opened BEFORE _vitruvian/secrets runs cleanly without secrets.
      await harness.client.request("session/new", {
        cwd: "/repo",
        mcpServers: [],
      });
      expect(queryHandles[0].options?.env?.ANTHROPIC_API_KEY).toBeUndefined();

      const secretsRes = await harness.client.request("_vitruvian/secrets", {
        env: { ANTHROPIC_API_KEY: canaryEnvSecret },
        mcpServers: {
          "local-docs": { env: { DOCS_KEY: canaryStdioSecret } },
          "remote-mcp": { headers: { Authorization: canaryHttpSecret } },
        },
      });
      expect(secretsRes).toEqual({});

      await harness.client.request("session/new", {
        cwd: "/repo",
        mcpServers: [
          {
            name: "local-docs",
            command: "/usr/local/bin/docs-mcp",
            args: ["--stdio"],
            env: [{ name: "DOCS_ROOT", value: "/repo/docs" }],
          },
          {
            type: "http",
            name: "remote-mcp",
            url: "https://mcp.example.com/v1",
            headers: [{ name: "X-Workspace", value: "default" }],
          },
          {
            type: "sse",
            name: "events-mcp",
            url: "https://events.example.com/sse",
            headers: [],
          },
        ],
      });

      const opts = queryHandles[1].options!;
      expect(opts.env?.ANTHROPIC_API_KEY).toBe(canaryEnvSecret);
      expect(opts.mcpServers).toEqual({
        "local-docs": {
          type: "stdio",
          command: "/usr/local/bin/docs-mcp",
          args: ["--stdio"],
          env: {
            DOCS_ROOT: "/repo/docs",
            DOCS_KEY: canaryStdioSecret,
          },
        },
        "remote-mcp": {
          type: "http",
          url: "https://mcp.example.com/v1",
          headers: {
            "X-Workspace": "default",
            Authorization: canaryHttpSecret,
          },
        },
        "events-mcp": {
          type: "sse",
          url: "https://events.example.com/sse",
        },
      });

      const argvString = process.argv.join(" ");
      const extraArgsString = JSON.stringify(opts.extraArgs ?? {});
      const wireOut = harness.receivedRawLines.join("\n");
      const errOut = stderrChunks.join("");

      for (const secret of [
        canaryEnvSecret,
        canaryStdioSecret,
        canaryHttpSecret,
      ]) {
        expect(argvString).not.toContain(secret);
        expect(extraArgsString).not.toContain(secret);
        expect(wireOut).not.toContain(secret);
        expect(errOut).not.toContain(secret);
      }
    } finally {
      process.stderr.write = origStderrWrite;
      await harness.close();
    }
  });

  test("_vitruvian/fork, _vitruvian/mcpStatus, and session/close behave correctly", async () => {
    const queryHandles: FakeQueryHandle[] = [];
    const forkCalls: Array<{ sessionId: string; dir?: string }> = [];
    const forkFn: ForkFn = async (sessionId, options) => {
      forkCalls.push({ sessionId, dir: options?.dir });
      return { sessionId: "forked-session-999" };
    };
    const expectedServers: McpServerStatus[] = [
      {
        name: "local-docs",
        status: "connected",
        serverInfo: { name: "docs-mcp", version: "1.2.0" },
      },
      {
        name: "remote-mcp",
        status: "failed",
        error: "Connection refused",
      },
    ];

    const harness = createConnectedHarness({
      claudePath: "/usr/local/bin/claude",
      forkFn,
      queryFn: ({ prompt, options }) => {
        const { sdkQuery, handle } = createFakeQuery({
          options,
          promptInput: prompt,
          mcpServers: expectedServers,
        });
        queryHandles.push(handle);
        return sdkQuery;
      },
    });

    try {
      await harness.client.request("initialize", {
        protocolVersion: 1,
        clientCapabilities: {},
      });
      const created = await harness.client.request("session/new", {
        cwd: "/repo/work",
        mcpServers: [],
      });

      const statusRes = await harness.client.request("_vitruvian/mcpStatus", {
        sessionId: created.sessionId,
      });
      expect(statusRes).toEqual({ servers: expectedServers });

      const forkRes = await harness.client.request("_vitruvian/fork", {
        sessionId: created.sessionId,
      });
      expect(forkRes).toEqual({ sessionId: "forked-session-999" });
      expect(forkCalls).toEqual([
        { sessionId: created.sessionId, dir: "/repo/work" },
      ]);

      const closeRes = await harness.client.request("session/close", {
        sessionId: created.sessionId,
      });
      expect(closeRes).toEqual({});
      expect(queryHandles[0].closeCalls).toBe(1);

      // Idempotent close and session-not-found on subsequent prompt.
      expect(
        await harness.client.request("session/close", {
          sessionId: created.sessionId,
        }),
      ).toEqual({});
      await expect(
        harness.client.request("session/prompt", {
          sessionId: created.sessionId,
          prompt: [{ type: "text", text: "hi" }],
        }),
      ).rejects.toBeInstanceOf(RequestError);
    } finally {
      await harness.close();
    }
  });

  test("CLI parseArgs parses --claude-path forms and rejects missing or unknown arguments", () => {
    expect(parseArgs(["--claude-path", "/usr/local/bin/claude"])).toEqual({
      claudePath: "/usr/local/bin/claude",
    });
    expect(parseArgs(["--claude-path=/opt/claude"])).toEqual({
      claudePath: "/opt/claude",
    });
    expect(() => parseArgs([])).toThrow("Missing required --claude-path");
    expect(() => parseArgs(["--claude-path"])).toThrow("Missing value");
    expect(() => parseArgs(["--unknown"])).toThrow("Unknown argument");
  });
});
