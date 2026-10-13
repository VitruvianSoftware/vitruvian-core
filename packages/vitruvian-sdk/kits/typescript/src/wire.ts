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

import { fstatSync, readSync, writeSync } from "node:fs";

import {
  type JSONValue,
  readRPCErrorObject,
  type RPCErrorObject,
} from "./generated/messages.js";

/** The longest line either side may write, not counting its line break. */
export const MAX_LINE_BYTES = 1_048_576;

/** What ties an answer to its request. */
export type RPCID = number | string;

/** One JSON-RPC 2.0 message: what one line on the link holds. */
export type RPCMessage =
  | {
      kind: "request";
      id: RPCID;
      method: string;
      params?: { [key: string]: JSONValue };
    }
  | { kind: "notice"; method: string; params?: { [key: string]: JSONValue } }
  | { kind: "result"; id: RPCID; result: JSONValue }
  | { kind: "failure"; id: RPCID | null; error: RPCErrorObject };

function isID(value: unknown): value is RPCID {
  return typeof value === "string" || Number.isInteger(value);
}

function isObject(value: unknown): value is { [key: string]: JSONValue } {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** The message a line holds, by the same rules as the Swift kit; null when it holds none. */
export function messageOf(line: string): RPCMessage | null {
  let value: unknown;
  try {
    value = JSON.parse(line);
  } catch {
    return null;
  }
  if (!isObject(value) || value.jsonrpc !== "2.0") return null;
  if ("method" in value) {
    if (
      "result" in value ||
      "error" in value ||
      typeof value.method !== "string"
    )
      return null;
    if (value.params !== undefined && !isObject(value.params)) return null;
    const params = value.params === undefined ? {} : { params: value.params };
    if (!("id" in value))
      return { kind: "notice", method: value.method, ...params };
    return isID(value.id)
      ? { kind: "request", id: value.id, method: value.method, ...params }
      : null;
  }
  if ("error" in value) {
    if (
      "result" in value ||
      !("id" in value) ||
      (value.id !== null && !isID(value.id))
    )
      return null;
    try {
      return {
        kind: "failure",
        id: value.id as RPCID | null,
        error: readRPCErrorObject(value.error),
      };
    } catch {
      return null;
    }
  }
  if (!isID(value.id) || !("result" in value)) return null;
  return { kind: "result", id: value.id, result: value.result as JSONValue };
}

/** A message as one line, with its line break. */
export function lineOf(message: RPCMessage): string {
  switch (message.kind) {
    case "request":
      return (
        JSON.stringify({
          jsonrpc: "2.0",
          id: message.id,
          method: message.method,
          params: message.params,
        }) + "\n"
      );
    case "notice":
      return (
        JSON.stringify({
          jsonrpc: "2.0",
          method: message.method,
          params: message.params,
        }) + "\n"
      );
    case "result":
      return (
        JSON.stringify({
          jsonrpc: "2.0",
          id: message.id,
          result: message.result,
        }) + "\n"
      );
    case "failure":
      return (
        JSON.stringify({
          jsonrpc: "2.0",
          id: message.id,
          error: message.error,
        }) + "\n"
      );
  }
}

/** What reading the link gave. */
export type Next =
  | { kind: "message"; message: RPCMessage }
  | { kind: "ended" }
  | { kind: "late" };

/** Milliseconds on a clock nobody can set. */
export function now(): number {
  return performance.now();
}

const sleeper = new Int32Array(new SharedArrayBuffer(4));

/** Waits, on this thread, for `milliseconds`. Nothing else runs meanwhile. */
function pause(milliseconds: number): void {
  Atomics.wait(sleeper, 0, 0, Math.max(0, milliseconds));
}

/** Longest wait between two looks at an input that had nothing to read. */
const LONGEST_PAUSE_MS = 20;

/**
 * The link to the app, from the tool's end: messages read from one file
 * descriptor and written to another, a line each.
 *
 * It works on the thread that uses it, synchronously, with `readSync` and
 * `writeSync`, and never gives Node's event loop a turn. That is what lets a
 * handler call the app and have the answer as a value: the call reads the
 * link right there until its answer comes. With `await` in between, the
 * handler would return before the answer, and a tool written as plain
 * statements would no longer be one.
 *
 * Node has no `poll`, so a wait with a time limit is made like this: when the
 * input is a pipe, Node is asked for `process.stdin` once, which puts the pipe
 * in non-blocking mode (libuv does so for any pipe it opens); a read with
 * nothing to read then fails with EAGAIN at once, and the wire pauses a few
 * milliseconds before it looks again, up to 20. Nothing ever reads from
 * `process.stdin` itself. A file never blocks, so it is read as it is.
 */
export class Wire {
  private readonly input: number;
  private readonly output: number;
  private readonly buffer = Buffer.alloc(65_536);
  private pending: Buffer[] = [];
  private pendingBytes = 0;
  private discarding = false;
  private lines: string[] = [];
  private finished = false;

  constructor(input: number, output: number) {
    this.input = input;
    this.output = output;
    if (input === 0) {
      const kind = fstatSync(0);
      if (kind.isFIFO() || kind.isSocket()) void process.stdin;
    }
  }

  /** True once the other side closed the link, or it broke. */
  get ended(): boolean {
    return this.finished;
  }

  /**
   * The next message. With `deadline` null it waits as long as the link is
   * open; otherwise until `deadline` on `now()`. A line that is not a message,
   * and a line over 1 MB, are dropped: there is no request to answer.
   */
  next(deadline: number | null): Next {
    let wait = 1;
    for (;;) {
      while (this.lines.length > 0) {
        const message = messageOf(this.lines.shift() as string);
        if (message !== null) return { kind: "message", message };
      }
      if (this.finished) return { kind: "ended" };
      if (deadline !== null && now() >= deadline) return { kind: "late" };
      let count: number;
      try {
        count = readSync(this.input, this.buffer, 0, this.buffer.length, null);
      } catch (error) {
        const code = (error as NodeJS.ErrnoException).code;
        if (code === "EAGAIN" || code === "EWOULDBLOCK") {
          pause(deadline === null ? wait : Math.min(wait, deadline - now()));
          wait = Math.min(wait * 2, LONGEST_PAUSE_MS);
          continue;
        }
        if (code === "EINTR") continue;
        this.finished = true;
        continue;
      }
      if (count === 0) {
        this.finished = true;
        continue;
      }
      wait = 1;
      this.split(this.buffer.subarray(0, count));
    }
  }

  /** Cuts bytes into lines, as the protocol's LineSplitter does. */
  private split(bytes: Buffer): void {
    let rest = bytes;
    for (let at = rest.indexOf(0x0a); at >= 0; at = rest.indexOf(0x0a)) {
      const head = rest.subarray(0, at);
      rest = rest.subarray(at + 1);
      if (this.discarding) {
        this.discarding = false;
      } else if (this.pendingBytes + head.length <= MAX_LINE_BYTES) {
        const line = Buffer.concat([...this.pending, head]).toString("utf8");
        if (line.trim() !== "") this.lines.push(line);
      }
      this.pending = [];
      this.pendingBytes = 0;
    }
    if (this.discarding) return;
    if (this.pendingBytes + rest.length > MAX_LINE_BYTES) {
      this.discarding = true;
      this.pending = [];
      this.pendingBytes = 0;
      return;
    }
    if (rest.length > 0) {
      this.pending.push(Buffer.from(rest));
      this.pendingBytes += rest.length;
    }
  }

  /** Writes one message as one line. False when it could not be; the link has then ended. */
  send(message: RPCMessage): boolean {
    if (this.finished) return false;
    const bytes = Buffer.from(lineOf(message), "utf8");
    let sent = 0;
    while (sent < bytes.length) {
      try {
        sent += writeSync(this.output, bytes, sent, bytes.length - sent);
      } catch (error) {
        const code = (error as NodeJS.ErrnoException).code;
        if (code === "EAGAIN" || code === "EWOULDBLOCK") {
          pause(1);
          continue;
        }
        if (code === "EINTR") continue;
        this.finished = true;
        return false;
      }
    }
    return true;
  }
}
