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
  CommandRefused,
  METHODS,
  messageOf,
  Refusal,
  RefusalCode,
  type RPCMessage,
  Tool,
} from "../src/index";

class Bench {
  readonly folder = mkdtempSync(join(tmpdir(), "vitruvian-tool-kit-"));
  private sent = "";

  app(line: string): this {
    this.sent += line + "\n";
    return this;
  }

  hello(versions = '["1"]'): this {
    return this.app(
      `{"jsonrpc":"2.0","id":"hello","method":"initialize","params":{"protocolVersions":${versions},"language":"de-DE","dataFolder":"/tmp/kit-data"}}`,
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
  expect(wanted).toHaveLength(12);
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

test("a version the tool does not speak is refused", () => {
  let ran = false;
  const tool = bench
    .hello('["2"]')
    .run("hello", 2)
    .goodbye()
    .tool((tool) => tool.command("hello", () => void (ran = true)));
  expect(tool.serve()).toBe(0);
  expect(ran).toBe(false);
  expect(bench.written()).toEqual([
    failure("hello", -32602, "this tool speaks protocol 1 only"),
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
