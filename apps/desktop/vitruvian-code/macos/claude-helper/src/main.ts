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

import { readFileSync, realpathSync } from "node:fs";
import { isAbsolute, resolve } from "node:path";
import { Readable, Writable } from "node:stream";
import { fileURLToPath } from "node:url";

import { ndJsonStream } from "@agentclientprotocol/sdk";

import { createClaudeHelperApp } from "./agent.js";

export interface ParsedCliArgs {
  readonly claudePath: string;
}

export function parseArgs(argv: readonly string[]): ParsedCliArgs {
  let claudePath = "";
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--claude-path") {
      const next = argv[i + 1];
      if (!next) {
        throw new Error("Missing value for --claude-path");
      }
      claudePath = next;
      i += 1;
    } else if (arg.startsWith("--claude-path=")) {
      claudePath = arg.slice("--claude-path=".length);
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (claudePath.trim().length === 0) {
    throw new Error("Missing required --claude-path argument");
  }
  if (!isAbsolute(claudePath) || claudePath.includes("\0")) {
    throw new Error("--claude-path must be an absolute path");
  }
  return { claudePath };
}

export function readPackageVersion(): string {
  try {
    const raw = readFileSync(
      new URL("../package.json", import.meta.url),
      "utf8",
    );
    const parsed = JSON.parse(raw) as { version?: unknown };
    return typeof parsed.version === "string" && parsed.version.length > 0
      ? parsed.version
      : "0.0.0";
  } catch {
    return "0.0.0";
  }
}

export async function runCli(
  argv: readonly string[] = process.argv.slice(2),
): Promise<void> {
  const { claudePath } = parseArgs(argv);
  const { app, helper } = createClaudeHelperApp({
    claudePath,
    helperVersion: readPackageVersion(),
  });
  const stream = ndJsonStream(
    Writable.toWeb(process.stdout) as WritableStream<Uint8Array>,
    Readable.toWeb(process.stdin) as ReadableStream<Uint8Array>,
  );
  const connection = app.connect(stream);
  try {
    await connection.closed;
  } finally {
    await helper.closeAllSessions();
  }
}

function isDirectCliEntry(): boolean {
  if (typeof process.argv[1] !== "string") {
    return false;
  }
  const entryPath = fileURLToPath(import.meta.url);
  try {
    return realpathSync(process.argv[1]) === realpathSync(entryPath);
  } catch {
    return resolve(process.argv[1]) === entryPath;
  }
}

if (isDirectCliEntry()) {
  runCli().catch((error: unknown) => {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`vitruvian-claude-helper error: ${message}\n`);
    process.exitCode = 1;
  });
}
