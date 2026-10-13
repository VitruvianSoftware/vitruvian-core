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
  type JSONValue,
  PROTOCOL_VERSIONS,
  readCommandRunParams,
  readInitializeParams,
  readLanguageChangedParams,
  readPreferencesChangedParams,
  readUICloseParams,
  readUIEventParams,
  readUIOpenParams,
  type RPCErrorObject,
} from "./generated/messages.js";
import { type AppCalls, appCalls, METHODS } from "./generated/methods.js";
import {
  bridgeCallOf,
  Panel,
  PanelEvent,
  type PanelHandlers,
  resultOf,
  TOOLS_OWN,
} from "./panels.js";
import { now, type RPCID, type RPCMessage, Wire } from "./wire.js";

/** JSON-RPC's own failure codes. */
export const RPCErrorCode = {
  parseError: -32700,
  invalidRequest: -32600,
  methodNotFound: -32601,
  invalidParams: -32602,
  internalError: -32603,
} as const;

/** Why a request was refused, as the code of its failure. */
export const RefusalCode = {
  /** The app: the service is not listed in the tool's `uses`. */
  notInUses: -32001,
  /** The app: the tool is not installed. */
  notInstalled: -32002,
  /** The app: Vitruvian lacks a macOS permission the service needs. */
  permissionMissing: -32003,
  /** The app: not available right now. */
  unavailable: -32004,
  /** The tool: it would not run the command. */
  commandRefused: -32010,
} as const;

/** A command that will not run. Throw it from a handler; the app is answered with -32010 and `message`. */
export class CommandRefused extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CommandRefused";
  }
}

/** The app answered a call with a failure. `code` says why; `RefusalCode` names the refusals. */
export class Refusal extends Error {
  readonly error: RPCErrorObject;

  constructor(error: RPCErrorObject) {
    super(error.message);
    this.name = "Refusal";
    this.error = error;
  }

  get code(): number {
    return this.error.code;
  }

  get data(): JSONValue | undefined {
    return this.error.data;
  }
}

/** A call to the app that got no answer. */
export class AppUnreachable extends Error {
  /** linkClosed: the app said goodbye or closed the link, or has not said hello. noAnswer: no answer in time. */
  readonly reason: "linkClosed" | "noAnswer";
  readonly seconds: number | undefined;

  constructor(reason: "linkClosed" | "noAnswer", seconds?: number) {
    super(
      reason === "linkClosed"
        ? "the link to the app is closed"
        : `no answer within ${seconds} seconds`,
    );
    this.name = "AppUnreachable";
    this.reason = reason;
    this.seconds = seconds;
  }
}

/**
 * The app, as a handler sees it: one call per message a tool may send, by its
 * name (`app.notify.hud({ icon, message })`, `app.storage.get({ key })`), and
 * what the app said at hello. Any call can be refused: it then throws a
 * `Refusal`. A handler that lets it through has its command answered as refused.
 */
export interface App extends AppCalls {
  /** The language the app is in, as a tag such as `en-US`. */
  readonly language: string;
  /** The folder the tool may keep its own files in; also the folder it is started in. */
  readonly dataFolder: string;
}

export type Handler = (app: App) => void;

export interface ToolOptions {
  /** The tool's own version, as its manifest gives it. */
  version: string;
  /** The link. Leave them out outside a test: the tool reads 0 and writes 1. */
  input?: number;
  output?: number;
}

/**
 * A tool that runs as its own program: its commands, and the loop that reads
 * what the app sends and answers it.
 *
 *     const tool = new Tool({ version: "0.1.0" });
 *     tool.command("hello", (app) => {
 *       app.notify.hud({ icon: "hand.wave", message: "Hello" });
 *     });
 *     tool.run();
 *
 * It works on one thread and never yields to Node's event loop: a handler
 * runs to its end, and a call to the app made inside it reads the link until
 * the answer has come. What the app sends while a handler waits is kept and
 * handled after the handler returns. A handler must not be `async`: the
 * command would be answered before its work was done, so one is refused.
 */
export class Tool {
  readonly version: string;
  /** How long a call to the app waits for its answer, in seconds. */
  answerSeconds = 10;
  /** Called once, after the app has said hello and been answered. */
  onStart?: (app: App) => void;
  /** Called when the person changed a preference: each one's id and value. */
  onPreferencesChanged?: (
    app: App,
    values: { [key: string]: JSONValue },
  ) => void;
  /** Called when the person changed the app's language. */
  onLanguageChanged?: (app: App) => void;

  private languageTag = "en";
  private folder = process.cwd();
  private readonly handlers = new Map<string, Handler>();
  /** The tool's panels, by id, as `panel()` made them. */
  private readonly panels = new Map<string, Panel>();
  private readonly wire: Wire;
  private readonly app: App;
  private lastID = 0;
  private kept: RPCMessage[] = [];
  private greeted = false;
  private stopping = false;

  constructor(options: ToolOptions) {
    this.version = options.version;
    this.wire = new Wire(options.input ?? 0, options.output ?? 1);
    const calls = appCalls(
      (method, params) => this.call(method, params),
      (method, params) => this.note(method, params),
    );
    const tool = this;
    this.app = Object.freeze({
      ...calls,
      get language() {
        return tool.languageTag;
      },
      get dataFolder() {
        return tool.folder;
      },
    });
  }

  /** The language the app is in. */
  get language(): string {
    return this.languageTag;
  }

  /** The folder the tool may keep its own files in. */
  get dataFolder(): string {
    return this.folder;
  }

  /** Says what a command does. `id` is the one the manifest gives it. */
  command(id: string, handler: Handler): this {
    this.handlers.set(id, handler);
    return this;
  }

  /**
   * Says what a panel does. `id` is the one the manifest gives it. `onOpen`
   * gives the first page when the person opens it; a web panel gives none.
   * `onEvent` answers what the person did. The handle it gives back sends
   * pages unprompted and sets the tool's badge.
   */
  panel(id: string, handlers: PanelHandlers): Panel {
    const tool = this;
    const panel = new Panel(
      id,
      {
        get app() {
          return tool.app;
        },
        note: (method, params) => tool.note(method, params),
      },
      handlers,
    );
    this.panels.set(id, panel);
    return panel;
  }

  /** Reads and answers until the app says goodbye, then exits with 0. */
  run(): never {
    process.exit(this.serve());
  }

  /** Reads and answers until the app says goodbye or the link ends. Returns 0, the status to exit with. */
  serve(): number {
    while (!this.stopping) {
      const waiting = this.kept.shift();
      if (waiting !== undefined) {
        this.handle(waiting);
        continue;
      }
      const next = this.wire.next(null);
      if (next.kind === "message") this.handle(next.message);
      else this.stopping = true;
    }
    return 0;
  }

  private handle(message: RPCMessage): void {
    switch (message.kind) {
      case "request":
        if (message.method === "initialize")
          return this.greet(message.id, message.params);
        if (message.method === "command/run")
          return this.runCommand(message.id, message.params);
        if (message.method === "ui/open")
          return this.openPanel(message.id, message.params);
        if (message.method === "ui/event")
          return this.panelEvent(message.id, message.params);
        return this.refuse(
          message.id,
          RPCErrorCode.methodNotFound,
          "method not found",
        );
      case "notice":
        if (message.method === "shutdown") {
          this.stopping = true;
        } else if (message.method === "preferences/changed") {
          const changed = tryRead(() =>
            readPreferencesChangedParams(message.params),
          );
          if (changed !== undefined)
            this.onPreferencesChanged?.(this.app, changed.values);
        } else if (message.method === "language/changed") {
          const changed = tryRead(() =>
            readLanguageChangedParams(message.params),
          );
          if (changed !== undefined) {
            this.languageTag = changed.language;
            this.onLanguageChanged?.(this.app);
          }
        } else if (message.method === "ui/close") {
          const closed = tryRead(() => readUICloseParams(message.params));
          if (closed !== undefined)
            this.panels.get(closed.panel)?.setOpen(false);
        }
        return;
      default:
        // An answer nobody waits for: it came after its call gave up.
        return;
    }
  }

  private greet(id: RPCID, params: unknown): void {
    const hello = tryRead(() => readInitializeParams(params));
    if (hello === undefined)
      return this.refuse(id, RPCErrorCode.invalidParams, "invalid params");
    // The newest version both speak. Version 2 only adds to version 1, so
    // a tool of either is answered by an app of either.
    const picked = [...PROTOCOL_VERSIONS]
      .reverse()
      .find((version) => hello.protocolVersions.includes(version));
    if (picked === undefined) {
      return this.refuse(
        id,
        RPCErrorCode.invalidParams,
        `this tool speaks protocols ${PROTOCOL_VERSIONS.join(" and ")} only`,
      );
    }
    this.languageTag = hello.language;
    this.folder = hello.dataFolder;
    this.greeted = true;
    this.wire.send({
      kind: "result",
      id,
      result: { protocolVersion: picked, toolVersion: this.version },
    });
    this.onStart?.(this.app);
  }

  private runCommand(id: RPCID, params: unknown): void {
    if (!this.greeted)
      return this.refuse(
        id,
        RPCErrorCode.invalidRequest,
        "initialize comes first",
      );
    const asked = tryRead(() => readCommandRunParams(params));
    if (asked === undefined)
      return this.refuse(id, RPCErrorCode.invalidParams, "invalid params");
    const handler = this.handlers.get(asked.command);
    if (handler === undefined)
      return this.refuse(id, RPCErrorCode.invalidParams, "no such command");
    try {
      const returned: unknown = handler(this.app);
      if (
        returned instanceof Promise ||
        (typeof returned === "object" &&
          returned !== null &&
          "then" in returned)
      ) {
        return this.refuse(
          id,
          RefusalCode.commandRefused,
          "the handler is async; the kit runs handlers to their end",
        );
      }
      this.wire.send({ kind: "result", id, result: {} });
    } catch (error) {
      if (error instanceof CommandRefused) {
        this.refuse(id, RefusalCode.commandRefused, error.message);
      } else if (error instanceof Refusal) {
        // The app refused something the command needed. Its reason goes with
        // ours, for the log.
        this.refuse(
          id,
          RefusalCode.commandRefused,
          "command refused",
          error.error as unknown as JSONValue,
        );
      } else {
        this.refuse(
          id,
          RefusalCode.commandRefused,
          error instanceof Error ? error.message : String(error),
        );
      }
    }
  }

  private openPanel(id: RPCID, params: unknown): void {
    const asked = tryRead(() => readUIOpenParams(params));
    if (asked === undefined)
      return this.refuse(id, RPCErrorCode.invalidParams, "invalid params");
    const panel = this.panels.get(asked.panel);
    if (panel === undefined)
      return this.refuse(id, RPCErrorCode.invalidParams, "no such panel");
    panel.setOpen(true);
    this.answering(id, () => {
      const tree = panel.onOpen(this.app, panel);
      return tree === undefined ? {} : { tree };
    });
  }

  private panelEvent(id: RPCID, params: unknown): void {
    const asked = tryRead(() => readUIEventParams(params));
    if (asked === undefined)
      return this.refuse(id, RPCErrorCode.invalidParams, "invalid params");
    const panel = this.panels.get(asked.panel);
    if (panel === undefined || !panel.isOpen)
      return this.refuse(
        id,
        RPCErrorCode.invalidParams,
        "the panel is not open",
      );
    this.answering(id, () => {
      if (asked.event === "bridge")
        return { reply: this.bridge(asked.value, panel) };
      const event = new PanelEvent(asked.block, asked.event, asked.value);
      return resultOf(panel.onEvent(this.app, panel, event));
    });
  }

  /**
   * A web panel's call: a request the app does is passed to the app as the
   * tool's own, under the tool's `uses`; a method of the tool's own goes to
   * the panel's `onCall`.
   */
  private bridge(value: JSONValue | undefined, panel: Panel): JSONValue {
    const asked = bridgeCallOf(value);
    if (asked === undefined)
      throw new Refusal({
        code: RPCErrorCode.invalidParams,
        message: "invalid params",
      });
    if (asked.method.startsWith(TOOLS_OWN)) {
      if (panel.onCall === undefined)
        throw new Refusal({
          code: RPCErrorCode.methodNotFound,
          message: "method not found",
        });
      return panel.onCall(this.app, asked.method, asked.params);
    }
    const row = METHODS.find((m) => m.method === asked.method);
    if (row === undefined || row.sender !== "tool" || row.kind !== "request")
      throw new Refusal({
        code: RPCErrorCode.methodNotFound,
        message: "method not found",
      });
    const params = asked.params ?? {};
    return this.call(
      asked.method,
      typeof params === "object" && params !== null ? params : {},
    );
  }

  /** Answers a request with what `give` returns, or with the refusal or error it throws. */
  private answering(id: RPCID, give: () => object): void {
    try {
      this.wire.send({ kind: "result", id, result: give() as JSONValue });
    } catch (error) {
      if (error instanceof Refusal) {
        this.refuse(id, error.code, error.message, error.data);
      } else {
        this.refuse(
          id,
          RPCErrorCode.internalError,
          error instanceof Error ? error.message : String(error),
        );
      }
    }
  }

  private refuse(
    id: RPCID,
    code: number,
    message: string,
    data?: JSONValue,
  ): void {
    const error: RPCErrorObject =
      data === undefined ? { code, message } : { code, message, data };
    this.wire.send({ kind: "failure", id, error });
  }

  /** Sends a request and reads the link until its answer has come. */
  private call(method: string, params: object | undefined): JSONValue {
    if (!this.greeted || this.stopping) throw new AppUnreachable("linkClosed");
    this.lastID += 1;
    const id = this.lastID;
    const sent = this.wire.send(
      params === undefined
        ? { kind: "request", id, method }
        : {
            kind: "request",
            id,
            method,
            params: params as { [key: string]: JSONValue },
          },
    );
    if (!sent) {
      this.stopping = true;
      throw new AppUnreachable("linkClosed");
    }
    const deadline = now() + this.answerSeconds * 1000;
    for (;;) {
      const next = this.wire.next(deadline);
      if (next.kind === "ended") {
        this.stopping = true;
        throw new AppUnreachable("linkClosed");
      }
      if (next.kind === "late")
        throw new AppUnreachable("noAnswer", this.answerSeconds);
      const message = next.message;
      if (message.kind === "result" && message.id === id) return message.result;
      if (message.kind === "failure" && message.id === id)
        throw new Refusal(message.error);
      if (message.kind === "notice" && message.method === "shutdown") {
        this.stopping = true;
        throw new AppUnreachable("linkClosed");
      }
      this.kept.push(message);
    }
  }

  /** Sends a notice. False when the link is not open. */
  private note(method: string, params: object): boolean {
    if (!this.greeted || this.stopping) return false;
    return this.wire.send({
      kind: "notice",
      method,
      params: params as { [key: string]: JSONValue },
    });
  }
}

function tryRead<T>(read: () => T): T | undefined {
  try {
    return read();
  } catch {
    return undefined;
  }
}
