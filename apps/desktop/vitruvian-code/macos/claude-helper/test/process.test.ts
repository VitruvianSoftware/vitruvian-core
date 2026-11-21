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

import { spawn } from "node:child_process";
import {
  chmodSync,
  existsSync,
  mkdtempSync,
  readFileSync,
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
const DIST_MAIN_JS = join(PACKAGE_ROOT, "dist", "main.js");
const SCHEMA_URI = "https://vitruviansoftware.dev/schemas/claude-helper.json";
const schema = JSON.parse(
  readFileSync(join(PACKAGE_ROOT, "protocol", "schema.json"), "utf8"),
) as Record<string, unknown>;
const ajv = new Ajv2020({ allErrors: true, strict: false });
addFormats(ajv);
ajv.addSchema(schema, SCHEMA_URI);
const validateWireMessage = ajv.getSchema(SCHEMA_URI)!;

async function runInitializeOverStdio(claudePath: string) {
  expect(existsSync(DIST_MAIN_JS)).toBe(true);

  const child = spawn(
    process.execPath,
    [DIST_MAIN_JS, "--claude-path", claudePath],
    {
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
  const stdinStream = Writable.toWeb(child.stdin) as WritableStream<Uint8Array>;

  const clientApp = client({ name: "process-test-client" });
  const conn = clientApp.connect(ndJsonStream(stdinStream, stdoutStream));

  const exitPromise = new Promise<{
    readonly code: number | null;
    readonly signal: NodeJS.Signals | null;
  }>((resolve, reject) => {
    child.once("error", reject);
    child.once("exit", (code, signal) => resolve({ code, signal }));
  });

  try {
    const initResponse = await conn.agent.request("initialize", {
      protocolVersion: 1,
      clientInfo: { name: "VitruvianCode", version: "1.0.0" },
      clientCapabilities: {},
    });

    conn.close();
    if (!child.stdin.destroyed && !child.stdin.writableEnded) {
      child.stdin.end();
    }
    await conn.closed;
    const exit = await exitPromise;

    return {
      initResponse,
      wireMessages,
      stderr: stderrChunks.join(""),
      exit,
    };
  } finally {
    if (child.exitCode === null && child.signalCode === null) {
      child.kill("SIGKILL");
    }
  }
}

describe("dist/main.js process-level stdio", () => {
  const tempDirs: string[] = [];

  function makeTempDir(): string {
    const dir = mkdtempSync(path.join(os.tmpdir(), "claude-helper-proc-"));
    tempDirs.push(dir);
    return dir;
  }

  afterEach(() => {
    while (tempDirs.length > 0) {
      rmSync(tempDirs.pop()!, { recursive: true, force: true });
    }
  });

  test("spawns node dist/main.js --claude-path, completes initialize over stdio, and exits 0 on stdin EOF", async () => {
    const dir = makeTempDir();
    const fakeClaude = path.join(dir, "claude-ok.sh");
    writeFileSync(
      fakeClaude,
      "#!/bin/sh\necho '2.1.45 (Claude Code)'\n",
      "utf8",
    );
    chmodSync(fakeClaude, 0o755);

    const run = await runInitializeOverStdio(fakeClaude);

    expect(run.initResponse.protocolVersion).toBe(1);
    expect(run.initResponse.agentInfo).toEqual({
      name: "vitruvian-claude-helper",
      version: "0.1.0",
    });
    expect(run.initResponse._meta).toEqual({
      vitruvian: {
        claudeVersion: "2.1.45",
        minClaudeVersionForMcpSecrets: "2.1.326",
      },
    });
    expect(run.stderr).toBe("");
    expect(run.exit).toEqual({ code: 0, signal: null });
    expect(run.wireMessages.length).toBeGreaterThanOrEqual(1);
    for (const msg of run.wireMessages) {
      expect(validateWireMessage(msg)).toBe(true);
    }
  });

  test("completes initialize with claudeVersion: null when fake claude --version fails", async () => {
    const dir = makeTempDir();
    const failingClaude = path.join(dir, "claude-fail.sh");
    writeFileSync(failingClaude, "#!/bin/sh\nexit 1\n", "utf8");
    chmodSync(failingClaude, 0o755);

    const run = await runInitializeOverStdio(failingClaude);

    expect(run.initResponse.protocolVersion).toBe(1);
    expect(run.initResponse._meta).toEqual({
      vitruvian: {
        claudeVersion: null,
        minClaudeVersionForMcpSecrets: "2.1.326",
      },
    });
    expect(run.stderr).toBe("");
    expect(run.exit).toEqual({ code: 0, signal: null });
    for (const msg of run.wireMessages) {
      expect(validateWireMessage(msg)).toBe(true);
    }
  });
});
