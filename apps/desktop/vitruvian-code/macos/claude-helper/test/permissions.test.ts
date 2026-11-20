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
  type AgentConnection,
  type ClientConnection,
  type CreateElicitationRequest,
  type CreateElicitationResponse,
  type RequestPermissionRequest,
  type RequestPermissionResponse,
} from "@agentclientprotocol/sdk";
import type {
  CanUseTool,
  Options as SdkQueryOptions,
  PermissionResult,
  PermissionUpdate,
  Query as SdkQuery,
  SDKMessage,
  SDKResultMessage,
  SDKUserMessage,
} from "@anthropic-ai/claude-agent-sdk";
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";

import {
  createClaudeHelperApp,
  type ClaudeHelperAgentOptions,
  type QueryFn,
} from "../src/agent.js";
import {
  buildAskUserQuestionAnswers,
  buildElicitationRequest,
  buildPermissionOptions,
  toSessionPermissionUpdates,
  buildPermissionRequest,
  CANCELLED_MESSAGE,
  DECLINED_QUESTION_MESSAGE,
  mapElicitationResponse,
  mapPermissionResponse,
  parseAskUserQuestions,
  REJECTED_MESSAGE,
} from "../src/permissions.js";

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

class AsyncQueue<T> {
  private readonly items: T[] = [];
  private readonly waiters: Array<(res: IteratorResult<T>) => void> = [];
  private ended = false;

  push(item: T): void {
    if (this.ended) return;
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
    if (this.ended) {
      return Promise.resolve({ value: undefined as unknown as T, done: true });
    }
    return new Promise((resolve) => this.waiters.push(resolve));
  }
}

function makeSuccessResult(
  sessionId: string,
  overrides?: Partial<Extract<SDKResultMessage, { subtype: "success" }>>,
): SDKResultMessage {
  return {
    type: "result",
    subtype: "success",
    duration_ms: 10,
    duration_api_ms: 5,
    is_error: false,
    num_turns: 1,
    result: "OK",
    stop_reason: "end_turn",
    total_cost_usd: 0,
    usage: {
      input_tokens: 10,
      output_tokens: 5,
      cache_read_input_tokens: 0,
      cache_creation_input_tokens: 0,
    } as unknown as SDKResultMessage["usage"],
    modelUsage: {},
    permission_denials: [],
    uuid: UUID_1,
    session_id: sessionId,
    ...overrides,
  };
}

function createFakeQueryWithCanUseTool(config: {
  readonly options: SdkQueryOptions | undefined;
  readonly promptInput: string | AsyncIterable<SDKUserMessage>;
  readonly onPromptMessage: (
    canUseTool: CanUseTool,
    emit: (msg: SDKMessage) => void,
    options: SdkQueryOptions,
  ) => Promise<void> | void;
  readonly onInterrupt?: (emit: (msg: SDKMessage) => void) => void;
}): {
  readonly sdkQuery: SdkQuery;
  readonly interruptCalls: () => number;
} {
  const outputQueue = new AsyncQueue<SDKMessage>();
  let interrupts = 0;

  if (typeof config.promptInput !== "string") {
    void (async () => {
      for await (const _msg of config.promptInput) {
        void _msg;
        await config.onPromptMessage(
          config.options!.canUseTool!,
          (m) => outputQueue.push(m),
          config.options!,
        );
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
      interrupts += 1;
      config.onInterrupt?.((m) => outputQueue.push(m));
    },
    setPermissionMode: async () => undefined,
    setMcpPermissionModeOverride: async () => ({}),
    setModel: async () => undefined,
    setMaxThinkingTokens: async () => undefined,
    applyFlagSettings: async () => undefined,
    updateSettings: async () => undefined,
    initializationResult: async () =>
      ({}) as Awaited<ReturnType<SdkQuery["initializationResult"]>>,
    reinitialize: async () =>
      ({}) as Awaited<ReturnType<SdkQuery["reinitialize"]>>,
    supportedCommands: async () => [],
    supportedModels: async () => [],
    supportedAgents: async () => [],
    mcpServerStatus: async () => [],
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
    close: () => outputQueue.finish(),
  };

  return { sdkQuery, interruptCalls: () => interrupts };
}

function createHarness(
  options: ClaudeHelperAgentOptions,
  handlers: {
    readonly onPermission?: (
      params: RequestPermissionRequest,
      signal: AbortSignal,
    ) => Promise<RequestPermissionResponse> | RequestPermissionResponse;
    readonly onElicitation?: (
      params: CreateElicitationRequest,
      signal: AbortSignal,
    ) => Promise<CreateElicitationResponse> | CreateElicitationResponse;
  },
): {
  readonly agentConnection: AgentConnection;
  readonly clientConnection: ClientConnection;
  readonly client: ClientConnection["agent"];
  readonly wireMessages: Array<Record<string, unknown>>;
  readonly close: () => Promise<void>;
} {
  const { app } = createClaudeHelperApp(options);
  const wireMessages: Array<Record<string, unknown>> = [];

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
        if (line.trim()) {
          wireMessages.push(JSON.parse(line) as Record<string, unknown>);
        }
      }
      controller.enqueue(chunk);
    },
  });

  const clientApp = client({ name: "permissions-test-client" });
  if (handlers.onPermission) {
    const fn = handlers.onPermission;
    clientApp.onRequest("session/request_permission", (ctx) =>
      fn(ctx.params, ctx.signal),
    );
  }
  if (handlers.onElicitation) {
    const fn = handlers.onElicitation;
    clientApp.onRequest("elicitation/create", (ctx) =>
      fn(ctx.params, ctx.signal),
    );
  }

  const agentConn = app.connect(
    ndJsonStream(agentToClient.writable, clientToAgent.readable),
  );
  const clientConn = clientApp.connect(
    ndJsonStream(
      clientToAgent.writable,
      agentToClient.readable.pipeThrough(wireTap),
    ),
  );

  return {
    agentConnection: agentConn,
    clientConnection: clientConn,
    client: clientConn.agent,
    wireMessages,
    close: async () => {
      clientConn.close();
      agentConn.close();
      await Promise.allSettled([clientConn.closed, agentConn.closed]);
    },
  };
}

describe("permissions and AskUserQuestion", () => {
  test("buildPermissionOptions always offers Always allow this session, as T3 Code does", () => {
    expect(buildPermissionOptions()).toEqual([
      { optionId: "allow_once", name: "Allow", kind: "allow_once" },
      {
        optionId: "allow_always",
        name: "Always allow this session",
        kind: "allow_always",
      },
      { optionId: "reject_once", name: "Reject", kind: "reject_once" },
    ]);
  });

  test("toSessionPermissionUpdates scopes every rule to the session and falls back to a rule for the tool", () => {
    expect(
      toSessionPermissionUpdates("Bash", [
        {
          type: "addRules",
          rules: [{ toolName: "Bash", ruleContent: "git status" }],
          behavior: "allow",
          destination: "userSettings",
        },
        { type: "setMode", mode: "bypassPermissions", destination: "session" },
      ]),
    ).toEqual([
      {
        type: "addRules",
        rules: [{ toolName: "Bash", ruleContent: "git status" }],
        behavior: "allow",
        destination: "session",
      },
    ]);
    for (const none of [undefined, []]) {
      expect(toSessionPermissionUpdates("Edit", none)).toEqual([
        {
          type: "addRules",
          rules: [{ toolName: "Edit" }],
          behavior: "allow",
          destination: "session",
        },
      ]);
    }
  });

  test("maps each permission response option to exact SDK PermissionResult", () => {
    const toolInput = { command: "git status" };
    const suggestions: PermissionUpdate[] = [
      {
        type: "addRules",
        rules: [{ toolName: "Bash", ruleContent: "git status" }],
        behavior: "allow",
        destination: "session",
      },
    ];

    expect(
      mapPermissionResponse(
        { outcome: { outcome: "selected", optionId: "allow_once" } },
        toolInput,
        { toolName: "Bash", suggestions, toolUseID: "tu_1" },
      ),
    ).toEqual({
      behavior: "allow",
      updatedInput: toolInput,
      toolUseID: "tu_1",
    });

    expect(
      mapPermissionResponse(
        { outcome: { outcome: "selected", optionId: "allow_always" } },
        toolInput,
        { toolName: "Bash", suggestions, toolUseID: "tu_2" },
      ),
    ).toEqual({
      behavior: "allow",
      updatedInput: toolInput,
      updatedPermissions: suggestions,
      toolUseID: "tu_2",
    });

    expect(
      mapPermissionResponse(
        { outcome: { outcome: "selected", optionId: "reject_once" } },
        toolInput,
        { toolName: "Bash", suggestions, toolUseID: "tu_3" },
      ),
    ).toEqual({
      behavior: "deny",
      message: REJECTED_MESSAGE,
      toolUseID: "tu_3",
    });

    expect(
      mapPermissionResponse({ outcome: { outcome: "cancelled" } }, toolInput, {
        toolName: "Bash",
        suggestions,
        toolUseID: "tu_4",
      }),
    ).toEqual({
      behavior: "deny",
      message: CANCELLED_MESSAGE,
      interrupt: true,
      toolUseID: "tu_4",
    });

    const req = buildPermissionRequest(
      "s-1",
      "Edit",
      { file_path: "/a.ts" },
      {
        toolUseID: "tu_5",
        suggestions,
      },
    );
    expect(req.toolCall.kind).toBe("edit");
    expect(req.toolCall.locations).toEqual([{ path: "/a.ts" }]);
  });

  test("round-trips permission approvals (allow_once, allow_always, reject_once) over real ACP streams", async () => {
    const sid = "550e8400-e29b-41d4-a716-446655440010";
    const suggestions: PermissionUpdate[] = [
      {
        type: "addRules",
        rules: [{ toolName: "Bash", ruleContent: "ls" }],
        behavior: "allow",
        destination: "session",
      },
    ];
    const observedRequests: RequestPermissionRequest[] = [];
    const observedResults: PermissionResult[] = [];
    let turnIndex = 0;

    const queryFn: QueryFn = ({ prompt, options }) =>
      createFakeQueryWithCanUseTool({
        options,
        promptInput: prompt,
        onPromptMessage: async (canUseTool, emit) => {
          turnIndex += 1;
          const ac = new AbortController();
          if (turnIndex === 1) {
            observedResults.push(
              await canUseTool(
                "Bash",
                { command: "ls" },
                { signal: ac.signal, toolUseID: "toolu_1" },
              ),
            );
          } else if (turnIndex === 2) {
            observedResults.push(
              await canUseTool(
                "Bash",
                { command: "ls" },
                { signal: ac.signal, toolUseID: "toolu_2", suggestions },
              ),
            );
          } else {
            observedResults.push(
              await canUseTool(
                "Bash",
                { command: "rm -rf /tmp/x" },
                { signal: ac.signal, toolUseID: "toolu_3" },
              ),
            );
          }
          emit(makeSuccessResult(sid));
        },
      }).sdkQuery;

    const harness = createHarness(
      {
        claudePath: "/usr/local/bin/claude",
        generateSessionIdFn: () => sid,
        queryFn,
      },
      {
        onPermission: (params) => {
          observedRequests.push(params);
          if (params.toolCall.toolCallId === "toolu_1") {
            return { outcome: { outcome: "selected", optionId: "allow_once" } };
          }
          if (params.toolCall.toolCallId === "toolu_2") {
            return {
              outcome: { outcome: "selected", optionId: "allow_always" },
            };
          }
          return { outcome: { outcome: "selected", optionId: "reject_once" } };
        },
      },
    );

    try {
      await harness.client.request("initialize", {
        protocolVersion: 1,
        clientCapabilities: {},
      });
      await harness.client.request("session/new", {
        cwd: "/repo",
        mcpServers: [],
      });

      await harness.client.request("session/prompt", {
        sessionId: sid,
        prompt: [{ type: "text", text: "1" }],
      });
      await harness.client.request("session/prompt", {
        sessionId: sid,
        prompt: [{ type: "text", text: "2" }],
      });
      await harness.client.request("session/prompt", {
        sessionId: sid,
        prompt: [{ type: "text", text: "3" }],
      });

      // "Always allow this session" is offered on every request, as in T3.
      expect(observedRequests[0].options.map((o) => o.optionId)).toEqual([
        "allow_once",
        "allow_always",
        "reject_once",
      ]);
      expect(observedRequests[1].options.map((o) => o.optionId)).toEqual([
        "allow_once",
        "allow_always",
        "reject_once",
      ]);

      expect(observedResults).toEqual([
        {
          behavior: "allow",
          updatedInput: { command: "ls" },
          toolUseID: "toolu_1",
        },
        {
          behavior: "allow",
          updatedInput: { command: "ls" },
          updatedPermissions: suggestions,
          toolUseID: "toolu_2",
        },
        {
          behavior: "deny",
          message: REJECTED_MESSAGE,
          toolUseID: "toolu_3",
        },
      ]);

      for (const msg of harness.wireMessages) {
        const ok = validateWireMessage(msg);
        if (!ok) {
          throw new Error(
            `Wire message failed schema.json: ${ajv.errorsText(validateWireMessage.errors)}`,
          );
        }
      }
    } finally {
      await harness.close();
    }
  });

  test("allow_always drops setMode suggestions while preserving addRules", async () => {
    const setModeSuggestion: PermissionUpdate = {
      type: "setMode",
      mode: "acceptEdits",
      destination: "session",
    };
    const addRulesSuggestion: PermissionUpdate = {
      type: "addRules",
      rules: [{ toolName: "Bash", ruleContent: "git status" }],
      behavior: "allow",
      destination: "session",
    };

    // Only a setMode suggestion: it is dropped, and the session rule for the
    // tool itself is used instead (T3 toSessionPermissionUpdates).
    expect(
      mapPermissionResponse(
        { outcome: { outcome: "selected", optionId: "allow_always" } },
        { command: "git status" },
        {
          toolName: "Bash",
          suggestions: [setModeSuggestion],
          toolUseID: "tu_only_setmode",
        },
      ),
    ).toEqual({
      behavior: "allow",
      updatedInput: { command: "git status" },
      updatedPermissions: [
        {
          type: "addRules",
          rules: [{ toolName: "Bash" }],
          behavior: "allow",
          destination: "session",
        },
      ],
      toolUseID: "tu_only_setmode",
    });

    const sid = "550e8400-e29b-41d4-a716-446655440019";
    const observedRequests: RequestPermissionRequest[] = [];
    const observedResults: PermissionResult[] = [];

    const queryFn: QueryFn = ({ prompt, options }) =>
      createFakeQueryWithCanUseTool({
        options,
        promptInput: prompt,
        onPromptMessage: async (canUseTool, emit) => {
          const ac = new AbortController();
          observedResults.push(
            await canUseTool(
              "Bash",
              { command: "git status" },
              {
                signal: ac.signal,
                toolUseID: "toolu_drop_setmode",
                suggestions: [setModeSuggestion, addRulesSuggestion],
              },
            ),
          );
          emit(makeSuccessResult(sid));
        },
      }).sdkQuery;

    const harness = createHarness(
      {
        claudePath: "/usr/local/bin/claude",
        generateSessionIdFn: () => sid,
        queryFn,
      },
      {
        onPermission: (params) => {
          observedRequests.push(params);
          return { outcome: { outcome: "selected", optionId: "allow_always" } };
        },
      },
    );

    try {
      await harness.client.request("initialize", {
        protocolVersion: 1,
        clientCapabilities: {},
      });
      await harness.client.request("session/new", {
        cwd: "/repo",
        mcpServers: [],
      });
      await harness.client.request("session/prompt", {
        sessionId: sid,
        prompt: [{ type: "text", text: "check git status" }],
      });

      expect(observedRequests).toHaveLength(1);
      expect(observedRequests[0].options.map((o) => o.optionId)).toEqual([
        "allow_once",
        "allow_always",
        "reject_once",
      ]);
      expect(observedResults).toEqual([
        {
          behavior: "allow",
          updatedInput: { command: "git status" },
          updatedPermissions: [addRulesSuggestion],
          toolUseID: "toolu_drop_setmode",
        },
      ]);
      const result = observedResults[0];
      expect(result.behavior).toBe("allow");
      if (result.behavior === "allow") {
        expect(
          result.updatedPermissions?.some((u) => u.type === "setMode") ?? false,
        ).toBe(false);
      }

      for (const msg of harness.wireMessages) {
        const ok = validateWireMessage(msg);
        if (!ok) {
          throw new Error(
            `Wire message failed schema.json: ${ajv.errorsText(validateWireMessage.errors)}`,
          );
        }
      }
    } finally {
      await harness.close();
    }
  });

  test("session/cancel resolves pending permission and elicitation as cancelled and stops prompt cancelled", async () => {
    const sid = "550e8400-e29b-41d4-a716-446655440011";
    const observedResults: PermissionResult[] = [];
    let interruptCount = 0;
    let turn = 0;
    let clientSawPendingRequest = 0;

    const queryFn: QueryFn = ({ prompt, options }) => {
      const handle = createFakeQueryWithCanUseTool({
        options,
        promptInput: prompt,
        onPromptMessage: async (canUseTool, emit) => {
          turn += 1;
          const ac = new AbortController();
          if (turn === 1) {
            observedResults.push(
              await canUseTool(
                "Bash",
                { command: "sleep 10" },
                { signal: ac.signal, toolUseID: "toolu_cancel_perm" },
              ),
            );
          } else {
            observedResults.push(
              await canUseTool(
                "AskUserQuestion",
                {
                  questions: [
                    {
                      header: "Env",
                      question: "Which env?",
                      options: [{ label: "staging" }, { label: "prod" }],
                    },
                  ],
                },
                { signal: ac.signal, toolUseID: "toolu_cancel_ask" },
              ),
            );
          }
          emit(makeSuccessResult(sid));
        },
        onInterrupt: () => {
          interruptCount = handle.interruptCalls();
        },
      });
      return handle.sdkQuery;
    };

    const pendingRespond: Array<() => void> = [];
    const harness = createHarness(
      {
        claudePath: "/usr/local/bin/claude",
        generateSessionIdFn: () => sid,
        queryFn,
      },
      {
        onPermission: (_params, signal) => {
          clientSawPendingRequest += 1;
          return new Promise<RequestPermissionResponse>((resolve) => {
            const finish = () => resolve({ outcome: { outcome: "cancelled" } });
            signal.addEventListener("abort", finish, { once: true });
            pendingRespond.push(finish);
          });
        },
        onElicitation: (_params, signal) => {
          clientSawPendingRequest += 1;
          return new Promise<CreateElicitationResponse>((resolve) => {
            const finish = () => resolve({ action: "cancel" });
            signal.addEventListener("abort", finish, { once: true });
            pendingRespond.push(finish);
          });
        },
      },
    );

    try {
      await harness.client.request("initialize", {
        protocolVersion: 1,
        clientCapabilities: { elicitation: { form: {} } },
      });
      await harness.client.request("session/new", {
        cwd: "/repo",
        mcpServers: [],
      });

      // Turn 1: pending permission cancelled via session/cancel
      const p1 = harness.client.request("session/prompt", {
        sessionId: sid,
        prompt: [{ type: "text", text: "run command" }],
      });
      while (clientSawPendingRequest < 1) {
        await new Promise((r) => setTimeout(r, 5));
      }
      await harness.client.notify("session/cancel", { sessionId: sid });
      expect((await p1).stopReason).toBe("cancelled");

      // Turn 2: pending AskUserQuestion elicitation cancelled via session/cancel
      const p2 = harness.client.request("session/prompt", {
        sessionId: sid,
        prompt: [{ type: "text", text: "ask me" }],
      });
      while (clientSawPendingRequest < 2) {
        await new Promise((r) => setTimeout(r, 5));
      }
      await harness.client.notify("session/cancel", { sessionId: sid });
      expect((await p2).stopReason).toBe("cancelled");

      expect(interruptCount).toBe(2);
      expect(observedResults).toEqual([
        {
          behavior: "deny",
          message: CANCELLED_MESSAGE,
          interrupt: true,
          toolUseID: "toolu_cancel_perm",
        },
        {
          behavior: "deny",
          message: CANCELLED_MESSAGE,
          interrupt: true,
          toolUseID: "toolu_cancel_ask",
        },
      ]);
    } finally {
      for (const fn of pendingRespond) fn();
      await harness.close();
    }
  });

  test("AskUserQuestion round-trips single-select, multi-select, decline, and cancel over real ACP streams", async () => {
    const sid = "550e8400-e29b-41d4-a716-446655440012";
    const questionInput: Record<string, unknown> = {
      questions: [
        {
          header: "Database",
          question: "Which database should we configure?",
          multiSelect: false,
          options: [
            { label: "PostgreSQL", description: "Primary relational store" },
            { label: "SQLite", description: "Embedded local database" },
          ],
        },
        {
          header: "Targets",
          question: "Which platforms should be generated?",
          multiSelect: true,
          options: [
            { label: "TypeScript", description: "Node ESM helper" },
            { label: "Swift", description: "macOS ACP client" },
          ],
        },
      ],
    };

    const parsedQuestions = parseAskUserQuestions(questionInput);
    expect(parsedQuestions.map((q) => q.id)).toEqual(["q_0", "q_1"]);
    const builtReq = buildElicitationRequest(sid, parsedQuestions, "toolu_q");
    expect(builtReq.mode).toBe("form");
    expect(
      (
        builtReq as unknown as {
          requestedSchema: {
            properties: Record<string, Record<string, unknown>>;
            required: string[];
          };
        }
      ).requestedSchema,
    ).toEqual({
      type: "object",
      properties: {
        q_0: {
          type: "string",
          title: "Database",
          description: "Which database should we configure?",
          oneOf: [
            {
              const: "PostgreSQL",
              title: "PostgreSQL",
              description: "Primary relational store",
            },
            {
              const: "SQLite",
              title: "SQLite",
              description: "Embedded local database",
            },
          ],
        },
        q_1: {
          type: "array",
          title: "Targets",
          description: "Which platforms should be generated?",
          items: {
            anyOf: [
              {
                const: "TypeScript",
                title: "TypeScript",
                description: "Node ESM helper",
              },
              {
                const: "Swift",
                title: "Swift",
                description: "macOS ACP client",
              },
            ],
          },
        },
      },
      required: ["q_0", "q_1"],
    });
    expect(
      buildAskUserQuestionAnswers(parsedQuestions, {
        q_0: "PostgreSQL",
        q_1: ["TypeScript", "Swift"],
      }),
    ).toEqual({
      "Which database should we configure?": "PostgreSQL",
      "Which platforms should be generated?": "TypeScript, Swift",
    });
    expect(
      mapElicitationResponse(
        { action: "decline" },
        questionInput,
        parsedQuestions,
        "toolu_q",
      ),
    ).toEqual({
      behavior: "deny",
      message: DECLINED_QUESTION_MESSAGE,
      toolUseID: "toolu_q",
    });

    const observedResults: PermissionResult[] = [];
    const seenRequests: CreateElicitationRequest[] = [];
    let callNum = 0;

    const queryFn: QueryFn = ({ prompt, options }) =>
      createFakeQueryWithCanUseTool({
        options,
        promptInput: prompt,
        onPromptMessage: async (canUseTool, emit) => {
          callNum += 1;
          const ac = new AbortController();
          observedResults.push(
            await canUseTool("AskUserQuestion", questionInput, {
              signal: ac.signal,
              toolUseID: `toolu_ask_${callNum}`,
            }),
          );
          emit(makeSuccessResult(sid));
        },
      }).sdkQuery;

    const harness = createHarness(
      {
        claudePath: "/usr/local/bin/claude",
        generateSessionIdFn: () => sid,
        queryFn,
      },
      {
        onElicitation: (params) => {
          seenRequests.push(params);
          if (seenRequests.length === 1) {
            return {
              action: "accept",
              content: {
                q_0: "PostgreSQL",
                q_1: ["TypeScript", "Swift"],
              },
            };
          }
          if (seenRequests.length === 2) {
            return { action: "decline" };
          }
          return { action: "cancel" };
        },
      },
    );

    try {
      await harness.client.request("initialize", {
        protocolVersion: 1,
        clientCapabilities: { elicitation: { form: {} } },
      });
      await harness.client.request("session/new", {
        cwd: "/repo",
        mcpServers: [],
      });

      await harness.client.request("session/prompt", {
        sessionId: sid,
        prompt: [{ type: "text", text: "accept" }],
      });
      await harness.client.request("session/prompt", {
        sessionId: sid,
        prompt: [{ type: "text", text: "decline" }],
      });
      await harness.client.request("session/prompt", {
        sessionId: sid,
        prompt: [{ type: "text", text: "cancel" }],
      });

      expect(observedResults).toEqual([
        {
          behavior: "allow",
          updatedInput: {
            ...questionInput,
            answers: {
              "Which database should we configure?": "PostgreSQL",
              "Which platforms should be generated?": "TypeScript, Swift",
            },
          },
          toolUseID: "toolu_ask_1",
        },
        {
          behavior: "deny",
          message: DECLINED_QUESTION_MESSAGE,
          toolUseID: "toolu_ask_2",
        },
        {
          behavior: "deny",
          message: CANCELLED_MESSAGE,
          interrupt: true,
          toolUseID: "toolu_ask_3",
        },
      ]);

      for (const msg of harness.wireMessages) {
        const ok = validateWireMessage(msg);
        if (!ok) {
          throw new Error(
            `Wire message failed schema.json: ${ajv.errorsText(validateWireMessage.errors)}`,
          );
        }
      }
    } finally {
      await harness.close();
    }
  });
});
