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

import {
  chmodSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import os from "node:os";
import path from "node:path";

import {
  client,
  ndJsonStream,
  type RequestPermissionResponse,
} from "@agentclientprotocol/sdk";
import type {
  McpServerStatus,
  PermissionResult,
  PermissionUpdate,
  Query as SdkQuery,
  SDKResultMessage,
} from "@anthropic-ai/claude-agent-sdk";

import { createClaudeHelperApp, type QueryFn } from "../src/agent.js";
import { parseArgs } from "../src/main.js";
import {
  mapElicitationResponse,
  mapPermissionResponse,
  parseAskUserQuestions,
} from "../src/permissions.js";
import { discoverClaudeSkills } from "../src/skills.js";

const UUID_SEC = "22222222-2222-4222-8222-222222222222";

function makeSuccessResult(sessionId: string): SDKResultMessage {
  return {
    type: "result",
    subtype: "success",
    duration_ms: 5,
    duration_api_ms: 3,
    is_error: false,
    num_turns: 1,
    result: "OK",
    stop_reason: "end_turn",
    total_cost_usd: 0,
    usage: {
      input_tokens: 1,
      output_tokens: 1,
      cache_read_input_tokens: 0,
      cache_creation_input_tokens: 0,
    } as unknown as SDKResultMessage["usage"],
    modelUsage: {},
    permission_denials: [],
    uuid: UUID_SEC,
    session_id: sessionId,
  };
}

describe("claude-helper security regressions", () => {
  const tempDirs: string[] = [];

  function makeTempDir(prefix = "claude-helper-sec-"): string {
    const dir = mkdtempSync(path.join(os.tmpdir(), prefix));
    tempDirs.push(dir);
    return dir;
  }

  afterEach(() => {
    while (tempDirs.length > 0) {
      rmSync(tempDirs.pop()!, { recursive: true, force: true });
    }
  });

  test("MCP server env and headers from _vitruvian/secrets never appear in spawned claude CLI argv", async () => {
    const dir = makeTempDir();
    const argvDumpPath = path.join(dir, "spawned-argv.txt");
    const fakeClaudePath = path.join(dir, "fake-claude.sh");
    writeFileSync(
      fakeClaudePath,
      [
        "#!/bin/sh",
        `if [ "$1" = "--version" ]; then echo "2.1.326 (Claude Code)"; exit 0; fi`,
        `printf '%s\\n' "$@" > "${argvDumpPath}"`,
        "exit 0",
      ].join("\n"),
      "utf8",
    );
    chmodSync(fakeClaudePath, 0o755);

    const mcpEnvCanary = "canary-mcp-stdio-env-value-9001";
    const mcpHeaderCanary = "canary-mcp-http-header-value-9002";

    const { app, helper } = createClaudeHelperApp({
      claudePath: fakeClaudePath,
      baseEnv: { PATH: process.env.PATH ?? "/usr/bin:/bin" },
      supportedModelsTimeoutMs: 20,
    });

    const clientToAgent = new TransformStream<Uint8Array, Uint8Array>();
    const agentToClient = new TransformStream<Uint8Array, Uint8Array>();
    const agentConn = app.connect(
      ndJsonStream(agentToClient.writable, clientToAgent.readable),
    );
    const clientConn = client({ name: "sec-argv-client" }).connect(
      ndJsonStream(clientToAgent.writable, agentToClient.readable),
    );

    try {
      await clientConn.agent.request("initialize", {
        protocolVersion: 1,
        clientCapabilities: {},
      });
      await clientConn.agent.request("_vitruvian/secrets", {
        mcpServers: {
          "stdio-srv": { env: { MCP_AUTH_MARKER: mcpEnvCanary } },
          "http-srv": { headers: { Authorization: mcpHeaderCanary } },
        },
      });
      await clientConn.agent.request("session/new", {
        cwd: dir,
        mcpServers: [
          {
            name: "stdio-srv",
            command: "/usr/bin/true",
            args: [],
            env: [],
          },
          {
            type: "http",
            name: "http-srv",
            url: "https://mcp.example.com/v1",
            headers: [],
          },
        ],
      });

      const deadline = Date.now() + 3_000;
      while (!existsSync(argvDumpPath) && Date.now() < deadline) {
        await new Promise((r) => setTimeout(r, 10));
      }
      expect(existsSync(argvDumpPath)).toBe(true);
      const spawnedArgs = readFileSync(argvDumpPath, "utf8")
        .split("\n")
        .filter((line) => line.length > 0);
      const joinedArgs = spawnedArgs.join(" ");

      expect(spawnedArgs).not.toContain("--mcp-config");
      expect(joinedArgs).not.toContain(mcpEnvCanary);
      expect(joinedArgs).not.toContain(mcpHeaderCanary);
    } finally {
      await helper.closeAllSessions();
      clientConn.close();
      agentConn.close();
      await Promise.allSettled([clientConn.closed, agentConn.closed]);
    }
  });

  test("_vitruvian/mcpStatus strips MCP config secrets and redacts secret values before writing to stdout", async () => {
    const sid = "550e8400-e29b-41d4-a716-446655440091";
    const headerCanary = "canary-mcpstatus-header-7711";
    const envCanary = "canary-mcpstatus-env-7712";

    const statusesWithConfigs: McpServerStatus[] = [
      {
        name: "remote-mcp",
        status: "connected",
        config: {
          type: "http",
          url: "https://mcp.example.com/v1",
          headers: { Authorization: headerCanary },
        },
      },
      {
        name: "local-mcp",
        status: "failed",
        error: `Failed with header ${headerCanary}`,
        config: {
          type: "stdio",
          command: "/usr/local/bin/local-mcp",
          args: [],
          env: { LOCAL_MARKER: envCanary },
        },
      },
    ];

    const queryFn: QueryFn = () =>
      ({
        next: () => new Promise(() => undefined),
        return: async () => ({ value: undefined, done: true }),
        throw: async (e: unknown) => {
          throw e;
        },
        [Symbol.asyncIterator]() {
          return this;
        },
        [Symbol.asyncDispose]: async () => undefined,
        interrupt: async () => undefined,
        setPermissionMode: async () => undefined,
        setModel: async () => undefined,
        supportedModels: async () => [],
        mcpServerStatus: async () => statusesWithConfigs,
        close: () => undefined,
      }) as unknown as SdkQuery;

    const wireLines: string[] = [];
    const decoder = new TextDecoder();
    let wireBuf = "";
    const wireTap = new TransformStream<Uint8Array, Uint8Array>({
      transform(chunk, controller) {
        wireBuf += decoder.decode(chunk, { stream: true });
        const parts = wireBuf.split("\n");
        wireBuf = parts.pop() ?? "";
        for (const line of parts) {
          if (line.trim()) wireLines.push(line);
        }
        controller.enqueue(chunk);
      },
    });

    const { app, helper } = createClaudeHelperApp({
      claudePath: "/usr/local/bin/claude",
      generateSessionIdFn: () => sid,
      queryFn,
    });
    const clientToAgent = new TransformStream<Uint8Array, Uint8Array>();
    const agentToClient = new TransformStream<Uint8Array, Uint8Array>();
    const agentConn = app.connect(
      ndJsonStream(agentToClient.writable, clientToAgent.readable),
    );
    const clientConn = client({ name: "sec-mcpstatus-client" }).connect(
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
      await clientConn.agent.request("_vitruvian/secrets", {
        mcpServers: {
          "remote-mcp": { headers: { Authorization: headerCanary } },
          "local-mcp": { env: { LOCAL_MARKER: envCanary } },
        },
      });
      await clientConn.agent.request("session/new", {
        cwd: "/repo",
        mcpServers: [],
      });
      await clientConn.agent.request("_vitruvian/mcpStatus", {
        sessionId: sid,
      });

      const stdoutText = wireLines.join("\n");
      expect(stdoutText).not.toContain(headerCanary);
      expect(stdoutText).not.toContain(envCanary);
    } finally {
      await helper.closeAllSessions();
      clientConn.close();
      agentConn.close();
      await Promise.allSettled([clientConn.closed, agentConn.closed]);
    }
  });

  test("canUseTool denies malformed elicitation answers and non-selected permission outcomes", () => {
    const toolInput: Record<string, unknown> = {
      questions: [
        {
          header: "Database",
          question: "Which database?",
          multiSelect: false,
          options: [{ label: "PostgreSQL" }, { label: "SQLite" }],
        },
        {
          header: "Platforms",
          question: "Which platforms?",
          multiSelect: true,
          options: [{ label: "macOS" }, { label: "Linux" }],
        },
      ],
    };
    const questions = parseAskUserQuestions(toolInput);

    // Missing content, null content, missing required answers, wrong types, or unknown enum labels must all deny.
    expect(
      mapElicitationResponse({ action: "accept" }, toolInput, questions, "tu1")
        .behavior,
    ).toBe("deny");
    expect(
      mapElicitationResponse(
        { action: "accept", content: null },
        toolInput,
        questions,
        "tu2",
      ).behavior,
    ).toBe("deny");
    expect(
      mapElicitationResponse(
        { action: "accept", content: { q_0: "PostgreSQL" } },
        toolInput,
        questions,
        "tu3",
      ).behavior,
    ).toBe("deny");
    expect(
      mapElicitationResponse(
        {
          action: "accept",
          content: {
            q_0: 123 as unknown as string,
            q_1: ["macOS"],
          },
        },
        toolInput,
        questions,
        "tu4",
      ).behavior,
    ).toBe("deny");
    expect(
      mapElicitationResponse(
        {
          action: "accept",
          content: {
            q_0: "OracleDB",
            q_1: ["macOS"],
          },
        },
        toolInput,
        questions,
        "tu5",
      ).behavior,
    ).toBe("deny");
    expect(
      mapElicitationResponse(
        {
          action: "accept",
          content: {
            q_0: "PostgreSQL",
            q_1: "macOS" as unknown as string[],
          },
        },
        toolInput,
        questions,
        "tu6",
      ).behavior,
    ).toBe("deny");

    // Non-"selected" outcome discriminant with an allow optionId must deny, never allow.
    expect(
      mapPermissionResponse(
        {
          outcome: { outcome: "rejected", optionId: "allow_once" },
        } as unknown as RequestPermissionResponse,
        { command: "ls" },
        { toolUseID: "tu7" },
      ).behavior,
    ).toBe("deny");
  });

  test("ExitPlanMode is denied in canUseTool and allow_always clamps suggestion destinations to session", async () => {
    const sid = "550e8400-e29b-41d4-a716-446655440092";
    const observedResults: PermissionResult[] = [];
    const diskPersistenceSuggestion: PermissionUpdate = {
      type: "addRules",
      rules: [{ toolName: "Bash", ruleContent: "git status" }],
      behavior: "allow",
      destination: "userSettings",
    };

    const queryFn: QueryFn = ({ prompt, options }) => {
      const queue: SDKResultMessage[] = [];
      let waiter: ((r: IteratorResult<SDKResultMessage>) => void) | null = null;
      if (typeof prompt !== "string") {
        void (async () => {
          for await (const _msg of prompt) {
            void _msg;
            const ac = new AbortController();
            observedResults.push(
              await options!.canUseTool!(
                "ExitPlanMode",
                { plan: "1. Step one" },
                { signal: ac.signal, toolUseID: "tu_exit_plan" },
              ),
            );
            observedResults.push(
              await options!.canUseTool!(
                "Bash",
                { command: "git status" },
                {
                  signal: ac.signal,
                  toolUseID: "tu_persist_dest",
                  suggestions: [diskPersistenceSuggestion],
                },
              ),
            );
            const res = makeSuccessResult(sid);
            if (waiter) {
              const w = waiter;
              waiter = null;
              w({ value: res, done: false });
            } else {
              queue.push(res);
            }
          }
        })();
      }
      return {
        next: () =>
          queue.length > 0
            ? Promise.resolve({ value: queue.shift()!, done: false })
            : new Promise((resolve) => {
                waiter = resolve;
              }),
        return: async () => ({ value: undefined, done: true }),
        throw: async (e: unknown) => {
          throw e;
        },
        [Symbol.asyncIterator]() {
          return this;
        },
        [Symbol.asyncDispose]: async () => undefined,
        interrupt: async () => undefined,
        setPermissionMode: async () => undefined,
        setModel: async () => undefined,
        supportedModels: async () => [],
        mcpServerStatus: async () => [],
        close: () => undefined,
      } as unknown as SdkQuery;
    };

    const { app, helper } = createClaudeHelperApp({
      claudePath: "/usr/local/bin/claude",
      defaultMode: "plan",
      generateSessionIdFn: () => sid,
      queryFn,
    });
    const clientToAgent = new TransformStream<Uint8Array, Uint8Array>();
    const agentToClient = new TransformStream<Uint8Array, Uint8Array>();
    const clientApp = client({ name: "sec-plan-client" }).onRequest(
      "session/request_permission",
      (ctx) => {
        const allowAlways = ctx.params.options.find(
          (o) => o.optionId === "allow_always",
        );
        return {
          outcome: {
            outcome: "selected",
            optionId: allowAlways ? "allow_always" : "allow_once",
          },
        };
      },
    );
    const agentConn = app.connect(
      ndJsonStream(agentToClient.writable, clientToAgent.readable),
    );
    const clientConn = clientApp.connect(
      ndJsonStream(clientToAgent.writable, agentToClient.readable),
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
        prompt: [{ type: "text", text: "propose plan" }],
      });

      // ExitPlanMode must be denied so only the app's set_mode/set_config_option changes modes.
      expect(observedResults[0].behavior).toBe("deny");

      // allow_always must clamp destinations to "session" rather than persisting to userSettings on disk.
      expect(observedResults[1].behavior).toBe("allow");
      if (observedResults[1].behavior === "allow") {
        expect(observedResults[1].updatedPermissions).toEqual([
          {
            ...diskPersistenceSuggestion,
            destination: "session",
          },
        ]);
      }
    } finally {
      await helper.closeAllSessions();
      clientConn.close();
      agentConn.close();
      await Promise.allSettled([clientConn.closed, agentConn.closed]);
    }
  });

  test("discoverClaudeSkills rejects escaping symlinks, bounds symlink cycles, and parseArgs requires absolute --claude-path", async () => {
    // --claude-path must reject relative paths / bare binary names to prevent PATH or cwd hijacking.
    expect(() => parseArgs(["--claude-path", "claude"])).toThrow();
    expect(() => parseArgs(["--claude-path", "./claude"])).toThrow();

    const root = makeTempDir();
    const cwd = path.join(root, "workspace");
    const configDir = path.join(root, "config");
    const outsideDir = path.join(root, "outside");

    mkdirSync(path.join(cwd, ".claude", "commands"), { recursive: true });
    mkdirSync(path.join(cwd, ".claude", "skills", "escaped-skill"), {
      recursive: true,
    });
    mkdirSync(outsideDir, { recursive: true });

    // Valid command inside workspace
    writeFileSync(
      path.join(cwd, ".claude", "commands", "ok.md"),
      "---\ndescription: Safe command\n---\nBody\n",
      "utf8",
    );

    // Escaping symlinks in .claude/commands and .claude/skills
    writeFileSync(
      path.join(outsideDir, "secret-doc.md"),
      "---\ndescription: Leaked outside description\n---\n",
      "utf8",
    );
    symlinkSync(
      path.join(outsideDir, "secret-doc.md"),
      path.join(cwd, ".claude", "commands", "leaked-cmd.md"),
    );
    symlinkSync(
      path.join(outsideDir, "secret-doc.md"),
      path.join(cwd, ".claude", "skills", "escaped-skill", "SKILL.md"),
    );

    // Two self-symlinks in .claude/commands creating an O(2^depth) cycle if unguarded
    symlinkSync(".", path.join(cwd, ".claude", "commands", "cycle-a"));
    symlinkSync(".", path.join(cwd, ".claude", "commands", "cycle-b"));

    const discovered = await discoverClaudeSkills({
      cwd,
      configDir,
      homeDir: root,
      env: {},
    });

    expect(discovered).toEqual([{ name: "ok", description: "Safe command" }]);
  });
});
