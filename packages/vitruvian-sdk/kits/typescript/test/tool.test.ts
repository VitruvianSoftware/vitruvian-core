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

// The kit against a link made of two files: what the app will have sent,
// written before the tool starts, and what the tool writes. A file never
// blocks, and its end is the end of the link, so no test here waits long.
// Ported test for test from Tests/VitruvianToolKitTests/ToolTests.swift.

import { execFileSync, spawn } from "node:child_process";
import {
  closeSync,
  constants,
  existsSync,
  mkdtempSync,
  openSync,
  readFileSync,
  rmSync,
  writeFileSync,
  writeSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

import {
  AppUnreachable,
  button,
  chips,
  choice,
  CommandRefused,
  divider,
  Feature,
  field,
  heading,
  image,
  link,
  list,
  METHODS,
  messageOf,
  type Panel,
  PanelEvent,
  progress,
  Refusal,
  RefusalCode,
  type RPCMessage,
  row,
  spacer,
  text,
  toggle,
  Tool,
  tree,
  type UITree,
} from "../src/index";

class Bench {
  readonly folder = mkdtempSync(join(tmpdir(), "vitruvian-tool-kit-"));
  private sent = "";

  app(line: string): this {
    this.sent += line + "\n";
    return this;
  }

  /**
   * `features` is what the app says it has, as JSON; left out, it is an app
   * from before the field, which says nothing.
   */
  hello(versions = '["1"]', features?: string): this {
    const said = features === undefined ? "" : `,"features":${features}`;
    return this.app(
      `{"jsonrpc":"2.0","id":"hello","method":"initialize","params":{"protocolVersions":${versions},"language":"de-DE","dataFolder":"/tmp/kit-data"${said}}}`,
    );
  }

  run(command: string, id: number): this {
    return this.app(
      `{"jsonrpc":"2.0","id":${id},"method":"command/run","params":{"command":"${command}"}}`,
    );
  }

  goodbye(): this {
    return this.app('{"jsonrpc":"2.0","method":"shutdown"}');
  }

  tool(build: (tool: Tool) => void = () => {}): Tool {
    writeFileSync(join(this.folder, "from-app"), this.sent);
    writeFileSync(join(this.folder, "to-app"), "");
    const tool = new Tool({
      version: "9.9.9",
      input: openSync(join(this.folder, "from-app"), "r"),
      output: openSync(join(this.folder, "to-app"), "w"),
    });
    build(tool);
    return tool;
  }

  written(): RPCMessage[] {
    const text = readFileSync(join(this.folder, "to-app"), "utf8");
    return text
      .split("\n")
      .filter((line) => line !== "")
      .map((line) => messageOf(line) as RPCMessage);
  }

  done(): void {
    rmSync(this.folder, { recursive: true, force: true });
  }
}

const result = (id: number | string, value: object): RPCMessage => ({
  kind: "result",
  id,
  result: value as never,
});
const failure = (
  id: number | string,
  code: number,
  message: string,
): RPCMessage => ({
  kind: "failure",
  id,
  error: { code, message },
});

let bench: Bench;
beforeEach(() => {
  bench = new Bench();
});
afterEach(() => bench.done());

test("every request a tool may send is a call on the app", () => {
  const tool = bench.hello().goodbye().tool();
  let calls: string[] = [];
  tool.onStart = (app) => {
    const record = app as unknown as {
      [group: string]: { [call: string]: unknown } | unknown;
    };
    calls = Object.keys(record).flatMap((group) => {
      const value = record[group];
      if (typeof value === "function") return [group];
      if (typeof value === "object" && value !== null)
        return Object.keys(value).map((call) => `${group}/${call}`);
      return [];
    });
  };
  expect(tool.serve()).toBe(0);
  const wanted = METHODS.filter((m) => m.sender === "tool").map(
    (m) => m.method,
  );
  expect(calls.sort()).toEqual([...wanted].sort());
  expect(wanted).toHaveLength(17);
});

test("hello, a command, and goodbye", () => {
  let ran = 0;
  let seen: string[] = [];
  const tool = bench
    .hello()
    .run("hello", 2)
    .goodbye()
    .tool((tool) =>
      tool.command("hello", (app) => {
        ran += 1;
        seen = [app.language, app.dataFolder];
      }),
    );
  expect(tool.serve()).toBe(0);
  expect(ran).toBe(1);
  expect(seen).toEqual(["de-DE", "/tmp/kit-data"]);
  expect(bench.written()).toEqual([
    result("hello", { protocolVersion: "1", toolVersion: "9.9.9" }),
    result(2, {}),
  ]);
});

test("a handler calls the app and reads the answer", () => {
  let read: string | undefined;
  const tool = bench
    .hello()
    .run("copy", 2)
    .app('{"jsonrpc":"2.0","id":1,"result":{"text":"from the clipboard"}}')
    .app('{"jsonrpc":"2.0","id":2,"result":{}}')
    .goodbye()
    .tool((tool) =>
      tool.command("copy", (app) => {
        read = app.clipboard.readText().text;
        app.notify.hud({ icon: "doc.on.clipboard", message: "Read it" });
      }),
    );
  expect(tool.serve()).toBe(0);
  expect(read).toBe("from the clipboard");
  const written = bench.written();
  expect(written).toHaveLength(4);
  expect(written[1]).toEqual({
    kind: "request",
    id: 1,
    method: "clipboard/readText",
  });
  expect(written[2]).toEqual({
    kind: "request",
    id: 2,
    method: "notify/hud",
    params: { icon: "doc.on.clipboard", message: "Read it" },
  });
  expect(written[3]).toEqual(result(2, {}));
});

test("an answer to another request is not taken for this one", () => {
  let read: string | undefined;
  const tool = bench
    .hello()
    .run("copy", 2)
    .app(
      '{"jsonrpc":"2.0","id":98,"error":{"code":-32004,"message":"not available right now"}}',
    )
    .app('{"jsonrpc":"2.0","id":99,"result":{"text":"somebody else\'s"}}')
    .app('{"jsonrpc":"2.0","id":1,"result":{"text":"mine"}}')
    .goodbye()
    .tool((tool) =>
      tool.command(
        "copy",
        (app) => void (read = app.clipboard.readText().text),
      ),
    );
  expect(tool.serve()).toBe(0);
  expect(read).toBe("mine");
  expect(bench.written().at(-1)).toEqual(result(2, {}));
});

test("a refusal the handler lets through refuses the command", () => {
  const tool = bench
    .hello()
    .run("hello", 7)
    .app(
      '{"jsonrpc":"2.0","id":1,"error":{"code":-32001,"message":"not listed in uses","data":{"service":"notify"}}}',
    )
    .goodbye()
    .tool((tool) =>
      tool.command(
        "hello",
        (app) => void app.notify.hud({ icon: "hand.wave", message: "Hello" }),
      ),
    );
  expect(tool.serve()).toBe(0);
  const last = bench.written().at(-1);
  expect(last?.kind).toBe("failure");
  if (last?.kind !== "failure") return;
  expect(last.id).toBe(7);
  expect(last.error.code).toBe(-32010);
  expect((last.error.data as { code: number }).code).toBe(-32001);
});

test("a handler may catch a refusal and carry on", () => {
  let why: number | undefined;
  const tool = bench
    .hello()
    .run("hello", 7)
    .app(
      '{"jsonrpc":"2.0","id":1,"error":{"code":-32004,"message":"not available right now"}}',
    )
    .goodbye()
    .tool((tool) =>
      tool.command("hello", (app) => {
        try {
          app.notify.beep();
        } catch (error) {
          if (error instanceof Refusal) why = error.code;
        }
      }),
    );
  expect(tool.serve()).toBe(0);
  expect(why).toBe(RefusalCode.unavailable);
  expect(bench.written().at(-1)).toEqual(result(7, {}));
});

test("a command that will not run says why", () => {
  const tool = bench
    .hello()
    .run("hello", 3)
    .run("missing", 4)
    .app('{"jsonrpc":"2.0","id":5,"method":"island/draw"}')
    .goodbye()
    .tool((tool) =>
      tool.command("hello", () => {
        throw new CommandRefused("nothing is selected");
      }),
    );
  expect(tool.serve()).toBe(0);
  expect(bench.written().slice(1)).toEqual([
    failure(3, -32010, "nothing is selected"),
    failure(4, -32602, "no such command"),
    failure(5, -32601, "method not found"),
  ]);
});

test("what comes while a handler waits is handled after it", () => {
  const order: string[] = [];
  const tool = bench
    .hello()
    .run("first", 2)
    .app(
      '{"jsonrpc":"2.0","method":"language/changed","params":{"language":"fr"}}',
    )
    .run("second", 3)
    .app('{"jsonrpc":"2.0","id":1,"result":{}}')
    .app('{"jsonrpc":"2.0","id":2,"result":{}}')
    .goodbye()
    .tool((tool) => {
      tool.command("first", (app) => {
        app.notify.beep();
        order.push(`first in ${app.language}`);
      });
      tool.command("second", (app) => {
        app.notify.beep();
        order.push(`second in ${app.language}`);
      });
    });
  expect(tool.serve()).toBe(0);
  expect(order).toEqual(["first in de-DE", "second in fr"]);
  const answers = bench
    .written()
    .flatMap((m) => (m.kind === "result" ? [m.id] : []));
  expect(answers).toEqual(["hello", 2, 3]);
});

test("goodbye while a handler waits ends the wait", () => {
  let thrown: string | undefined;
  const tool = bench
    .hello()
    .run("hello", 2)
    .goodbye()
    .tool((tool) =>
      tool.command("hello", (app) => {
        try {
          app.notify.beep();
        } catch (error) {
          if (error instanceof AppUnreachable) thrown = error.reason;
          throw error;
        }
      }),
    );
  expect(tool.serve()).toBe(0);
  expect(thrown).toBe("linkClosed");
  const last = bench.written().at(-1);
  expect(last?.kind === "failure" && last.id === 2 && last.error.code).toBe(
    -32010,
  );
});

test("the link ending ends the wait and the loop", () => {
  let thrown: string | undefined;
  const tool = bench
    .hello()
    .run("hello", 2)
    .tool((tool) =>
      tool.command("hello", (app) => {
        try {
          app.notify.beep();
        } catch (error) {
          if (error instanceof AppUnreachable) thrown = error.reason;
        }
      }),
    );
  expect(tool.serve()).toBe(0);
  expect(thrown).toBe("linkClosed");
});

test("a call gives up when no answer comes", () => {
  // A pipe, so that the link stays open with nothing on it: a named one, as
  // Node cannot make an unnamed pair. Its reading end is opened first and
  // without blocking, which is also what makes a read of it come back at once.
  const fifo = join(bench.folder, "link");
  execFileSync("mkfifo", [fifo]);
  const input = openSync(fifo, constants.O_RDONLY | constants.O_NONBLOCK);
  const writer = openSync(fifo, constants.O_WRONLY);
  writeSync(
    writer,
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersions":["1"],"language":"en","dataFolder":"/tmp"}}\n' +
      '{"jsonrpc":"2.0","id":2,"method":"command/run","params":{"command":"hello"}}\n',
  );
  writeFileSync(join(bench.folder, "to-app"), "");
  const tool = new Tool({
    version: "1",
    input,
    output: openSync(join(bench.folder, "to-app"), "w"),
  });
  tool.answerSeconds = 0.05;
  let thrown: AppUnreachable | undefined;
  tool.command("hello", (app) => {
    try {
      app.notify.beep();
    } catch (error) {
      if (error instanceof AppUnreachable) thrown = error;
    }
    // The app goes away, which ends the loop.
    closeSync(writer);
  });
  const started = Date.now();
  expect(tool.serve()).toBe(0);
  expect(thrown?.reason).toBe("noAnswer");
  expect(thrown?.seconds).toBe(0.05);
  expect(Date.now() - started).toBeLessThan(5000);
  closeSync(input);
});

test("the newest version both speak is picked", () => {
  for (const [offered, picked] of [
    ['["1","2"]', "2"],
    ['["1"]', "1"],
    ['["2","1"]', "2"],
    ['["2","3"]', "2"],
  ]) {
    const one = new Bench();
    const tool = one.hello(offered).goodbye().tool();
    expect(tool.serve()).toBe(0);
    const first = one.written()[0];
    expect(first.kind === "result" && first.result).toEqual({
      protocolVersion: picked,
      toolVersion: "9.9.9",
    });
    one.done();
  }
});

test("a version the tool does not speak is refused", () => {
  let ran = false;
  const tool = bench
    .hello('["3"]')
    .run("hello", 2)
    .goodbye()
    .tool((tool) => tool.command("hello", () => void (ran = true)));
  expect(tool.serve()).toBe(0);
  expect(ran).toBe(false);
  expect(bench.written()).toEqual([
    failure("hello", -32602, "this tool speaks protocols 1 and 2 only"),
    failure(2, -32600, "initialize comes first"),
  ]);
});

test("notices reach their handlers, and the tool's own are written after hello", () => {
  let changed: object = {};
  let language = "";
  const tool = bench
    .hello()
    .app("this line is not a message")
    .app(
      '{"jsonrpc":"2.0","method":"preferences/changed","params":{"values":{"project":"web"}}}',
    )
    .app(
      '{"jsonrpc":"2.0","method":"language/changed","params":{"language":"ja"}}',
    )
    .goodbye()
    .tool((tool) => {
      tool.onStart = (app) => {
        app.commands.state({ runnable: ["hello"] });
        app.log({ message: "started" });
      };
      tool.onPreferencesChanged = (_, values) => void (changed = values);
      tool.onLanguageChanged = (app) => void (language = app.language);
    });
  expect(tool.serve()).toBe(0);
  expect(changed).toEqual({ project: "web" });
  expect(language).toBe("ja");
  expect(bench.written().slice(1)).toEqual([
    {
      kind: "notice",
      method: "commands/state",
      params: { runnable: ["hello"] },
    },
    { kind: "notice", method: "log", params: { message: "started" } },
  ]);
});

test("an async handler is refused, not answered before its work is done", () => {
  const tool = bench
    .hello()
    .run("later", 2)
    .goodbye()
    .tool((tool) =>
      tool.command("later", (async () => {}) as unknown as () => void),
    );
  expect(tool.serve()).toBe(0);
  const last = bench.written().at(-1);
  expect(last?.kind === "failure" && last.error.code).toBe(-32010);
});

test("the tool's own standard input, a pipe, is read with a time limit too", async () => {
  // The real path: a tool started with a pipe on its standard input, as the
  // app starts it, whose call gets no answer. Run from the built kit.
  const built = join(__dirname, "..", "dist", "index.js");
  if (!existsSync(built))
    throw new Error(
      `${built} is not there: build the kit first (npm run build)`,
    );
  const program = [
    `import { Tool, AppUnreachable } from ${JSON.stringify(pathToFileURL(built).href)};`,
    `const tool = new Tool({ version: "1" });`,
    `tool.answerSeconds = 0.05;`,
    `tool.command("hello", (app) => {`,
    `  try { app.notify.beep(); } catch (error) { if (error instanceof AppUnreachable) app.log({ message: error.reason }); }`,
    `});`,
    `tool.run();`,
  ].join("\n");
  const child = spawn(
    process.execPath,
    ["--input-type=module", "-e", program],
    { stdio: ["pipe", "pipe", "inherit"] },
  );
  let out = "";
  child.stdout.on("data", (chunk: Buffer) => {
    out += chunk.toString("utf8");
    if (out.includes('"log"')) child.stdin.end();
  });
  child.stdin.write(
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersions":["1"],"language":"en","dataFolder":"/tmp"}}\n' +
      '{"jsonrpc":"2.0","id":2,"method":"command/run","params":{"command":"hello"}}\n',
  );
  const status = await new Promise<number | null>((resolve) =>
    child.on("exit", resolve),
  );
  expect(status).toBe(0);
  expect(out).toContain(
    '{"jsonrpc":"2.0","method":"log","params":{"message":"noAnswer"}}',
  );
  expect(out).toContain('{"jsonrpc":"2.0","id":2,"result":{}}');
}, 20_000);

// The Swift kit's PanelTests, test for test.

const open = (panel: string, id: number) =>
  `{"jsonrpc":"2.0","id":${id},"method":"ui/open","params":{"panel":"${panel}"}}`;
const tap = (panel: string, block: string, id: number) =>
  `{"jsonrpc":"2.0","id":${id},"method":"ui/event","params":{"panel":"${panel}","block":"${block}","event":"tap"}}`;
const close = (panel: string) =>
  `{"jsonrpc":"2.0","method":"ui/close","params":{"panel":"${panel}"}}`;
const treeOf = (message: RPCMessage | undefined): unknown =>
  message?.kind === "result" && typeof message.result === "object"
    ? (message.result as { tree?: unknown }).tree
    : undefined;
const page = (words: string): UITree => tree([text(words)]);

test("a panel is opened, acted in and closed", () => {
  let count = 0;
  const seen: PanelEvent[] = [];
  let handle: Panel | undefined;
  const tool = bench
    .hello('["1","2"]')
    .app(open("counter", 2))
    .app(tap("counter", "add", 3))
    .app(tap("counter", "nothing", 4))
    .app(close("counter"))
    .goodbye()
    .tool((tool) => {
      handle = tool.panel("counter", {
        onOpen: () => page(`Pressed ${count} times`),
        onEvent: (_app, _panel, event) => {
          seen.push(event);
          if (event.block !== "add") return { keep: true };
          count += 1;
          return { page: page(`Pressed ${count} times`) };
        },
      });
    });
  expect(tool.serve()).toBe(0);
  const written = bench.written();
  expect(written[0]).toEqual(
    result("hello", { protocolVersion: "2", toolVersion: "9.9.9" }),
  );
  expect(treeOf(written[1])).toEqual({
    blocks: [{ type: "text", text: "Pressed 0 times" }],
  });
  expect(treeOf(written[2])).toEqual({
    blocks: [{ type: "text", text: "Pressed 1 times" }],
  });
  expect(written[3]).toEqual(result(4, { keep: true }));
  expect(seen).toEqual([
    new PanelEvent("add", "tap"),
    new PanelEvent("nothing", "tap"),
  ]);
  expect(handle?.isOpen).toBe(false);
});

test("a page is sent unprompted only while the panel is open", () => {
  const sent: boolean[] = [];
  const tool = bench
    .hello('["1","2"]')
    .run("refresh", 2)
    .app(open("counter", 3))
    .run("refresh", 4)
    .app(close("counter"))
    .run("refresh", 5)
    .goodbye()
    .tool((tool) => {
      const panel = tool.panel("counter", {
        onOpen: () => tree([heading("Counter")]),
      });
      tool.command("refresh", () => {
        sent.push(panel.render(page("Later")));
      });
    });
  expect(tool.serve()).toBe(0);
  expect(sent).toEqual([false, true, false]);
  const renders = bench
    .written()
    .filter((m) => m.kind === "notice" && m.method === "ui/render");
  expect(renders).toEqual([
    {
      kind: "notice",
      method: "ui/render",
      params: {
        panel: "counter",
        tree: { blocks: [{ type: "text", text: "Later" }] },
      },
    },
  ]);
});

test("what is not a panel of the tool's is refused", () => {
  const tool = bench
    .hello('["1","2"]')
    .app(open("nowhere", 2))
    .app(tap("counter", "add", 3))
    .goodbye()
    .tool((tool) => {
      tool.panel("counter", { onOpen: () => undefined });
    });
  expect(tool.serve()).toBe(0);
  expect(bench.written().slice(1)).toEqual([
    failure(2, -32602, "no such panel"),
    failure(3, -32602, "the panel is not open"),
  ]);
});

test("an answer may open a window or reply, and the badge is a request", () => {
  const tool = bench
    .hello('["1","2"]')
    .app(open("deploys", 2))
    .app(tap("deploys", "log", 3))
    .app('{"jsonrpc":"2.0","id":1,"result":{}}')
    .goodbye()
    .tool((tool) => {
      tool.panel("deploys", {
        onOpen: (_app, panel) => {
          panel.badge({ count: 2 });
          return undefined;
        },
        onEvent: () => ({ open: "log" }),
      });
    });
  expect(tool.serve()).toBe(0);
  const written = bench.written();
  expect(written[1]).toEqual({
    kind: "request",
    id: 1,
    method: "ui/badge",
    params: { count: 2 },
  });
  expect(written[2]).toEqual(result(2, {}));
  expect(written[3]).toEqual(result(3, { open: "log" }));
});

test("a web panel's calls are the tool's own or passed to the app", () => {
  const bridge = (id: number, call: string) =>
    `{"jsonrpc":"2.0","id":${id},"method":"ui/event","params":{"panel":"dashboard","event":"bridge","value":${call}}}`;
  const tool = bench
    .hello('["1","2"]')
    .app(open("dashboard", 2))
    .app(
      bridge(
        3,
        '{"method":"notify/hud","params":{"icon":"checkmark","message":"Saved"}}',
      ),
    )
    .app('{"jsonrpc":"2.0","id":1,"result":{}}')
    .app(bridge(4, '{"method":"tool/count","params":{"by":2}}'))
    .app(bridge(5, '{"method":"tool/other"}'))
    .app(bridge(6, '{"method":"initialize"}'))
    .goodbye()
    .tool((tool) => {
      const panel = tool.panel("dashboard", { onOpen: () => undefined });
      panel.onCall = (_app, method, params) => {
        if (method !== "tool/count")
          throw new Refusal({ code: -32601, message: "method not found" });
        return { count: (params as { by: number }).by };
      };
    });
  expect(tool.serve()).toBe(0);
  expect(bench.written().slice(2)).toEqual([
    {
      kind: "request",
      id: 1,
      method: "notify/hud",
      params: { icon: "checkmark", message: "Saved" },
    },
    result(3, { reply: {} }),
    result(4, { reply: { count: 2 } }),
    failure(5, -32601, "method not found"),
    failure(6, -32601, "method not found"),
  ]);
});

test("a status is sent to an app that has it", () => {
  const shown: boolean[] = [];
  const tool = bench
    .hello('["1","2"]', '["ui.status","ui.later"]')
    .run("check", 2)
    .app('{"jsonrpc":"2.0","id":1,"result":{}}')
    .app('{"jsonrpc":"2.0","id":2,"result":{}}')
    .goodbye()
    .tool((tool) =>
      tool.command("check", (app) => {
        shown.push(
          app.status("busy", {
            text: "Checks are running",
            icon: "arrow.triangle.branch",
          }),
        );
        shown.push(app.status("none"));
      }),
    );
  expect(tool.serve()).toBe(0);
  expect(shown).toEqual([true, true]);
  const written = bench.written();
  expect(written).toHaveLength(4);
  expect(written[1]).toEqual({
    kind: "request",
    id: 1,
    method: "ui/status",
    params: {
      state: "busy",
      text: "Checks are running",
      icon: "arrow.triangle.branch",
    },
  });
  expect(written[2]).toEqual({
    kind: "request",
    id: 2,
    method: "ui/status",
    params: { state: "none" },
  });
});

test("a status sends its words to an app that draws them", () => {
  const shown: boolean[] = [];
  const tool = bench
    .hello('["2"]', '["ui.status","ui.status.activity"]')
    .run("check", 2)
    .app('{"jsonrpc":"2.0","id":1,"result":{}}')
    .goodbye()
    .tool((tool) =>
      tool.command("check", (app) => {
        shown.push(
          app.status("busy", {
            text: "Checks are running",
            activity: "3",
            since: new Date(1760450400500),
          }),
        );
      }),
    );
  expect(tool.serve()).toBe(0);
  expect(shown).toEqual([true]);
  // The words, and the start time in Unix seconds, not milliseconds.
  expect(bench.written()[1]).toEqual({
    kind: "request",
    id: 1,
    method: "ui/status",
    params: {
      state: "busy",
      text: "Checks are running",
      activity: "3",
      since: 1760450400.5,
    },
  });
});

test("a status sends no words to an app from 3.48", () => {
  // 3.48 and 3.49 name `ui.status` and not its words: the status goes,
  // without them.
  const shown: boolean[] = [];
  const tool = bench
    .hello('["2"]', '["ui.status","ui.choice","preferences.options"]')
    .run("check", 2)
    .app('{"jsonrpc":"2.0","id":1,"result":{}}')
    .goodbye()
    .tool((tool) =>
      tool.command("check", (app) => {
        shown.push(
          app.status("busy", {
            text: "Checks are running",
            activity: "3",
            since: new Date(),
          }),
        );
      }),
    );
  expect(tool.serve()).toBe(0);
  expect(shown).toEqual([true]);
  expect(bench.written()[1]).toEqual({
    kind: "request",
    id: 1,
    method: "ui/status",
    params: { state: "busy", text: "Checks are running" },
  });
});

test("a status with words writes nothing for an app without a status", () => {
  const shown: boolean[] = [];
  const tool = bench
    .hello('["1","2"]')
    .run("check", 2)
    .goodbye()
    .tool((tool) => {
      tool.answerSeconds = 0.2;
      tool.command("check", (app) => {
        shown.push(app.status("busy", { activity: "3", since: new Date() }));
      });
    });
  expect(tool.serve()).toBe(0);
  expect(shown).toEqual([false]);
  expect(bench.written()).toHaveLength(2);
});

test("a status writes nothing for an older app", () => {
  // An app before 3.48: its hello has no `features`. No answer is scripted,
  // so a request sent here would wait and then fail.
  const shown: boolean[] = [];
  const tool = bench
    .hello('["1","2"]')
    .run("check", 2)
    .goodbye()
    .tool((tool) => {
      tool.answerSeconds = 0.2;
      tool.command("check", (app) => {
        shown.push(app.status("failure", { text: "main is red" }));
      });
    });
  expect(tool.serve()).toBe(0);
  // The call says the status is not shown,
  expect(shown).toEqual([false]);
  // and nothing was sent for it: only the two answers are on the link.
  expect(bench.written()).toEqual([
    result("hello", { protocolVersion: "2", toolVersion: "9.9.9" }),
    result(2, {}),
  ]);
});

test("a status writes nothing for an app that has other things", () => {
  const shown: boolean[] = [];
  const tool = bench
    .hello('["2"]', '["ui.choice"]')
    .run("check", 2)
    .goodbye()
    .tool((tool) =>
      tool.command("check", (app) => {
        shown.push(app.status("ok"));
      }),
    );
  expect(tool.serve()).toBe(0);
  expect(shown).toEqual([false]);
  expect(bench.written()).toHaveLength(2);
});

test("supports is true only for what the hello listed", () => {
  let has: boolean[] = [];
  const tool = bench
    .hello('["1"]', '["ui.choice","preferences.options","ui.later"]')
    .run("ask", 2)
    .goodbye()
    .tool((tool) =>
      tool.command("ask", (app) => {
        has = [
          Feature.choice,
          Feature.preferenceOptions,
          Feature.status,
          "ui.later",
          "ui.never",
        ].map((name) => app.supports(name));
      }),
    );
  expect(tool.serve()).toBe(0);
  expect(has).toEqual([true, true, false, true, false]);
  expect(Feature).toEqual({
    status: "ui.status",
    choice: "ui.choice",
    preferenceOptions: "preferences.options",
    statusActivity: "ui.status.activity",
    openSettings: "ui.open.settings",
    chips: "ui.chips",
    sections: "ui.sections",
    notice: "notify.notice",
    slot: "ui.slot",
    folderPicker: "preferences.folder",
  });
});

test("an app that says nothing has none of them", () => {
  let has: boolean[] = [];
  const tool = bench
    .hello()
    .run("ask", 2)
    .goodbye()
    .tool((tool) =>
      tool.command("ask", (app) => {
        has = Object.values(Feature).map((name) => app.supports(name));
      }),
    );
  expect(tool.serve()).toBe(0);
  expect(has).toEqual([
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
  ]);
});

test("a choice is built as the protocol's example", () => {
  const options = [
    { value: "green", title: "Green" },
    {
      value: "breathe green",
      title: { en: "Pulsing green", de: "Pulsierendes Grün" },
    },
  ];
  const examples = JSON.parse(
    readFileSync(
      join(
        __dirname,
        "..",
        "..",
        "..",
        "protocol",
        "examples",
        "messages.json",
      ),
      "utf8",
    ),
  ).examples as { about: string; message: { params: { tree: UITree } } }[];
  const example = examples.find(
    (e) => e.about === "a page with a choice among fixed options",
  )!.message.params.tree.blocks[0];
  expect(
    choice("light", "green", options, {
      title: "Mouse when green",
      enabled: true,
      fallback: "Mouse when green: Green",
    }),
  ).toEqual(example);

  // With no fallback given, the builder writes one: an app before 3.48
  // draws it in the menu's place.
  expect(
    choice("light", "green", options, { title: "Mouse when green" }).fallback,
  ).toBe("Mouse when green: Green");
  // With no title, the selected option's title alone.
  expect(choice("light", "green", options).fallback).toBe("Green");
  // In every language either text has.
  expect(
    choice("light", "breathe green", options, { title: "Mouse when green" })
      .fallback,
  ).toEqual({
    en: "Mouse when green: Pulsing green",
    de: "Mouse when green: Pulsierendes Grün",
  });
  // A value that is no option's is written as it is.
  expect(
    choice("light", "typed by hand", options, { title: "Light" }).fallback,
  ).toBe("Light: typed by hand");
  // A pick arrives as the event a field's change is, with the option's value.
  expect(new PanelEvent("light", "change", "breathe green").text).toBe(
    "breathe green",
  );
});

function exampleBlocks(about: string): UITree["blocks"] {
  const examples = JSON.parse(
    readFileSync(
      join(
        __dirname,
        "..",
        "..",
        "..",
        "protocol",
        "examples",
        "messages.json",
      ),
      "utf8",
    ),
  ).examples as { about: string; message: { params: { tree: UITree } } }[];
  return examples.find((e) => e.about === about)!.message.params.tree.blocks;
}

test("chips are built as the protocol's example", () => {
  const options = [
    { value: "whatsapp", title: "WhatsApp", on: true },
    {
      value: "signal",
      title: { en: "Signal", de: "Signal" },
      on: false,
      enabled: true,
    },
    {
      value: "slack",
      title: "Slack",
      on: false,
      enabled: false,
      reason: "Slack has its own switch",
    },
  ];
  expect(
    chips("networks", options, {
      title: "Networks",
      enabled: true,
      help: "Messages from a muted network are not announced.",
      fallback: "Networks: WhatsApp",
    }),
  ).toEqual(exampleBlocks("a set of chips")[0]);

  // With no fallback given, the builder writes one: an app without
  // ui.chips draws it in their place. The title, a colon and the titles of
  // the options that are on.
  expect(chips("networks", options, { title: "Networks" }).fallback).toBe(
    "Networks: WhatsApp",
  );
  // With no title, the titles alone.
  expect(
    chips("networks", [
      options[0]!,
      { value: "signal", title: "Signal", on: true },
    ]).fallback,
  ).toBe("WhatsApp, Signal");
  // In every language any of the texts has.
  expect(
    chips(
      "networks",
      [
        options[0]!,
        { value: "sms", title: { en: "Text messages", de: "SMS" }, on: true },
        { value: "signal", title: "Signal", on: false },
      ],
      { title: "Networks" },
    ).fallback,
  ).toEqual({
    en: "Networks: WhatsApp, Text messages",
    de: "Networks: WhatsApp, SMS",
  });
  // A dash when none is on.
  const off = [{ value: "whatsapp", title: "WhatsApp", on: false }];
  expect(chips("networks", off, { title: "Networks" }).fallback).toBe(
    "Networks: \u2014",
  );
  expect(chips("networks", off).fallback).toBe("\u2014");

  // Turning a chip is the event change, with the values of every option
  // then on.
  expect(new PanelEvent("networks", "change", ["whatsapp"]).values).toEqual([
    "whatsapp",
  ]);
  expect(new PanelEvent("networks", "change", []).values).toEqual([]);
  expect(new PanelEvent("networks", "change", []).text).toBeUndefined();
  expect(new PanelEvent("light", "change", "green").values).toBeUndefined();
  expect(
    new PanelEvent("networks", "tap", ["whatsapp"]).values,
  ).toBeUndefined();
  expect(new PanelEvent("networks", "change", [1]).values).toBeUndefined();
});

test("sections and help are built as the protocol's examples", () => {
  expect([
    heading("Chats", { section: true }),
    heading("Beeper", { section: false }),
  ]).toEqual(exampleBlocks("a heading that starts a section"));
  expect([
    toggle("pause", "Pause media", true, {
      help: "Pauses what is playing while a message is spoken.",
    }),
  ]).toEqual(exampleBlocks("a toggle with help"));
  expect([
    choice("voice", "calm", [{ value: "calm", title: "Calm" }], {
      title: "Voice",
      help: "The voice messages are spoken in.",
    }),
    field("token", {
      title: "Access token",
      kind: "secret",
      help: { en: "From Beeper's settings.", de: "Aus Beepers Einstellungen." },
    }),
  ]).toEqual(
    exampleBlocks("a choice and a field with help").map((block, index) =>
      index === 0 ? { ...block, fallback: "Voice: Calm" } : block,
    ),
  );
  // Without them, nothing more is written.
  expect([
    heading("Counter"),
    toggle("notify", "Tell me", true),
    field("name"),
  ]).toEqual([
    { type: "heading", text: "Counter" },
    { type: "toggle", id: "notify", title: "Tell me", value: true },
    { type: "field", id: "name" },
  ]);
});

test("a page is written as the blocks it holds", () => {
  const count = 12;
  const rows = ["web", "api"];
  const page = tree([
    heading("Counter"),
    text(`Pressed ${count} times`, { style: "secondary" }),
    button("add", "Add one", { style: "prominent" }),
    count > 9 && text("That is a lot", { style: "caption" }),
    count > 99 ? divider() : spacer(4),
    ...rows.map((name) => row(name, { id: name })),
    list("deploys", [{ id: "web", title: "web 1.42.0" }]),
    toggle("notify", "Tell me", true),
    field("name", { title: "Name", placeholder: "Type and press Return" }),
    progress({ value: 0.5 }),
    image("ui/logo.png", { alt: "Logo" }),
    link("Dashboard", "https://example.com"),
  ]);
  expect(page.blocks.map((block) => block.type)).toEqual([
    "heading",
    "text",
    "button",
    "text",
    "spacer",
    "row",
    "row",
    "list",
    "toggle",
    "field",
    "progress",
    "image",
    "link",
  ]);
  expect(page.blocks[2].id).toBe("add");
  expect(page.blocks.flatMap((block) => (block.id ? [block.id] : []))).toEqual([
    "add",
    "web",
    "api",
    "deploys",
    "notify",
    "name",
  ]);
  expect(JSON.parse(JSON.stringify(page.blocks[1]))).toEqual({
    type: "text",
    text: "Pressed 12 times",
    style: "secondary",
  });
});

test("a notice is sent to an app that has it", () => {
  const tool = bench
    .hello('["2"]', '["notify.notice"]')
    .run("tell", 2)
    .app('{"jsonrpc":"2.0","id":1,"result":{}}')
    .app('{"jsonrpc":"2.0","id":2,"result":{}}')
    .goodbye()
    .tool((tool) =>
      tool.command("tell", (app) => {
        app.showNotice("Claude finished", {
          icon: "checkmark.circle",
          detail: "the tests pass",
          system: true,
        });
        app.showNotice("Waiting", { icon: "bell" });
      }),
    );
  expect(tool.serve()).toBe(0);
  const written = bench.written();
  expect(written[1]).toEqual({
    kind: "request",
    id: 1,
    method: "notify/notice",
    params: {
      icon: "checkmark.circle",
      title: "Claude finished",
      detail: "the tests pass",
      system: true,
    },
  });
  expect(written[2]).toEqual({
    kind: "request",
    id: 2,
    method: "notify/notice",
    params: { icon: "bell", title: "Waiting" },
  });
});

test("a notice is a short message for an app without notices", () => {
  const tool = bench
    .hello('["2"]', '["ui.status"]')
    .run("tell", 2)
    .app('{"jsonrpc":"2.0","id":1,"result":{}}')
    .goodbye()
    .tool((tool) =>
      tool.command("tell", (app) => {
        app.showNotice("Claude finished", {
          icon: "checkmark.circle",
          detail: "the tests pass",
          system: true,
        });
      }),
    );
  expect(tool.serve()).toBe(0);
  expect(bench.written()[1]).toEqual({
    kind: "request",
    id: 1,
    method: "notify/hud",
    params: { icon: "checkmark.circle", message: "Claude finished" },
  });
});

test("dock is sent to an app with a slot, and nothing to an older app", () => {
  const docked: boolean[] = [];
  const tool = bench
    .hello('["2"]', '["ui.slot"]')
    .run("dock", 2)
    .app('{"jsonrpc":"2.0","id":1,"result":{}}')
    .goodbye()
    .tool((tool) =>
      tool.command("dock", (app) => {
        docked.push(app.dockToSlot());
      }),
    );
  expect(tool.serve()).toBe(0);
  expect(docked).toEqual([true]);
  expect(bench.written()[1]).toEqual({
    kind: "request",
    id: 1,
    method: "ui/dock",
  });
});

test("dock writes nothing for an app without a slot", () => {
  const docked: boolean[] = [];
  const tool = bench
    .hello('["1","2"]')
    .run("dock", 2)
    .goodbye()
    .tool((tool) => {
      tool.answerSeconds = 0.2;
      tool.command("dock", (app) => {
        docked.push(app.dockToSlot());
      });
    });
  expect(tool.serve()).toBe(0);
  expect(docked).toEqual([false]);
  expect(bench.written()).toEqual([
    result("hello", { protocolVersion: "2", toolVersion: "9.9.9" }),
    result(2, {}),
  ]);
});

test("the slot's place is handed to onSlot", () => {
  const seen: object[] = [];
  const tool = bench
    .hello('["2"]', '["ui.slot"]')
    .app(
      '{"jsonrpc":"2.0","method":"ui/slot","params":{"visible":true,"x":10,"y":20.5,"width":300,"height":200}}',
    )
    .app(
      '{"jsonrpc":"2.0","method":"ui/slot","params":{"visible":false,"popOut":true}}',
    )
    .app('{"jsonrpc":"2.0","method":"ui/slot","params":{"x":1}}')
    .goodbye()
    .tool((tool) => {
      tool.onSlot = (_app, slot) => seen.push(slot);
    });
  expect(tool.serve()).toBe(0);
  expect(seen).toEqual([
    { visible: true, x: 10, y: 20.5, width: 300, height: 200 },
    { visible: false, popOut: true },
  ]);
});
