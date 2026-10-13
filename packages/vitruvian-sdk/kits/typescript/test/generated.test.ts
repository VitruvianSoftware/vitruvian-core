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

// The generated types read every example the protocol calls valid, and give
// back what they read, less a field the schema does not name (the protocol
// says such a field is ignored). protocol/examples/ is what the schemas and
// the Swift types are both held to; reading it here holds the generated
// TypeScript to it too.

import { readFileSync } from "node:fs";
import { join } from "node:path";

import * as messages from "../src/generated/messages";
import { METHODS, readToolManifest, ShapeError } from "../src/index";

const protocol = join(__dirname, "..", "..", "..", "protocol");
const load = (name: string) =>
  JSON.parse(readFileSync(join(protocol, name), "utf8"));

type Reader = (value: unknown) => object;

function readerFor(name: string): Reader {
  const title =
    (
      { empty: "EmptyObject", error: "RPCErrorObject" } as {
        [k: string]: string;
      }
    )[name] ??
    (/^ui[A-Z]/.test(name)
      ? "UI" + name.slice(2)
      : name[0].toUpperCase() + name.slice(1));
  return (messages as unknown as { [k: string]: Reader })[`read${title}`];
}

test("every valid message reads and writes back", () => {
  const named: { [name: string]: string[] } = {};
  for (const [name, node] of Object.entries(
    load("messages.schema.json").$defs as {
      [k: string]: { properties?: object };
    },
  )) {
    named[name] = Object.keys(node.properties ?? {});
  }
  const known = (name: string, value: { [k: string]: unknown }) =>
    Object.fromEntries(
      Object.entries(value).filter(([key]) => named[name].includes(key)),
    );
  const table = new Map(METHODS.map((m) => [m.method, m]));
  let read = 0;
  for (const example of load("examples/messages.json").examples) {
    if (!example.valid) continue;
    const message = example.message;
    const row = table.get(example.answers ?? message.method);
    if (row === undefined) continue;
    if ("method" in message && row.params !== null) {
      expect(
        JSON.parse(JSON.stringify(readerFor(row.params)(message.params))),
      ).toEqual(known(row.params, message.params));
      read += 1;
    } else if ("result" in message && row.result !== null) {
      expect(
        JSON.parse(JSON.stringify(readerFor(row.result)(message.result))),
      ).toEqual(known(row.result, message.result));
      read += 1;
    }
  }
  expect(read).toBeGreaterThan(20);
});

test("a wrong field is named", () => {
  expect(() => messages.readNotifyHUDParams({ icon: "x", message: 3 })).toThrow(
    ShapeError,
  );
  expect(() => messages.readNotifyHUDParams({ icon: "x", message: 3 })).toThrow(
    "notifyHUDParams.message is not text",
  );
});

test("every valid manifest reads", () => {
  const examples = load("examples/manifests.json");
  let read = 0;
  for (const example of examples.examples) {
    if (!example.valid) continue;
    const manifest = { ...examples.base };
    for (const [key, value] of Object.entries(example.change)) {
      if (value === null) delete manifest[key];
      else manifest[key] = value;
    }
    readToolManifest(manifest);
    read += 1;
  }
  expect(read).toBeGreaterThan(5);
});
