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

import { spawn, spawnSync } from "node:child_process";
import {
  chmodSync,
  copyFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import os from "node:os";
import path, { dirname, join } from "node:path";
import { Readable, Writable } from "node:stream";
import { fileURLToPath } from "node:url";

import { client, ndJsonStream } from "@agentclientprotocol/sdk";
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";

const PACKAGE_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const BUNDLE_MJS = join(PACKAGE_ROOT, "bundle", "claude-helper.mjs");
const PACKAGES_JSON = join(PACKAGE_ROOT, "bundle", "packages.json");
const SCHEMA_URI = "https://vitruviansoftware.dev/schemas/claude-helper.json";
const schema = JSON.parse(
  readFileSync(join(PACKAGE_ROOT, "protocol", "schema.json"), "utf8"),
) as Record<string, unknown>;
const ajv = new Ajv2020({ allErrors: true, strict: false });
addFormats(ajv);
ajv.addSchema(schema, SCHEMA_URI);
const validateWireMessage = ajv.getSchema(SCHEMA_URI)!;
const validateInitializeResult = ajv.getSchema(
  `${SCHEMA_URI}#/$defs/initializeResult`,
)!;

function resolveRealNodeBinary(): string {
  const candidates: string[] = [];
  const nodeEnv = process.env.JS_BINARY__NODE_BINARY;
  if (nodeEnv) {
    candidates.push(nodeEnv);
    for (const base of [
      process.cwd(),
      process.env.JS_BINARY__EXECROOT,
      process.env.JS_BINARY__RUNFILES,
      process.env.JS_BINARY__RUNFILES && process.env.JS_BINARY__WORKSPACE
        ? join(
            process.env.JS_BINARY__RUNFILES,
            process.env.JS_BINARY__WORKSPACE,
          )
        : undefined,
    ]) {
      if (base) {
        candidates.push(path.resolve(base, nodeEnv));
      }
    }
  }
  candidates.push(process.execPath);

  for (const candidate of candidates) {
    if (!existsSync(candidate)) continue;
    const resolved = realpathSync(candidate);
    const header = readFileSync(resolved).subarray(0, 2).toString("utf8");
    if (header !== "#!") {
      return resolved;
    }
  }
  throw new Error(
    `Could not locate real Node binary (JS_BINARY__NODE_BINARY=${JSON.stringify(nodeEnv)}, execPath=${JSON.stringify(process.execPath)})`,
  );
}

describe("bundled claude-helper.mjs isolated load check", () => {
  const tempDirs: string[] = [];

  function makeTempDir(): string {
    const dir = mkdtempSync(path.join(os.tmpdir(), "claude-helper-isolated-"));
    tempDirs.push(dir);
    return dir;
  }

  afterEach(() => {
    while (tempDirs.length > 0) {
      rmSync(tempDirs.pop()!, { recursive: true, force: true });
    }
  });

  test("excludes Claude Agent SDK platform binary packages from bundle and packages.json", () => {
    const manifest = JSON.parse(readFileSync(PACKAGES_JSON, "utf8")) as {
      packages: Array<{ name: string; version: string; license: string }>;
    };
    expect(Array.isArray(manifest.packages)).toBe(true);
    expect(manifest.packages.length).toBeGreaterThanOrEqual(2);
    for (const pkg of manifest.packages) {
      expect(pkg.name).not.toMatch(
        /^@anthropic-ai\/claude-agent-sdk-(darwin|linux|win32)-/,
      );
    }

    const bundleSource = readFileSync(BUNDLE_MJS, "utf8");
    expect(bundleSource).not.toMatch(
      /from\s*["']@anthropic-ai\/claude-agent-sdk-(darwin|linux|win32)-/,
    );
  });

  test("is the same bytes on every machine: no Bazel output path or host config name", () => {
    const bundleSource = readFileSync(BUNDLE_MJS, "utf8");
    // The sandbox path (`bazel-out/<host config>/bin`), and the names of the
    // host configs it carries: `darwin_arm64-fastbuild`, `darwin_x86_64-opt`...
    expect(bundleSource).not.toMatch(/bazel-out/);
    expect(bundleSource).not.toMatch(/execroot/);
    expect(bundleSource).not.toMatch(/darwin_(arm64|x86_64|amd64)/);
    expect(bundleSource).not.toMatch(/-(fastbuild|dbg|opt)\b.*\/bin\//);
    expect(bundleSource).not.toMatch(/^\/\/ (\.\.\/)+/m);
  });

  test("normalize-bundle.mjs keeps the package-relative module path whatever the sandbox depth or host config", () => {
    const dir = makeTempDir();
    const input = join(dir, "in.mjs");
    const output = join(dir, "out.mjs");
    const expected = [
      "// apps/x/src/main.ts",
      "// node_modules/.aspect_rules_js/zod@4.6.7/node_modules/zod/v4/core/util.js",
      "// @__NO_SIDE_EFFECTS__",
      "const a = 1;",
      "",
    ].join("\n");
    for (const config of [
      "darwin_arm64-fastbuild",
      "darwin_x86_64-opt",
      "k8-dbg",
    ]) {
      for (const up of [
        "../../../",
        "../../../../../../../../../../../../../",
      ]) {
        writeFileSync(
          input,
          [
            `// ${up}execroot/_main/bazel-out/${config}/bin/apps/x/src/main.ts`,
            `// ${up}execroot/_main/bazel-out/${config}/bin/node_modules/.aspect_rules_js/zod@4.6.7/node_modules/zod/v4/core/util.js`,
            "// @__NO_SIDE_EFFECTS__",
            "const a = 1;",
            "",
          ].join("\n"),
          "utf8",
        );
        const run = spawnSync(
          resolveRealNodeBinary(),
          [
            join(PACKAGE_ROOT, "scripts", "normalize-bundle.mjs"),
            input,
            output,
          ],
          { encoding: "utf8" },
        );
        expect(run.stderr).toBe("");
        expect(run.status).toBe(0);
        expect(readFileSync(output, "utf8")).toBe(expected);
      }
    }

    // A path it does not know how to shorten must fail the build, not ship.
    writeFileSync(input, "// /Users/someone/execroot/odd/layout.js\n", "utf8");
    const bad = spawnSync(
      resolveRealNodeBinary(),
      [join(PACKAGE_ROOT, "scripts", "normalize-bundle.mjs"), input, output],
      { encoding: "utf8" },
    );
    expect(bad.status).not.toBe(0);
    expect(bad.stderr).toMatch(
      /bazel-out or execroot path is still in the bundle/,
    );

    // A comment the pattern cannot finish on its own line must never run on
    // into the code below it and delete it.
    writeFileSync(
      input,
      '// ../bazel-out/x\nconst a = 1;\nconst b = "usr/bin/env";\n',
      "utf8",
    );
    const crossLine = spawnSync(
      resolveRealNodeBinary(),
      [join(PACKAGE_ROOT, "scripts", "normalize-bundle.mjs"), input, output],
      { encoding: "utf8" },
    );
    expect(crossLine.status).not.toBe(0);
    expect(readFileSync(input, "utf8")).toContain("const a = 1;");
  });

  test("loads in an empty temp folder with only node + claude-helper.mjs and completes ACP initialize", async () => {
    expect(existsSync(BUNDLE_MJS)).toBe(true);

    const tempDir = makeTempDir();

    // Ensure no node_modules exists anywhere in any ancestor of tempDir.
    let cursor = path.resolve(tempDir);
    while (true) {
      expect(existsSync(join(cursor, "node_modules"))).toBe(false);
      const parent = dirname(cursor);
      if (parent === cursor) break;
      cursor = parent;
    }

    const isolatedNode = join(tempDir, "node");
    const isolatedBundle = join(tempDir, "claude-helper.mjs");
    const isolatedHome = join(tempDir, "home");
    const fakeClaude = join(tempDir, "fake-claude.sh");

    copyFileSync(resolveRealNodeBinary(), isolatedNode);
    chmodSync(isolatedNode, 0o755);
    copyFileSync(BUNDLE_MJS, isolatedBundle);
    mkdirSync(isolatedHome, { recursive: true });
    writeFileSync(
      fakeClaude,
      "#!/bin/sh\necho '2.1.326 (Claude Code)'\n",
      "utf8",
    );
    chmodSync(fakeClaude, 0o755);

    const child = spawn(
      isolatedNode,
      [isolatedBundle, "--claude-path", fakeClaude],
      {
        cwd: tempDir,
        env: {
          PATH: "/usr/bin:/bin",
          HOME: isolatedHome,
        },
        stdio: ["pipe", "pipe", "pipe"],
      },
    );

    const stderrChunks: string[] = [];
    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk: string) => {
      stderrChunks.push(chunk);
    });

    const wireMessages: Array<Record<string, unknown>> = [];
    const decoder = new TextDecoder();
    let wireBuffer = "";
    const wireTap = new TransformStream<Uint8Array, Uint8Array>({
      transform(chunk, controller) {
        wireBuffer += decoder.decode(chunk, { stream: true });
        const lines = wireBuffer.split("\n");
        wireBuffer = lines.pop() ?? "";
        for (const line of lines) {
          if (line.trim().length > 0) {
            wireMessages.push(JSON.parse(line) as Record<string, unknown>);
          }
        }
        controller.enqueue(chunk);
      },
    });

    const stdoutStream = (
      Readable.toWeb(child.stdout) as ReadableStream<Uint8Array>
    ).pipeThrough(wireTap);
    const stdinStream = Writable.toWeb(
      child.stdin,
    ) as WritableStream<Uint8Array>;

    const clientApp = client({ name: "isolated-bundle-test" });
    const conn = clientApp.connect(ndJsonStream(stdinStream, stdoutStream));

    const exitPromise = new Promise<{
      readonly code: number | null;
      readonly signal: NodeJS.Signals | null;
    }>((resolve, reject) => {
      child.once("error", reject);
      child.once("exit", (code, signal) => resolve({ code, signal }));
    });

    try {
      const initResponse = await conn.agent
        .request("initialize", {
          protocolVersion: 1,
          clientInfo: { name: "VitruvianCode", version: "1.0.0" },
          clientCapabilities: {},
        })
        .catch(async (err: unknown) => {
          const exit = await Promise.race([
            exitPromise,
            new Promise<null>((resolve) =>
              setTimeout(() => resolve(null), 500),
            ),
          ]);
          throw new Error(
            `initialize failed: ${String(err)}; stderr=${JSON.stringify(stderrChunks.join(""))}; exit=${JSON.stringify(exit)}`,
          );
        });

      conn.close();
      if (!child.stdin.destroyed && !child.stdin.writableEnded) {
        child.stdin.end();
      }
      await conn.closed;
      const exit = await exitPromise;

      expect(validateInitializeResult(initResponse)).toBe(true);
      expect(initResponse.protocolVersion).toBe(1);
      expect(initResponse.agentInfo?.name).toBe("vitruvian-claude-helper");
      expect(initResponse._meta).toEqual({
        vitruvian: {
          claudeVersion: "2.1.326",
          minClaudeVersionForMcpSecrets:
            expect.stringMatching(/^\d+\.\d+\.\d+$/),
        },
      });
      expect(stderrChunks.join("")).toBe("");
      expect(exit).toEqual({ code: 0, signal: null });
      expect(wireMessages.length).toBeGreaterThanOrEqual(1);
      for (const msg of wireMessages) {
        expect(validateWireMessage(msg)).toBe(true);
      }
    } finally {
      if (child.exitCode === null && child.signalCode === null) {
        child.kill("SIGKILL");
      }
    }
  });
});
