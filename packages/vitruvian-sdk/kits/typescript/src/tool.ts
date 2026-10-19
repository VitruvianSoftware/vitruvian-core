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
  type StatusState,
  type UIText,
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

/**
 * What an app may have beyond the first release of a protocol version, by
 * the name it gives at hello. Ask with `app.supports(Feature.choice)`.
 */
export const Feature = {
  /** `ui/status`: the tool's status on the closed island. */
  status: "ui.status",
  /** The `choice` block. */
  choice: "ui.choice",
  /** `options` on a text preference, drawn as a pop-up menu. */
  preferenceOptions: "preferences.options",
  /** `activity` and `since` on `ui/status`: a few words, or a count of seconds, beside the mark. From 3.50. */
  statusActivity: "ui.status.activity",
  /** `{ open }` may name the tool's own settings panel: the app opens Settings on the tool's detail. From 3.58. */
  openSettings: "ui.open.settings",
  /** The `chips` block. */
  chips: "ui.chips",
  /** `section` on a heading, and `help` on a switch, a field, a choice and chips. */
  sections: "ui.sections",
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
  /**
   * Whether this app has something a later release added to the protocol
   * version: it named it at hello. `Feature` holds the names. False for an
   * app that named nothing, as every app before 3.48 does. Ask before using
   * a `choice` block, and send a `field` to an app without it; before
   * `chips`, and send a `toggle` for each option to an app without
   * `Feature.chips`; and before a heading's `section` or a control's `help`,
   * which an app without `Feature.sections` does not draw.
   */
  supports(feature: string): boolean;
  /**
   * Sets the tool's status, a small mark the app draws on the closed island:
   * `ui/status`. Each one replaces the last; `"none"` takes it away; and it
   * goes when the tool's program ends, so a tool that wants it to last
   * starts with the app (`"activation": ["onLaunch"]`). `text` says what it
   * means, for VoiceOver. `icon`, an SF Symbol name, replaces the state's
   * own glyph. The manifest must declare `contributes.status`: without it
   * the app refuses, and this throws the `Refusal`. It needs nothing in
   * `uses`.
   *
   * `activity`, a few words, and `since`, a start time the app counts the
   * seconds from, are drawn beside the mark while it is the one the closed
   * island shows; the words win over the start time. Six characters or
   * fewer, and a number is best. They show only on an app that has
   * `ui.status.activity` (3.50 and later): to an app without it the status
   * is sent without them. The manifest's status must say
   * `"activity": true`, or the app leaves them out.
   *
   * False, and nothing is sent, when the app did not say it has
   * `ui.status`: an app before 3.48 shows no status. True when it was sent
   * and answered; the person may still have switched the mark off.
   *
   * `app.ui.status(params)` is the bare request: it is sent whatever the app
   * said, and an older app answers it with a `Refusal`, -32601.
   */
  status(state: StatusState, options?: StatusOptions): boolean;
}

/** What `app.status` takes beside the state. */
export interface StatusOptions {
  /** What it means, in one short line, for VoiceOver and the tooltip. */
  text?: UIText;
  /** An SF Symbol name, drawn in place of the state's own glyph. */
  icon?: string;
  /** A few words for the closed island, beside the mark. Sent only to an app that has `ui.status.activity`. */
  activity?: UIText;
  /** A start time the app counts the seconds from, when there are no words. Written as Unix seconds. */
  since?: Date;
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
  /**
   * What the app said it has beyond the first release of the protocol
   * version: the hello's `features`. Empty for an app that said nothing.
   */
  private featureNames: ReadonlySet<string> = new Set();
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
    const app = {
      ...calls,
      get language() {
        return tool.languageTag;
      },
      get dataFolder() {
        return tool.folder;
      },
    } as App;
    // The kit's own two, beside the protocol's calls and not among them:
    // what `Object.keys(app)` lists stays one name for each message.
    Object.defineProperties(app, {
      supports: {
        value: (feature: string) => tool.featureNames.has(feature),
      },
      status: {
        value: (state: StatusState, options: StatusOptions = {}) => {
          if (!tool.featureNames.has(Feature.status)) return false;
          const params: {
            state: StatusState;
            text?: UIText;
            icon?: string;
            activity?: UIText;
            since?: number;
          } = { state };
          if (options.text !== undefined) params.text = options.text;
          if (options.icon !== undefined) params.icon = options.icon;
          // An app from before 3.50 is sent the status without its words.
          if (tool.featureNames.has(Feature.statusActivity)) {
            if (options.activity !== undefined)
              params.activity = options.activity;
            if (options.since !== undefined)
              params.since = options.since.getTime() / 1000;
          }
          calls.ui.status(params);
          return true;
        },
      },
    });
    this.app = Object.freeze(app);
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
    this.featureNames = new Set(hello.features ?? []);
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
