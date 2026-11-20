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
  mkdirSync,
  mkdtempSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import os from "node:os";
import path from "node:path";
import { dirname, join } from "node:path";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import {
  client,
  ndJsonStream,
  type SessionNotification,
} from "@agentclientprotocol/sdk";
import type {
  Query as SdkQuery,
  SDKResultMessage,
  SDKSystemMessage,
  SDKUserMessage,
} from "@anthropic-ai/claude-agent-sdk";
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";

import { createClaudeHelperApp } from "../src/agent.js";
import {
  discoverClaudeSkills,
  mergeAvailableCommands,
  parseSkillFrontmatter,
} from "../src/skills.js";

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

function writeFixtureFile(filePath: string, contents: string): void {
  mkdirSync(path.dirname(filePath), { recursive: true });
  writeFileSync(filePath, contents, "utf8");
}

describe("skills discovery and frontmatter parsing", () => {
  const tempDirs: string[] = [];

  function makeTempDir(prefix = "claude-skills-test-"): string {
    const dir = mkdtempSync(path.join(os.tmpdir(), prefix));
    tempDirs.push(dir);
    return dir;
  }

  afterEach(() => {
    while (tempDirs.length > 0) {
      rmSync(tempDirs.pop()!, { recursive: true, force: true });
    }
  });

  test("parses frontmatter including colons, hints, YAML 1.1 booleans, and malformed states", () => {
    expect(parseSkillFrontmatter("# No frontmatter\nhello")).toEqual({
      kind: "missing",
    });

    expect(
      parseSkillFrontmatter(
        [
          "---",
          "name: audit",
          "description: Inspect: everything carefully # inline comment",
          "argument-hint: <target path>",
          "disable-model-invocation: yes",
          "user-invocable: true",
          "---",
          "Body",
        ].join("\n"),
      ),
    ).toEqual({
      kind: "parsed",
      name: "audit",
      description: "Inspect: everything carefully",
      argumentHint: "<target path>",
      userInvocationOnly: true,
    });

    expect(
      parseSkillFrontmatter(
        ["---", "description: Hidden helper", "user-invocable: no", "---"].join(
          "\n",
        ),
      ),
    ).toEqual({
      kind: "parsed",
      description: "Hidden helper",
      userInvocable: false,
    });

    expect(parseSkillFrontmatter("---\n\tbad: indent\n---\n")).toEqual({
      kind: "malformed",
    });
    expect(parseSkillFrontmatter("---\nunclosed: true\n")).toEqual({
      kind: "malformed",
    });
  });

  test("discovers user/project skills and commands with precedence, overrides, and malformed filtering", async () => {
    const root = makeTempDir();
    const homeDir = path.join(root, "home");
    const configDir = path.join(root, "config");
    const cwd = path.join(root, "workspace");
    const extraDir = path.join(root, "extra");

    // User skill + user command
    writeFixtureFile(
      path.join(configDir, "skills", "review", "SKILL.md"),
      [
        "---",
        "description: User review: full checklist",
        "argument-hint: <pr-number>",
        "---",
        "Instructions",
      ].join("\n"),
    );
    writeFixtureFile(
      path.join(configDir, "commands", "deploy", "prod.md"),
      [
        "---",
        "description: Deploy production release",
        "argument-hint: <tag>",
        "disable-model-invocation: true",
        "---",
        "Deploy",
      ].join("\n"),
    );

    // Project skill colliding with user skill `review` (user must win) + project-only + hidden + malformed
    writeFixtureFile(
      path.join(cwd, ".claude", "skills", "review", "SKILL.md"),
      ["---", "description: Project review (shadowed)", "---"].join("\n"),
    );
    writeFixtureFile(
      path.join(cwd, ".claude", "skills", "local-fix", "SKILL.md"),
      ["---", "description: Fix local issue", "---"].join("\n"),
    );
    writeFixtureFile(
      path.join(cwd, ".claude", "skills", "internal-only", "SKILL.md"),
      [
        "---",
        "description: Model-only skill",
        "user-invocable: false",
        "---",
      ].join("\n"),
    );
    writeFixtureFile(
      path.join(cwd, ".claude", "skills", "broken-yaml", "SKILL.md"),
      ["---", "not valid yaml line", "---"].join("\n"),
    );
    writeFixtureFile(
      path.join(cwd, ".claude", "skills", "muted-skill", "SKILL.md"),
      ["---", "description: Disabled via override", "---"].join("\n"),
    );

    // Additional directory skill
    writeFixtureFile(
      path.join(extraDir, ".claude", "skills", "shared-lint", "SKILL.md"),
      ["---", "description: Shared lint check", "---"].join("\n"),
    );

    // Lenient JSON settings with comments, trailing commas, and skillOverrides
    writeFixtureFile(
      path.join(cwd, ".claude", "settings.json"),
      `{
        // disable muted-skill
        "skillOverrides": {
          "muted-skill": "off",
        },
        "enabledPlugins": {
          "toolkit@marketplace": true,
        },
      }`,
    );

    // Enabled plugin with valid skills + escaping symlink that must be ignored
    const pluginDir = path.join(root, "plugin-cache", "toolkit");
    const outsideDir = path.join(root, "outside-secret-skills");
    writeFixtureFile(
      path.join(pluginDir, ".claude-plugin", "plugin.json"),
      JSON.stringify({
        name: "toolkit",
        skills: ["./custom-skills", "./escaped-skills"],
      }),
    );
    writeFixtureFile(
      path.join(pluginDir, "skills", "scan", "SKILL.md"),
      ["---", "description: Plugin security scan", "---"].join("\n"),
    );
    writeFixtureFile(
      path.join(pluginDir, "custom-skills", "bench", "SKILL.md"),
      ["---", "description: Custom benchmark", "---"].join("\n"),
    );
    writeFixtureFile(
      path.join(outsideDir, "steal", "SKILL.md"),
      ["---", "description: Should never load", "---"].join("\n"),
    );
    symlinkSync(outsideDir, path.join(pluginDir, "escaped-skills"));

    writeFixtureFile(
      path.join(configDir, "plugins", "installed_plugins.json"),
      JSON.stringify({
        plugins: {
          "toolkit@marketplace": [
            {
              scope: "user",
              installPath: pluginDir,
            },
          ],
        },
      }),
    );

    const discovered = await discoverClaudeSkills({
      cwd,
      configDir,
      homeDir,
      additionalDirectories: [extraDir],
      env: {},
    });

    expect(discovered).toEqual([
      {
        name: "deploy:prod",
        description: "Deploy production release",
        input: { hint: "<tag>" },
      },
      {
        name: "local-fix",
        description: "Fix local issue",
      },
      {
        name: "review",
        description: "User review: full checklist",
        input: { hint: "<pr-number>" },
      },
      {
        name: "shared-lint",
        description: "Shared lint check",
      },
      {
        name: "toolkit:bench",
        description: "Custom benchmark",
      },
      {
        name: "toolkit:scan",
        description: "Plugin security scan",
      },
    ]);
  });

  test("drops all skillOverrides in a settings file when any entry has an unknown value", async () => {
    const root = makeTempDir();
    const configDir = path.join(root, "config");
    const cwd = path.join(root, "workspace");

    writeFixtureFile(
      path.join(cwd, ".claude", "skills", "alpha", "SKILL.md"),
      ["---", "description: Alpha skill", "---"].join("\n"),
    );
    writeFixtureFile(
      path.join(cwd, ".claude", "settings.json"),
      JSON.stringify({
        skillOverrides: {
          alpha: "off",
          bogus: "invalid-mode",
        },
      }),
    );

    const discovered = await discoverClaudeSkills({
      cwd,
      configDir,
      homeDir: root,
      env: {},
    });
    expect(discovered.map((c) => c.name)).toEqual(["alpha"]);
  });

  test("returns empty array when skill directories do not exist", async () => {
    const root = makeTempDir();
    const discovered = await discoverClaudeSkills({
      cwd: path.join(root, "missing-cwd"),
      configDir: path.join(root, "missing-config"),
      homeDir: root,
      env: {},
    });
    expect(discovered).toEqual([]);
  });

  test("mergeAvailableCommands strips leading slash, deduplicates, and enriches from disk", () => {
    expect(
      mergeAvailableCommands(
        ["/compact", "review", "/Review", ""],
        [
          {
            name: "/review",
            description: "Review local diff",
            input: { hint: "<base>" },
          },
          {
            name: "deploy:prod",
            description: "Deploy release",
          },
        ],
      ),
    ).toEqual([
      { name: "compact", description: "" },
      {
        name: "review",
        description: "Review local diff",
        input: { hint: "<base>" },
      },
      { name: "deploy:prod", description: "Deploy release" },
    ]);
  });

  test("agent system/init discovers disk skills from temp dir and emits schema-valid available_commands_update", async () => {
    const root = makeTempDir();
    const configDir = path.join(root, "claude-config");
    const cwd = path.join(root, "project");
    writeFixtureFile(
      path.join(cwd, ".claude", "skills", "ship", "SKILL.md"),
      [
        "---",
        "description: Ship verified build",
        "argument-hint: <env>",
        "---",
      ].join("\n"),
    );

    const sid = "550e8400-e29b-41d4-a716-446655440077";
    const updates: SessionNotification[] = [];
    const wireMessages: Array<Record<string, unknown>> = [];

    const { app } = createClaudeHelperApp({
      claudePath: "/usr/local/bin/claude",
      baseEnv: { PATH: "/usr/bin", CLAUDE_CONFIG_DIR: configDir },
      generateSessionIdFn: () => sid,
      queryFn: ({ prompt }) => {
        const frames: Array<SDKSystemMessage | SDKResultMessage> = [];
        let emitted = false;
        if (typeof prompt !== "string") {
          void (async () => {
            for await (const _msg of prompt) {
              void _msg;
            }
          })();
        }
        return {
          async next() {
            if (!emitted) {
              emitted = true;
              return {
                value: {
                  type: "system",
                  subtype: "init",
                  apiKeySource: "none",
                  claude_code_version: "2.1.45",
                  cwd,
                  tools: ["Read"],
                  mcp_servers: [],
                  model: "claude-sonnet-4-5",
                  permissionMode: "default",
                  slash_commands: ["/compact", "/ship"],
                  output_style: "default",
                  skills: [],
                  plugins: [],
                  uuid: "11111111-1111-4111-8111-111111111111",
                  session_id: sid,
                } satisfies SDKSystemMessage,
                done: false,
              };
            }
            if (frames.length === 0) {
              return new Promise(() => {
                // Keep live query open until closed.
              });
            }
            return { value: frames.shift()!, done: false };
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
          streamInput: async (_input: AsyncIterable<SDKUserMessage>) =>
            undefined,
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

    const clientApp = client({ name: "skills-test-client" }).onNotification(
      "session/update",
      (ctx) => {
        updates.push(ctx.params);
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
        cwd,
        mcpServers: [],
      });

      // Poll instead of a fixed wait: the update arrives after session/new
      // replies, and how long that takes depends on the machine's load.
      const deadline = Date.now() + 5000;
      const findCmdUpdate = () =>
        updates.find(
          (u) => u.update.sessionUpdate === "available_commands_update",
        );
      while (!findCmdUpdate() && Date.now() < deadline) {
        await new Promise((r) => setTimeout(r, 5));
      }
      const cmdUpdate = findCmdUpdate();
      expect(cmdUpdate).toEqual({
        sessionId: sid,
        update: {
          sessionUpdate: "available_commands_update",
          availableCommands: [
            { name: "compact", description: "" },
            {
              name: "ship",
              description: "Ship verified build",
              input: { hint: "<env>" },
            },
          ],
        },
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
