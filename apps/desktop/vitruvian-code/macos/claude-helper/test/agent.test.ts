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
  MAX_OPEN_SESSIONS,
  MCP_INITIALIZE_MIN_CLAUDE_VERSION,
  compareClaudeVersions,
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

function withTimeout<T>(
  promise: Promise<T>,
  ms: number,
  label: string,
): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeoutPromise = new Promise<never>((_resolve, reject) => {
    timer = setTimeout(() => {
      reject(new Error(`Timed out after ${ms}ms waiting for ${label}`));
    }, ms);
    timer.unref?.();
  });
  return Promise.race([promise, timeoutPromise]).finally(() => {
    if (timer !== undefined) {
      clearTimeout(timer);
    }
  });
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
  readonly onInterrupt?: (handle: FakeQueryHandle) => void | Promise<void>;
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
      await config.onInterrupt?.(handle);
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
  // Hermetic by default: never run a real `claude --version`. The default is
  // the oldest claude that takes MCP servers over stdin.
  const { app } = createClaudeHelperApp({
    detectVersionFn: async () => "2.1.326",
    ...options,
  });
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
      expect(res._meta).toEqual({
        vitruvian: {
          claudeVersion: "2.1.45",
          minClaudeVersionForMcpSecrets: "2.1.326",
        },
      });
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
      expect(res._meta).toEqual({
        vitruvian: {
          claudeVersion: null,
          minClaudeVersionForMcpSecrets: "2.1.326",
        },
      });
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
      // Cancel once the fourth prompt has reached the SDK, not after a fixed wait.
      const cancelDeadline = Date.now() + 5000;
      while (step < 4 && Date.now() < cancelDeadline) {
        await new Promise((r) => setTimeout(r, 5));
      }
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
        "current_mode_update",
        "config_option_update",
      ]);
      expect(harness.receivedUpdates[0].update).toEqual({
        sessionUpdate: "current_mode_update",
        currentModeId: "acceptEdits",
      });
      expect(harness.receivedUpdates[1].update).toMatchObject({
        sessionUpdate: "config_option_update",
        configOptions: expect.arrayContaining([
          expect.objectContaining({ id: "mode", currentValue: "acceptEdits" }),
        ]),
      });
      expect(harness.receivedUpdates[3].update).toEqual({
        sessionUpdate: "current_mode_update",
        currentModeId: "plan",
      });
      expect(harness.receivedUpdates[4].update).toMatchObject({
        sessionUpdate: "config_option_update",
        configOptions: expect.arrayContaining([
          expect.objectContaining({ id: "mode", currentValue: "plan" }),
        ]),
      });
    } finally {
      await harness.close();
    }
  });

  test("session/set_mode and session/set_config_option(mode) each emit current_mode_update then config_option_update", async () => {
    const harness = createConnectedHarness({
      claudePath: "/usr/local/bin/claude",
      defaultMode: "default",
      queryFn: ({ prompt, options }) =>
        createFakeQuery({
          options,
          promptInput: prompt,
        }).sdkQuery,
    });

    try {
      await harness.client.request("initialize", {
        protocolVersion: 1,
        clientCapabilities: {},
      });
      const created = await harness.client.request("session/new", {
        cwd: "/repo/mode-updates",
        mcpServers: [],
      });

      const beforeSetMode = harness.receivedUpdates.length;
      await harness.client.request("session/set_mode", {
        sessionId: created.sessionId,
        modeId: "acceptEdits",
      });
      const afterSetMode = harness.receivedUpdates.slice(beforeSetMode);
      expect(afterSetMode).toHaveLength(2);
      expect(afterSetMode[0].update).toEqual({
        sessionUpdate: "current_mode_update",
        currentModeId: "acceptEdits",
      });
      expect(afterSetMode[1].update).toMatchObject({
        sessionUpdate: "config_option_update",
        configOptions: expect.arrayContaining([
          expect.objectContaining({ id: "mode", currentValue: "acceptEdits" }),
        ]),
      });

      const beforeSetConfig = harness.receivedUpdates.length;
      await harness.client.request("session/set_config_option", {
        sessionId: created.sessionId,
        configId: "mode",
        value: "plan",
      });
      const afterSetConfig = harness.receivedUpdates.slice(beforeSetConfig);
      expect(afterSetConfig).toHaveLength(2);
      expect(afterSetConfig[0].update).toEqual({
        sessionUpdate: "current_mode_update",
        currentModeId: "plan",
      });
      expect(afterSetConfig[1].update).toMatchObject({
        sessionUpdate: "config_option_update",
        configOptions: expect.arrayContaining([
          expect.objectContaining({ id: "mode", currentValue: "plan" }),
        ]),
      });

      for (const wireMsg of harness.receivedRawMessages) {
        const valid = validateWireMessage(wireMsg);
        if (!valid) {
          throw new Error(
            `Wire message failed schema.json: ${ajv.errorsText(validateWireMessage.errors)}\n${JSON.stringify(wireMsg)}`,
          );
        }
      }
    } finally {
      await harness.close();
    }
  });

  test("_vitruvian/secrets merges env and per-server mcpServers env/headers across calls", async () => {
    const queryHandles: FakeQueryHandle[] = [];
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

      expect(
        await harness.client.request("_vitruvian/secrets", {
          env: { A: "1" },
          mcpServers: {
            S: {
              env: { X: "1" },
              headers: { H: "1" },
            },
          },
        }),
      ).toEqual({});

      expect(
        await harness.client.request("_vitruvian/secrets", {
          env: { B: "2", A: "3" },
          mcpServers: {
            S: {
              env: { Y: "2" },
            },
          },
        }),
      ).toEqual({});

      await harness.client.request("session/new", {
        cwd: "/repo/secrets-stdio",
        mcpServers: [
          {
            name: "S",
            command: "/usr/local/bin/s-mcp",
            args: [],
            env: [],
          },
        ],
      });
      expect(queryHandles[0].options?.env?.A).toBe("3");
      expect(queryHandles[0].options?.env?.B).toBe("2");
      expect(queryHandles[0].options?.mcpServers?.S).toEqual({
        type: "stdio",
        command: "/usr/local/bin/s-mcp",
        args: [],
        env: { X: "1", Y: "2" },
      });

      await harness.client.request("session/new", {
        cwd: "/repo/secrets-http",
        mcpServers: [
          {
            type: "http",
            name: "S",
            url: "https://s.example.com/mcp",
            headers: [],
          },
        ],
      });
      expect(queryHandles[1].options?.env?.A).toBe("3");
      expect(queryHandles[1].options?.env?.B).toBe("2");
      expect(queryHandles[1].options?.mcpServers?.S).toEqual({
        type: "http",
        url: "https://s.example.com/mcp",
        headers: { H: "1" },
      });

      expect(
        await harness.client.request("_vitruvian/secrets", {
          mcpServers: {
            S: { headers: { H2: "2" } },
            T: { env: { Z: "9" } },
          },
        }),
      ).toEqual({});

      await harness.client.request("session/new", {
        cwd: "/repo/secrets-multi",
        mcpServers: [
          {
            type: "http",
            name: "S",
            url: "https://s.example.com/mcp",
            headers: [],
          },
          {
            name: "T",
            command: "/usr/local/bin/t-mcp",
            args: [],
            env: [],
          },
        ],
      });
      expect(queryHandles[2].options?.env?.A).toBe("3");
      expect(queryHandles[2].options?.env?.B).toBe("2");
      expect(queryHandles[2].options?.mcpServers).toEqual({
        S: {
          type: "http",
          url: "https://s.example.com/mcp",
          headers: { H: "1", H2: "2" },
        },
        T: {
          type: "stdio",
          command: "/usr/local/bin/t-mcp",
          args: [],
          env: { Z: "9" },
        },
      });

      const wireOut = harness.receivedRawLines.join("\n");
      for (const secretKey of ["X", "Y", "H", "H2", "Z"]) {
        expect(wireOut).not.toContain(`"${secretKey}"`);
      }
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

  test("session/set_mode live switch from default to bypassPermissions reopens query and switching back does not reopen", async () => {
    const sid = "550e8400-e29b-41d4-a716-446655440010";
    const queryHandles: FakeQueryHandle[] = [];
    const harness = createConnectedHarness({
      claudePath: "/usr/local/bin/claude",
      defaultMode: "default",
      generateSessionIdFn: () => sid,
      queryFn: ({ prompt, options }) => {
        const idx = queryHandles.length;
        const { sdkQuery, handle } = createFakeQuery({
          options,
          promptInput: prompt,
          onPromptMessage: (_msg, h) => {
            if (idx === 1) {
              h.emit(makeSuccessResult(sid));
            }
          },
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
      await harness.client.request("session/new", {
        cwd: "/repo/live-mode",
        mcpServers: [
          {
            name: "docs",
            command: "/usr/local/bin/docs-mcp",
            args: ["--stdio"],
            env: [],
          },
        ],
        additionalDirectories: ["/repo/shared"],
      });

      expect(queryHandles).toHaveLength(1);
      expect(queryHandles[0].options?.sessionId).toBe(sid);
      expect(queryHandles[0].options?.resume).toBeUndefined();
      expect(queryHandles[0].options?.permissionMode).toBe("default");
      expect(
        queryHandles[0].options?.allowDangerouslySkipPermissions,
      ).toBeUndefined();

      const setModeRes = await harness.client.request("session/set_mode", {
        sessionId: sid,
        modeId: "bypassPermissions",
      });
      expect(setModeRes).toEqual({});
      expect(queryHandles).toHaveLength(2);
      expect(queryHandles[0].closeCalls).toBe(1);
      expect(queryHandles[1].options?.resume).toBe(sid);
      expect(queryHandles[1].options?.sessionId).toBeUndefined();
      expect(queryHandles[1].options?.permissionMode).toBe("bypassPermissions");
      expect(queryHandles[1].options?.allowDangerouslySkipPermissions).toBe(
        true,
      );
      expect(queryHandles[1].options?.cwd).toBe("/repo/live-mode");
      expect(queryHandles[1].options?.additionalDirectories).toEqual([
        "/repo/shared",
      ]);
      expect(queryHandles[1].options?.mcpServers).toEqual({
        docs: {
          type: "stdio",
          command: "/usr/local/bin/docs-mcp",
          args: ["--stdio"],
        },
      });
      expect(harness.receivedUpdates).toContainEqual({
        sessionId: sid,
        update: {
          sessionUpdate: "current_mode_update",
          currentModeId: "bypassPermissions",
        },
      });

      const promptRes = await harness.client.request("session/prompt", {
        sessionId: sid,
        prompt: [{ type: "text", text: "after live switch" }],
      });
      expect(promptRes.stopReason).toBe("end_turn");
      expect(queryHandles[0].pushedUserMessages).toHaveLength(0);
      expect(queryHandles[1].pushedUserMessages).toHaveLength(1);

      await harness.client.request("session/set_mode", {
        sessionId: sid,
        modeId: "default",
      });
      expect(queryHandles).toHaveLength(2);
      expect(queryHandles[1].setPermissionModeCalls).toEqual(["default"]);
      const modeUpdates = harness.receivedUpdates.filter(
        (u) => u.update.sessionUpdate === "current_mode_update",
      );
      expect(modeUpdates.at(-1)?.update).toEqual({
        sessionUpdate: "current_mode_update",
        currentModeId: "default",
      });
    } finally {
      await harness.close();
    }
  });

  test("MCP_INITIALIZE_MIN_CLAUDE_VERSION matches the Claude Code bundled with the pinned SDK", () => {
    const sdkPackage = JSON.parse(
      readFileSync(
        join(
          dirname(fileURLToPath(import.meta.url)),
          "../node_modules/@anthropic-ai/claude-agent-sdk/package.json",
        ),
        "utf8",
      ),
    ) as { claudeCodeVersion?: string };
    expect(sdkPackage.claudeCodeVersion).toBe(
      MCP_INITIALIZE_MIN_CLAUDE_VERSION,
    );
    expect(compareClaudeVersions("2.1.326", "2.1.326")).toBe(0);
    expect(compareClaudeVersions("2.1.322", "2.1.326")).toBe(-1);
    expect(compareClaudeVersions("2.10.0", "2.9.99")).toBe(1);
    expect(compareClaudeVersions("2.1.400-beta.1", "2.1.326")).toBe(1);
  });

  test("MCP servers go over stdin on a new enough claude; an older one never gets secrets on its command line", async () => {
    const cases: Array<{
      version: string | null;
      secrets: boolean;
      expect: "initialize" | "argv" | "error";
    }> = [
      { version: "2.1.326", secrets: true, expect: "initialize" },
      { version: "2.2.0", secrets: false, expect: "initialize" },
      { version: "2.1.322", secrets: false, expect: "argv" },
      { version: "2.1.322", secrets: true, expect: "error" },
      { version: null, secrets: true, expect: "error" },
    ];
    for (const c of cases) {
      const sid = "550e8400-e29b-41d4-a716-446655440040";
      const queryHandles: FakeQueryHandle[] = [];
      const harness = createConnectedHarness({
        claudePath: "/usr/local/bin/claude",
        detectVersionFn: async () => c.version,
        generateSessionIdFn: () => sid,
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
        if (c.secrets) {
          await harness.client.request("_vitruvian/secrets", {
            mcpServers: { docs: { env: { DOCS_TOKEN: "secret-value" } } },
          });
        }
        const open = harness.client.request("session/new", {
          cwd: "/repo",
          mcpServers: [
            {
              name: "docs",
              command: "/usr/local/bin/docs-mcp",
              args: [],
              env: [],
            },
          ],
        });
        if (c.expect === "error") {
          await expect(open).rejects.toMatchObject({
            message: expect.stringContaining(
              `Update Claude Code to ${MCP_INITIALIZE_MIN_CLAUDE_VERSION}`,
            ),
          });
          expect(queryHandles).toHaveLength(0);
        } else {
          await open;
          expect(queryHandles[0].options?.mcpServersDelivery).toBe(c.expect);
        }
      } finally {
        await harness.close();
      }
    }
  });

  test("refuses to open more than MAX_OPEN_SESSIONS sessions", async () => {
    let next = 0;
    const harness = createConnectedHarness({
      claudePath: "/usr/local/bin/claude",
      generateSessionIdFn: () =>
        `550e8400-e29b-41d4-a716-${String(next++).padStart(12, "0")}`,
      queryFn: ({ prompt, options }) =>
        createFakeQuery({ options, promptInput: prompt }).sdkQuery,
    });
    try {
      await harness.client.request("initialize", {
        protocolVersion: 1,
        clientCapabilities: {},
      });
      for (let i = 0; i < MAX_OPEN_SESSIONS; i += 1) {
        await harness.client.request("session/new", {
          cwd: "/repo",
          mcpServers: [],
        });
      }
      await expect(
        harness.client.request("session/new", { cwd: "/repo", mcpServers: [] }),
      ).rejects.toMatchObject({
        message: expect.stringContaining("Too many open sessions"),
      });
      // Closing one makes room again.
      await harness.client.request("session/close", {
        sessionId: "550e8400-e29b-41d4-a716-000000000000",
      });
      await harness.client.request("session/new", {
        cwd: "/repo",
        mcpServers: [],
      });
    } finally {
      await harness.close();
    }
  });

  test("switching to bypassPermissions mid-turn waits for the next prompt and reopens with the current secrets", async () => {
    const sid = "550e8400-e29b-41d4-a716-446655440030";
    const queryHandles: FakeQueryHandle[] = [];
    const harness = createConnectedHarness({
      claudePath: "/usr/local/bin/claude",
      defaultMode: "default",
      generateSessionIdFn: () => sid,
      queryFn: ({ prompt, options }) => {
        const idx = queryHandles.length;
        const { sdkQuery, handle } = createFakeQuery({
          options,
          promptInput: prompt,
          onPromptMessage: (_msg, h) => {
            // The first query's turn is finished by hand below; the reopened
            // query finishes each turn at once.
            if (idx === 1) {
              h.emit(makeSuccessResult(sid));
            }
          },
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
      await harness.client.request("session/new", {
        cwd: "/repo/mid-turn",
        mcpServers: [],
      });
      // Secrets sent after the session opened.
      await harness.client.request("_vitruvian/secrets", {
        env: { LATE_API_KEY: "late-value" },
      });

      const running = harness.client.request("session/prompt", {
        sessionId: sid,
        prompt: [{ type: "text", text: "long turn" }],
      });
      const deadline = Date.now() + 5000;
      while (
        queryHandles[0].pushedUserMessages.length < 1 &&
        Date.now() < deadline
      ) {
        await new Promise((r) => setTimeout(r, 5));
      }

      const setModeRes = await harness.client.request("session/set_mode", {
        sessionId: sid,
        modeId: "bypassPermissions",
      });
      expect(setModeRes).toEqual({});
      // The running turn keeps its query: nothing is reopened or closed yet.
      expect(queryHandles).toHaveLength(1);
      expect(queryHandles[0].closeCalls).toBe(0);
      expect(harness.receivedUpdates).toContainEqual({
        sessionId: sid,
        update: {
          sessionUpdate: "current_mode_update",
          currentModeId: "bypassPermissions",
        },
      });

      queryHandles[0].emit(makeSuccessResult(sid));
      expect((await running).stopReason).toBe("end_turn");
      expect(queryHandles).toHaveLength(1);

      const next = await harness.client.request("session/prompt", {
        sessionId: sid,
        prompt: [{ type: "text", text: "next turn" }],
      });
      expect(next.stopReason).toBe("end_turn");
      expect(queryHandles).toHaveLength(2);
      expect(queryHandles[0].closeCalls).toBe(1);
      expect(queryHandles[1].options?.resume).toBe(sid);
      expect(queryHandles[1].options?.permissionMode).toBe("bypassPermissions");
      expect(queryHandles[1].options?.allowDangerouslySkipPermissions).toBe(
        true,
      );
      expect(queryHandles[1].options?.env?.LATE_API_KEY).toBe("late-value");
      expect(queryHandles[1].pushedUserMessages).toHaveLength(1);
    } finally {
      await harness.close();
    }
  });

  test("session/set_config_option live switch from default to bypassPermissions reopens query and switching back does not reopen", async () => {
    const sid = "550e8400-e29b-41d4-a716-446655440011";
    const queryHandles: FakeQueryHandle[] = [];
    const harness = createConnectedHarness({
      claudePath: "/usr/local/bin/claude",
      defaultMode: "default",
      generateSessionIdFn: () => sid,
      queryFn: ({ prompt, options }) => {
        const idx = queryHandles.length;
        const { sdkQuery, handle } = createFakeQuery({
          options,
          promptInput: prompt,
          onPromptMessage: (_msg, h) => {
            if (idx === 1) {
              h.emit(makeSuccessResult(sid));
            }
          },
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
      await harness.client.request("session/new", {
        cwd: "/repo/live-config",
        mcpServers: [],
      });

      const bypassRes = await harness.client.request(
        "session/set_config_option",
        {
          sessionId: sid,
          configId: "mode",
          value: "bypassPermissions",
        },
      );
      expect(bypassRes.configOptions).toMatchObject([
        { id: "mode", currentValue: "bypassPermissions" },
      ]);
      expect(queryHandles).toHaveLength(2);
      expect(queryHandles[0].closeCalls).toBe(1);
      expect(queryHandles[1].options?.resume).toBe(sid);
      expect(queryHandles[1].options?.allowDangerouslySkipPermissions).toBe(
        true,
      );

      const promptRes = await harness.client.request("session/prompt", {
        sessionId: sid,
        prompt: [{ type: "text", text: "after config switch" }],
      });
      expect(promptRes.stopReason).toBe("end_turn");
      expect(queryHandles[0].pushedUserMessages).toHaveLength(0);
      expect(queryHandles[1].pushedUserMessages).toHaveLength(1);

      const backRes = await harness.client.request(
        "session/set_config_option",
        {
          sessionId: sid,
          configId: "mode",
          value: "default",
        },
      );
      expect(backRes.configOptions).toMatchObject([
        { id: "mode", currentValue: "default" },
      ]);
      expect(queryHandles).toHaveLength(2);
      expect(queryHandles[1].setPermissionModeCalls).toEqual(["default"]);
    } finally {
      await harness.close();
    }
  });

  test("marks session dead when SDK query ends while idle, rejects prompt with resume hint, and recovers via session/resume", async () => {
    const sid = "550e8400-e29b-41d4-a716-446655440012";
    const queryHandles: FakeQueryHandle[] = [];
    const harness = createConnectedHarness({
      claudePath: "/usr/local/bin/claude",
      generateSessionIdFn: () => sid,
      queryFn: ({ prompt, options }) => {
        const idx = queryHandles.length;
        const { sdkQuery, handle } = createFakeQuery({
          options,
          promptInput: prompt,
          onPromptMessage: (_msg, h) => {
            if (idx === 1) {
              h.emit(makeSuccessResult(sid));
            }
          },
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
      await harness.client.request("session/new", {
        cwd: "/repo",
        mcpServers: [],
      });

      queryHandles[0].finishOutput();
      await new Promise((r) => setTimeout(r, 15));

      let promptErr: unknown;
      try {
        await withTimeout(
          harness.client.request("session/prompt", {
            sessionId: sid,
            prompt: [{ type: "text", text: "to dead session" }],
          }),
          1500,
          "dead session prompt rejection",
        );
      } catch (err) {
        promptErr = err;
      }
      expect(promptErr).toBeInstanceOf(RequestError);
      expect((promptErr as RequestError).message).toMatch(/ended/i);
      expect((promptErr as RequestError).message).toMatch(/session\/resume/);
      expect(queryHandles[0].pushedUserMessages).toHaveLength(0);

      await harness.client.request("session/resume", {
        sessionId: sid,
        cwd: "/repo",
        mcpServers: [],
      });
      expect(queryHandles).toHaveLength(2);
      expect(queryHandles[1].options?.resume).toBe(sid);

      const resumedPromptRes = await withTimeout(
        harness.client.request("session/prompt", {
          sessionId: sid,
          prompt: [{ type: "text", text: "after resume" }],
        }),
        1500,
        "prompt after resume",
      );
      expect(resumedPromptRes.stopReason).toBe("end_turn");
      expect(queryHandles[1].pushedUserMessages).toHaveLength(1);
    } finally {
      await harness.close();
    }
  });

  test("session/cancel resolves in-flight prompt as cancelled when interrupt rejects and no result arrives", async () => {
    const sid = "550e8400-e29b-41d4-a716-446655440013";
    const queryHandles: FakeQueryHandle[] = [];
    const harness = createConnectedHarness({
      claudePath: "/usr/local/bin/claude",
      generateSessionIdFn: () => sid,
      queryFn: ({ prompt, options }) => {
        const { sdkQuery, handle } = createFakeQuery({
          options,
          promptInput: prompt,
          onInterrupt: async () => {
            throw new Error("interrupt failed");
          },
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
      await harness.client.request("session/new", {
        cwd: "/repo",
        mcpServers: [],
      });

      const promptPromise = harness.client.request("session/prompt", {
        sessionId: sid,
        prompt: [{ type: "text", text: "hang forever" }],
      });

      const deadline = Date.now() + 1000;
      while (
        queryHandles[0].pushedUserMessages.length < 1 &&
        Date.now() < deadline
      ) {
        await new Promise((r) => setTimeout(r, 5));
      }
      expect(queryHandles[0].pushedUserMessages).toHaveLength(1);

      await harness.client.notify("session/cancel", { sessionId: sid });
      const res = await withTimeout(
        promptPromise,
        1500,
        "cancel with rejecting interrupt",
      );
      expect(res.stopReason).toBe("cancelled");
      expect(queryHandles[0].interruptCalls).toBe(1);
    } finally {
      await harness.close();
    }
  });

  test("session/cancel resolves in-flight prompt as cancelled when interrupt resolves and no result arrives", async () => {
    const sid = "550e8400-e29b-41d4-a716-446655440014";
    const queryHandles: FakeQueryHandle[] = [];
    const harness = createConnectedHarness({
      claudePath: "/usr/local/bin/claude",
      generateSessionIdFn: () => sid,
      queryFn: ({ prompt, options }) => {
        const { sdkQuery, handle } = createFakeQuery({
          options,
          promptInput: prompt,
          onInterrupt: () => {
            // Resolves without emitting any SDK result.
          },
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
      await harness.client.request("session/new", {
        cwd: "/repo",
        mcpServers: [],
      });

      const promptPromise = harness.client.request("session/prompt", {
        sessionId: sid,
        prompt: [{ type: "text", text: "silent interrupt" }],
      });

      const deadline = Date.now() + 1000;
      while (
        queryHandles[0].pushedUserMessages.length < 1 &&
        Date.now() < deadline
      ) {
        await new Promise((r) => setTimeout(r, 5));
      }
      expect(queryHandles[0].pushedUserMessages).toHaveLength(1);

      await harness.client.notify("session/cancel", { sessionId: sid });
      const res = await withTimeout(
        promptPromise,
        1500,
        "cancel with silent interrupt",
      );
      expect(res.stopReason).toBe("cancelled");
      expect(queryHandles[0].interruptCalls).toBe(1);
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
