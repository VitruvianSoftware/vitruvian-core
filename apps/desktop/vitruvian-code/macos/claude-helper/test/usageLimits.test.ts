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

import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path, { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { client, ndJsonStream } from "@agentclientprotocol/sdk";
import type {
  Query as SdkQuery,
  SDKMessage,
  SDKResultMessage,
  SDKUserMessage,
} from "@anthropic-ai/claude-agent-sdk";
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";

import { createClaudeHelperApp } from "../src/agent.js";
import {
  extractUsageLimit,
  isoFromEpochSeconds,
  parseGatewayCooldownResetAt,
  type VitruvianUsageLimitParams,
} from "../src/usageLimits.js";

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

function assertSchemaValidNotification(
  params: VitruvianUsageLimitParams,
): void {
  const envelope = {
    jsonrpc: "2.0",
    method: "_vitruvian/usageLimit",
    params,
  };
  const valid = validateWireMessage(envelope);
  if (!valid) {
    throw new Error(
      `Invalid _vitruvian/usageLimit payload: ${ajv.errorsText(validateWireMessage.errors)}`,
    );
  }
}

describe("usageLimits", () => {
  const tempDirs: string[] = [];

  function makeTempDir(): string {
    const dir = mkdtempSync(path.join(os.tmpdir(), "claude-usage-test-"));
    tempDirs.push(dir);
    return dir;
  }

  afterEach(() => {
    while (tempDirs.length > 0) {
      rmSync(tempDirs.pop()!, { recursive: true, force: true });
    }
  });

  test("extracts _vitruvian/usageLimit from temp-dir JSON fixtures across rate_limit_event, assistant, and result frames", () => {
    const dir = makeTempDir();
    const nowMs = Date.parse("2026-11-20T18:00:00.000Z");
    const resetEpoch = Math.floor(
      Date.parse("2026-11-20T19:00:00.000Z") / 1000,
    );

    const fixturePath = path.join(dir, "usage-limit-fixtures.json");
    writeFileSync(
      fixturePath,
      JSON.stringify({
        rejectedWithReset: {
          type: "rate_limit_event",
          rate_limit_info: {
            status: "rejected",
            rateLimitType: "five_hour",
            resetsAt: resetEpoch,
          },
          uuid: "11111111-1111-4111-8111-111111111111",
          session_id: SESSION_ID,
        },
        rejectedNoReset: {
          type: "rate_limit_event",
          rate_limit_info: {
            status: "rejected",
            rateLimitType: "seven_day",
          },
          uuid: "11111111-1111-4111-8111-111111111112",
          session_id: SESSION_ID,
        },
        overageAllowed: {
          type: "rate_limit_event",
          rate_limit_info: {
            status: "rejected",
            rateLimitType: "five_hour",
            resetsAt: resetEpoch,
            overageStatus: "allowed",
          },
          uuid: "11111111-1111-4111-8111-111111111113",
          session_id: SESSION_ID,
        },
        allowedWarning: {
          type: "rate_limit_event",
          rate_limit_info: {
            status: "allowed_warning",
            rateLimitType: "five_hour",
            utilization: 0.9,
          },
          uuid: "11111111-1111-4111-8111-111111111114",
          session_id: SESSION_ID,
        },
        blockedAssistant: {
          type: "assistant",
          error: "rate_limit",
          api_error_params: {
            rate_limit_info: {
              status: "rejected",
              rateLimitType: "seven_day_sonnet",
              resetsAt: resetEpoch,
            },
          },
          message: {
            id: "msg_rl",
            role: "assistant",
            content: [{ type: "text", text: "7-day Sonnet limit reached." }],
          },
          parent_tool_use_id: null,
          uuid: "11111111-1111-4111-8111-111111111115",
          session_id: SESSION_ID,
        },
        result429: {
          type: "result",
          subtype: "success",
          is_error: true,
          api_error_status: 429,
          terminal_reason: "api_error",
          result: 'API Error: 429 {"type":"error"} (reset after 1h 30m 0s)',
          uuid: "11111111-1111-4111-8111-111111111116",
          session_id: SESSION_ID,
        },
        result503Gateway: {
          type: "result",
          subtype: "success",
          is_error: true,
          api_error_status: 503,
          terminal_reason: "api_error",
          result:
            'API Error: 503 [gateway-1] [429]: {"type":"error","error":{"type":"rate_limit_error","message":"limit"}} (reset after 2m 30s)',
          uuid: "11111111-1111-4111-8111-111111111117",
          session_id: SESSION_ID,
        },
        resultNonLimitError: {
          type: "result",
          subtype: "error_during_execution",
          is_error: true,
          errors: ["Tool failed due to missing file"],
          uuid: "11111111-1111-4111-8111-111111111118",
          session_id: SESSION_ID,
        },
      }),
      "utf8",
    );

    const fixtures = JSON.parse(readFileSync(fixturePath, "utf8")) as Record<
      string,
      unknown
    >;

    const rejected = extractUsageLimit(SESSION_ID, fixtures.rejectedWithReset, {
      nowMs,
    });
    expect(rejected).toEqual({
      sessionId: SESSION_ID,
      resetsAt: "2026-11-20T19:00:00.000Z",
      message: expect.stringContaining("5-hour limit resets in 1h"),
    });
    assertSchemaValidNotification(rejected!);

    const noReset = extractUsageLimit(SESSION_ID, fixtures.rejectedNoReset, {
      nowMs,
    });
    expect(noReset).toEqual({
      sessionId: SESSION_ID,
      resetsAt: null,
      message: expect.stringContaining("Claude usage limit reached"),
    });
    assertSchemaValidNotification(noReset!);

    expect(
      extractUsageLimit(SESSION_ID, fixtures.overageAllowed, { nowMs }),
    ).toBeNull();
    expect(
      extractUsageLimit(SESSION_ID, fixtures.allowedWarning, { nowMs }),
    ).toBeNull();

    const assistantLimit = extractUsageLimit(
      SESSION_ID,
      fixtures.blockedAssistant,
      { nowMs },
    );
    expect(assistantLimit).toEqual({
      sessionId: SESSION_ID,
      resetsAt: "2026-11-20T19:00:00.000Z",
      message: "7-day Sonnet limit reached.",
    });
    assertSchemaValidNotification(assistantLimit!);

    const r429 = extractUsageLimit(SESSION_ID, fixtures.result429, { nowMs });
    expect(r429).toEqual({
      sessionId: SESSION_ID,
      resetsAt: "2026-11-20T19:30:00.000Z",
      message: "Claude API rate limit reached. Try again later.",
    });
    assertSchemaValidNotification(r429!);

    const r503 = extractUsageLimit(SESSION_ID, fixtures.result503Gateway, {
      nowMs,
    });
    expect(r503).toEqual({
      sessionId: SESSION_ID,
      resetsAt: "2026-11-20T18:02:30.000Z",
      message: "Claude API rate limit reached. Try again later.",
    });
    assertSchemaValidNotification(r503!);

    expect(
      extractUsageLimit(SESSION_ID, fixtures.resultNonLimitError, { nowMs }),
    ).toBeNull();
  });

  test("helper timestamp/cooldown parsers handle edge cases", () => {
    expect(isoFromEpochSeconds(0)).toBeNull();
    expect(isoFromEpochSeconds(-10)).toBeNull();
    expect(isoFromEpochSeconds(NaN)).toBeNull();
    expect(isoFromEpochSeconds(1795201200)).toBe("2026-11-20T19:00:00.000Z");

    const now = Date.parse("2026-11-20T18:00:00.000Z");
    expect(parseGatewayCooldownResetAt("(reset after 5m 10s)", now)).toBe(
      "2026-11-20T18:05:10.000Z",
    );
    expect(parseGatewayCooldownResetAt("(reset after 0s)", now)).toBeNull();
  });

  test("agent emits deduplicated _vitruvian/usageLimit notifications over real ACP stream", async () => {
    const receivedLimits: Array<Record<string, unknown>> = [];
    const wireMessages: Array<Record<string, unknown>> = [];
    const sid = SESSION_ID;
    const resetEpoch = Math.floor(
      Date.parse("2026-11-20T19:00:00.000Z") / 1000,
    );

    const { app } = createClaudeHelperApp({
      claudePath: "/usr/local/bin/claude",
      generateSessionIdFn: () => sid,
      queryFn: ({ prompt }) => {
        const queue: SDKMessage[] = [];
        const waiters: Array<(res: IteratorResult<SDKMessage>) => void> = [];
        const push = (msg: SDKMessage) => {
          const w = waiters.shift();
          if (w) w({ value: msg, done: false });
          else queue.push(msg);
        };
        if (typeof prompt !== "string") {
          void (async () => {
            for await (const _m of prompt as AsyncIterable<SDKUserMessage>) {
              void _m;
              // Emit two identical rejected rate_limit_events + one null-reset assistant frame -> deduped to 1.
              push({
                type: "rate_limit_event",
                rate_limit_info: {
                  status: "rejected",
                  rateLimitType: "five_hour",
                  resetsAt: resetEpoch,
                },
                uuid: "11111111-1111-4111-8111-111111111111",
                session_id: sid,
              });
              push({
                type: "rate_limit_event",
                rate_limit_info: {
                  status: "rejected",
                  rateLimitType: "five_hour",
                  resetsAt: resetEpoch,
                },
                uuid: "11111111-1111-4111-8111-111111111112",
                session_id: sid,
              });
              push({
                type: "result",
                subtype: "success",
                duration_ms: 10,
                duration_api_ms: 5,
                is_error: false,
                num_turns: 1,
                result: "Paused",
                stop_reason: "end_turn",
                total_cost_usd: 0,
                usage: {
                  input_tokens: 0,
                  output_tokens: 0,
                  cache_read_input_tokens: 0,
                  cache_creation_input_tokens: 0,
                } as unknown as SDKResultMessage["usage"],
                modelUsage: {},
                permission_denials: [],
                uuid: "11111111-1111-4111-8111-111111111113",
                session_id: sid,
              });
            }
          })();
        }
        return {
          next: () => {
            if (queue.length > 0) {
              return Promise.resolve({ value: queue.shift()!, done: false });
            }
            return new Promise((resolve) => waiters.push(resolve));
          },
          return: async () => ({ value: undefined, done: true }),
          throw: async (err) => {
            throw err;
          },
          [Symbol.asyncIterator]() {
            return this;
          },
          [Symbol.asyncDispose]: async () => undefined,
          interrupt: async () => undefined,
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
          close: () => undefined,
        } as SdkQuery;
      },
    });

    const clientToAgent = new TransformStream<Uint8Array, Uint8Array>();
    const agentToClient = new TransformStream<Uint8Array, Uint8Array>();
    const decoder = new TextDecoder();
    let buffer = "";
    const wireTap = new TransformStream<Uint8Array, Uint8Array>({
      transform(chunk, controller) {
        buffer += decoder.decode(chunk, { stream: true });
        const lines = buffer.split("\n");
        buffer = lines.pop() ?? "";
        for (const line of lines) {
          if (line.trim()) {
            wireMessages.push(JSON.parse(line) as Record<string, unknown>);
          }
        }
        controller.enqueue(chunk);
      },
    });

    const clientApp = client({ name: "usage-test-client" }).onNotification(
      "_vitruvian/usageLimit",
      (raw) => raw as Record<string, unknown>,
      (ctx) => {
        receivedLimits.push(ctx.params);
      },
    );

    const agentConn = app.connect(
      ndJsonStream(agentToClient.writable, clientToAgent.readable),
    );
    const clientConn = clientApp.connect(
      ndJsonStream(
        clientToAgent.writable,
        agentToClient.readable.pipeThrough(wireTap),
      ),
    );

    try {
      await clientConn.agent.request("initialize", {
        protocolVersion: 1,
        clientCapabilities: {},
      });
      await clientConn.agent.request("session/new", {
        cwd: "/repo",
        mcpServers: [],
      });
      await clientConn.agent.request("session/prompt", {
        sessionId: sid,
        prompt: [{ type: "text", text: "hi" }],
      });

      expect(receivedLimits).toHaveLength(1);
      expect(receivedLimits[0]).toEqual({
        sessionId: sid,
        resetsAt: "2026-11-20T19:00:00.000Z",
        message: expect.stringContaining("Claude usage limit reached"),
      });
      for (const msg of wireMessages) {
        expect(validateWireMessage(msg)).toBe(true);
      }
    } finally {
      clientConn.close();
      agentConn.close();
      await Promise.allSettled([clientConn.closed, agentConn.closed]);
    }
  });
});
