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

import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";

type JsonObject = Record<string, unknown>;

const PROTOCOL_DIR = join(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "protocol",
);
const EXAMPLES_DIR = join(PROTOCOL_DIR, "examples");
const SCHEMA_URI = "https://vitruviansoftware.dev/schemas/claude-helper.json";

const schema = JSON.parse(
  readFileSync(join(PROTOCOL_DIR, "schema.json"), "utf8"),
) as JsonObject & { $defs: Record<string, JsonObject> };

const ajv = new Ajv2020({
  allErrors: true,
  strict: false,
});
addFormats(ajv);
ajv.addSchema(schema, SCHEMA_URI);

const validateMessage = ajv.getSchema(SCHEMA_URI)!;

const EXPECTED_DEF_BY_FILE: Record<string, string> = {
  "client-initialize.json": "initializeParams",
  "helper-initialize-result.json": "initializeResult",
  "helper-initialize-result-null-version.json": "initializeResult",
  "client-vitruvian-secrets.json": "vitruvianSecretsParams",
  "helper-vitruvian-secrets-result.json": "emptyResult",
  "client-session-new.json": "sessionNewParams",
  "client-session-new-ollama.json": "sessionNewParams",
  "helper-session-new-result.json": "sessionNewResult",
  "client-session-resume.json": "sessionResumeParams",
  "helper-session-resume-result.json": "sessionResumeResult",
  "client-session-prompt.json": "sessionPromptParams",
  "helper-session-prompt-result.json": "sessionPromptResult",
  "helper-auth-required-error.json": "rpcError",
  "client-session-cancel.json": "sessionCancelParams",
  "client-session-set-mode.json": "sessionSetModeParams",
  "helper-session-set-mode-result.json": "emptyResult",
  "client-session-set-config-option.json": "sessionSetConfigOptionParams",
  "helper-session-set-config-option-result.json":
    "sessionSetConfigOptionResult",
  "client-session-close.json": "sessionCloseParams",
  "helper-session-close-result.json": "emptyResult",
  "client-vitruvian-fork.json": "vitruvianForkParams",
  "helper-vitruvian-fork-result.json": "vitruvianForkResult",
  "client-vitruvian-mcp-status.json": "vitruvianMcpStatusParams",
  "helper-vitruvian-mcp-status-result.json": "vitruvianMcpStatusResult",
  "helper-vitruvian-usage-limit.json": "vitruvianUsageLimitParams",
  "helper-vitruvian-usage-limit-no-reset.json": "vitruvianUsageLimitParams",
  "helper-request-permission.json": "requestPermissionParams",
  "client-request-permission-result.json": "requestPermissionResult",
  "helper-elicitation-create.json": "elicitationCreateParams",
  "client-elicitation-create-result.json": "elicitationCreateResult",
  "helper-update-agent-message-chunk.json": "agentMessageChunkUpdate",
  "helper-update-agent-thought-chunk.json": "agentThoughtChunkUpdate",
  "helper-update-tool-call.json": "toolCallUpdate",
  "helper-update-tool-call-subagent.json": "toolCallUpdate",
  "helper-update-tool-call-child.json": "toolCallUpdate",
  "helper-update-tool-call-update.json": "toolCallDeltaUpdate",
  "helper-update-plan.json": "planUpdate",
  "helper-update-usage-update.json": "usageUpdate",
  "helper-update-available-commands.json": "availableCommandsUpdate",
  "helper-update-current-mode.json": "currentModeUpdate",
  "helper-update-config-option.json": "configOptionUpdate",
};

function isRecord(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function validateAgainstNode(node: JsonObject, value: unknown): boolean {
  if (typeof node.$ref === "string" && node.$ref.startsWith("#/$defs/")) {
    const validator = ajv.getSchema(`${SCHEMA_URI}${node.$ref}`);
    return validator ? validator(value) : false;
  }
  const validator = ajv.compile({
    $schema: schema.$schema,
    ...node,
    $defs: schema.$defs,
  });
  return validator(value);
}

function collectMatchedDefs(
  node: JsonObject,
  value: unknown,
  seenDefs: Set<string>,
): void {
  if (typeof node.$ref === "string" && node.$ref.startsWith("#/$defs/")) {
    const defName = node.$ref.slice("#/$defs/".length);
    const target = schema.$defs[defName];
    if (target && validateAgainstNode(node, value)) {
      seenDefs.add(defName);
      collectMatchedDefs(target, value, seenDefs);
    }
    return;
  }

  if (Array.isArray(node.allOf)) {
    for (const entry of node.allOf) {
      if (!isRecord(entry)) continue;
      if (isRecord(entry.if) && isRecord(entry.then)) {
        if (validateAgainstNode(entry.if, value)) {
          collectMatchedDefs(entry.then, value, seenDefs);
        }
      } else {
        collectMatchedDefs(entry, value, seenDefs);
      }
    }
  }

  for (const branchKey of ["oneOf", "anyOf"] as const) {
    const branches = node[branchKey];
    if (Array.isArray(branches)) {
      for (const branch of branches) {
        if (isRecord(branch) && validateAgainstNode(branch, value)) {
          collectMatchedDefs(branch, value, seenDefs);
        }
      }
    }
  }

  if (isRecord(value)) {
    const props = isRecord(node.properties) ? node.properties : undefined;
    const addl = isRecord(node.additionalProperties)
      ? node.additionalProperties
      : undefined;
    for (const [key, propValue] of Object.entries(value)) {
      const propSchema = props?.[key];
      if (isRecord(propSchema)) {
        collectMatchedDefs(propSchema, propValue, seenDefs);
      } else if (addl) {
        collectMatchedDefs(addl, propValue, seenDefs);
      }
    }
  } else if (Array.isArray(value) && isRecord(node.items)) {
    for (const item of value) {
      collectMatchedDefs(node.items, item, seenDefs);
    }
  }
}

function loadExamples(): Array<{
  readonly file: string;
  readonly payload: JsonObject;
}> {
  const files = readdirSync(EXAMPLES_DIR)
    .filter((f) => f.endsWith(".json"))
    .sort();
  return files.map((file) => ({
    file,
    payload: JSON.parse(
      readFileSync(join(EXAMPLES_DIR, file), "utf8"),
    ) as JsonObject,
  }));
}

describe("claude-helper protocol contract", () => {
  test("schema.json compiles as Draft 2020-12", () => {
    expect(validateMessage).toBeDefined();
    expect(Object.keys(schema.$defs).length).toBeGreaterThan(30);
  });

  test("every example file follows naming convention and validates against schema.json", () => {
    const examples = loadExamples();
    expect(examples.length).toBeGreaterThanOrEqual(40);

    for (const { file, payload } of examples) {
      expect(file).toMatch(/^(client|helper)-[a-z0-9-]+\.json$/);
      const valid = validateMessage(payload);
      if (!valid) {
        throw new Error(
          `Example ${file} failed schema validation: ${ajv.errorsText(validateMessage.errors)}`,
        );
      }
    }
  });

  test("every example validates against its specific payload $def", () => {
    const examples = loadExamples();
    for (const { file, payload } of examples) {
      const targetDef = EXPECTED_DEF_BY_FILE[file];
      expect(targetDef).toBeDefined();

      let targetPayload: unknown;
      if ("params" in payload) {
        const params = payload.params as JsonObject;
        targetPayload =
          payload.method === "session/update" ? params.update : params;
      } else if ("result" in payload) {
        targetPayload = payload.result;
      } else if ("error" in payload) {
        targetPayload = payload.error;
      }

      const defValidator = ajv.getSchema(`${SCHEMA_URI}#/$defs/${targetDef}`);
      expect(defValidator).toBeDefined();
      const ok = defValidator!(targetPayload);
      if (!ok) {
        throw new Error(
          `Example ${file} failed #/$defs/${targetDef}: ${ajv.errorsText(defValidator!.errors)}`,
        );
      }
    }
  });

  test("every $def in schema.json is exercised by at least one example", () => {
    const examples = loadExamples();
    const seenDefs = new Set<string>();

    for (const { payload } of examples) {
      collectMatchedDefs(schema, payload, seenDefs);
    }

    const allDefs = Object.keys(schema.$defs).sort();
    const uncoveredDefs = allDefs.filter((name) => !seenDefs.has(name));
    expect(uncoveredDefs).toEqual([]);
  });

  test("schema.json rejects invalid messages and contract violations", () => {
    const invalidMessages: Array<{
      readonly label: string;
      readonly msg: unknown;
    }> = [
      {
        label: "wrong jsonrpc version",
        msg: { jsonrpc: "1.0", id: 1, result: {} },
      },
      {
        label: "response with both result and error",
        msg: {
          jsonrpc: "2.0",
          id: 1,
          result: {},
          error: { code: -32603, message: "bad" },
        },
      },
      {
        label: "_vitruvian/fork missing sessionId",
        msg: { jsonrpc: "2.0", id: 2, method: "_vitruvian/fork", params: {} },
      },
      {
        label: "_vitruvian/usageLimit invalid ISO-8601 resetsAt",
        msg: {
          jsonrpc: "2.0",
          method: "_vitruvian/usageLimit",
          params: {
            sessionId: "s-1",
            resetsAt: "not-a-timestamp",
            message: "Limit reached",
          },
        },
      },
      {
        label: "initializeResult missing _meta.vitruvian.claudeVersion",
        msg: {
          jsonrpc: "2.0",
          id: 1,
          result: {
            protocolVersion: 1,
            agentInfo: { name: "vitruvian-claude-helper", version: "0.1.0" },
            agentCapabilities: {
              loadSession: false,
              promptCapabilities: { image: true, embeddedContext: true },
              sessionCapabilities: { resume: {}, close: {} },
            },
            authMethods: [],
            _meta: { vitruvian: {} },
          },
        },
      },
      {
        label: "tool_call with invalid kind",
        msg: {
          jsonrpc: "2.0",
          method: "session/update",
          params: {
            sessionId: "s-1",
            update: {
              sessionUpdate: "tool_call",
              toolCallId: "tc-1",
              title: "Unknown",
              kind: "not_a_kind",
              status: "pending",
            },
          },
        },
      },
      {
        label: "available command with leading slash",
        msg: {
          jsonrpc: "2.0",
          method: "session/update",
          params: {
            sessionId: "s-1",
            update: {
              sessionUpdate: "available_commands_update",
              availableCommands: [
                { name: "/review", description: "Should omit leading slash" },
              ],
            },
          },
        },
      },
    ];

    for (const { label, msg } of invalidMessages) {
      expect({ label, valid: validateMessage(msg) }).toEqual({
        label,
        valid: false,
      });
    }
  });
});
