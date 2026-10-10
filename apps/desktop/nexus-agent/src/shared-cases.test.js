/**
 * Copyright (c) 2026 VitruvianSoftware
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

// The examples in ../testdata are shared with the Mac apps' tests
// (macos/Tests/SharedCasesTests.swift). This file runs them through the bot's
// own code, so a rule changed here without the apps following fails their
// tests, and the other way round. Expected values live only in the JSON.

import { test, after } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import { createRequire } from "node:module";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

// The package the bot loads `.env` with (bot.js: `import "dotenv/config"`).
import dotenv from "dotenv";

import { annotationIsArchived } from "./annotations.js";

// agy.js reads the environment once, when it is imported, and loads the
// session store from the working directory. Point it at a throwaway folder
// and take the approval-mode keys out BEFORE importing, so the test never
// touches a real store and sees the bot as it is with no mode in `.env`.
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "nexus-shared-cases-"));
after(() => {
  fs.rmSync(scratch, { recursive: true, force: true });
});
process.env.AGY_WORKING_DIR = scratch;
delete process.env.AGY_APPROVAL_MODE;
delete process.env.GEMINI_APPROVAL_MODE;
const { approvalArgs, getChatSettings } = await import("./agy.js");

/**
 * The cases of one shared file. A missing, unreadable or empty file fails the
 * test: a loop over no cases would pass without checking anything.
 * @param {string} file
 * @returns {any[]}
 */
function loadCases(file) {
  const url = new URL(`../testdata/${file}`, import.meta.url);
  let parsed;
  try {
    parsed = JSON.parse(fs.readFileSync(url, "utf8"));
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    assert.fail(`shared cases file ${url.pathname} cannot be read: ${message}`);
  }
  assert.ok(
    Array.isArray(parsed.cases) && parsed.cases.length > 0,
    `shared cases file ${url.pathname} has no cases`,
  );
  return parsed.cases;
}

test("archive annotations: the bot reads every shared example as written", () => {
  const cases = loadCases("archive-annotations.json");
  let checked = 0;
  for (const { name, text, archived } of cases) {
    assert.equal(typeof archived, "boolean", `${name}: archived is a boolean`);
    assert.equal(annotationIsArchived(text), archived, name);
    checked += 1;
  }
  assert.equal(checked, cases.length);
});

test("approval modes: the bot passes agy the flags every shared example says", () => {
  const cases = loadCases("approval-modes.json");
  // A chat nobody has changed the mode for: its mode is whatever the bot took
  // from the environment when it loaded, which here had no mode in it.
  const whenAbsent = getChatSettings(0).approvalMode;
  let checked = 0;
  for (const { name, value, args } of cases) {
    assert.ok(Array.isArray(args), `${name}: args is a list`);
    assert.ok(
      value === null || typeof value === "string",
      `${name}: value is a string, or null for an absent key`,
    );
    const mode = value === null ? whenAbsent : value;
    assert.deepEqual(approvalArgs(mode), args, name);
    checked += 1;
  }
  assert.equal(checked, cases.length);
});

test("approval modes: an empty AGY_APPROVAL_MODE in the environment gives the flags of the empty example", () => {
  // The example for "" above calls approvalArgs directly. What the bot does
  // with an empty line in `.env` also depends on how agy.js reads the
  // environment when it loads (`??`, so an empty string wins over the
  // default and is not replaced by yolo). So load the bot's module the way
  // the bot starts, with that variable set to "". Modules are cached per
  // URL, so this runs in a fresh node process, with the home folder and the
  // working directory pointed at the throwaway folder.
  const cases = loadCases("approval-modes.json");
  const empty = cases.filter((item) => item.value === "");
  assert.equal(
    empty.length,
    1,
    "the shared examples have one case for an empty value",
  );
  const agyUrl = new URL("./agy.js", import.meta.url).href;
  const script = `
    const { approvalArgs, getChatSettings } = await import(${JSON.stringify(agyUrl)});
    const mode = getChatSettings(0).approvalMode;
    process.stdout.write(JSON.stringify({ mode, args: approvalArgs(mode) }));
    process.exit(0);
  `;
  const env = {
    ...process.env,
    HOME: scratch,
    AGY_WORKING_DIR: scratch,
    AGY_APPROVAL_MODE: "",
  };
  delete env.GEMINI_APPROVAL_MODE;
  delete env.GEMINI_WORKING_DIR;
  const run = spawnSync(
    process.execPath,
    ["--input-type=module", "-e", script],
    { env, encoding: "utf8" },
  );
  assert.equal(run.status, 0, `the bot's module did not load: ${run.stderr}`);
  const loaded = JSON.parse(run.stdout);
  assert.equal(loaded.mode, "", "the bot kept the empty mode, not its default");
  assert.deepEqual(loaded.args, empty[0].args, empty[0].name);
});

test(".env files: dotenv reads every shared file as written", () => {
  const cases = loadCases("env-files.json");
  let checked = 0;
  for (const { name, content, values } of cases) {
    assert.equal(typeof content, "string", `${name}: content is a string`);
    assert.ok(
      values !== null && typeof values === "object" && !Array.isArray(values),
      `${name}: values is an object`,
    );
    assert.deepEqual(dotenv.parse(content), values, name);
    checked += 1;
  }
  assert.equal(checked, cases.length);
});

test(".env lines: dotenv reads every shared example as written", () => {
  const cases = loadCases("env-lines.json");
  let checked = 0;
  for (const { name, line, key, value } of cases) {
    assert.equal(typeof line, "string", `${name}: line is a string`);
    assert.ok(
      (key === null && value === null) ||
        (typeof key === "string" && typeof value === "string"),
      `${name}: key and value are both strings, or both null`,
    );
    const expected = key === null ? {} : { [key]: value };
    assert.deepEqual(dotenv.parse(line), expected, name);
    checked += 1;
  }
  assert.equal(checked, cases.length);
});

test(".env values: what the apps write, dotenv reads back as the same value", () => {
  const cases = loadCases("env-written-values.json");
  let checked = 0;
  for (const { name, value, line, lossy } of cases) {
    assert.equal(typeof value, "string", `${name}: value is a string`);
    assert.equal(typeof line, "string", `${name}: line is a string`);
    const read = dotenv.parse(`K=${line}`).K;
    if (lossy === true) {
      // No spelling carries this value. The day one does, this fails, and
      // the case loses its `lossy` mark.
      assert.notEqual(read, value, `${name}: marked lossy, but it reads back`);
    } else {
      assert.equal(lossy, undefined, `${name}: lossy is true or left out`);
      assert.equal(read, value, name);
    }
    checked += 1;
  }
  assert.equal(checked, cases.length);
});

// ─── agy flags ───────────────────────────────────────────────────────────────
//
// What the bot passes agy depends on how it starts: bot.js loads `.env` with
// `import "dotenv/config"`, and agy.js then reads the process environment
// once, as it is imported. So each example starts the bot's modules that way
// in a fresh node process: its own folder holding the example's `.env`, a
// process environment with no setting of the bot's in it but the example's
// own, and the home folder pointed at that folder too. Nothing here starts
// agy: the flags are read from the bot's own argument builder, and AGY_BIN
// names a program that does nothing in case anything ever tried.

const dotenvConfigUrl = pathToFileURL(
  createRequire(import.meta.url).resolve("dotenv/config"),
).href;
const agyUrl = new URL("./agy.js", import.meta.url).href;

/**
 * Starts the bot's modules over `envText` and runs `body`, which leaves its
 * answer in `result`.
 * @param {string} envText - the whole `.env`
 * @param {Record<string, string>} environment - variables set before the bot starts
 * @param {string} body - statements run after the bot's modules are loaded
 * @returns {any}
 */
function startBot(envText, environment, body) {
  const folder = fs.mkdtempSync(path.join(scratch, "bot-"));
  fs.writeFileSync(path.join(folder, ".env"), envText);
  /** @type {Record<string, string | undefined>} */
  const env = {};
  for (const [key, value] of Object.entries(process.env)) {
    if (!/^(AGY_|GEMINI_|CLI_|DOTENV_)/.test(key)) env[key] = value;
  }
  Object.assign(env, { HOME: folder, AGY_BIN: "/usr/bin/false" }, environment);
  const script = `
    await import(${JSON.stringify(dotenvConfigUrl)});
    const bot = await import(${JSON.stringify(agyUrl)});
    let result;
    ${body}
    process.stdout.write("\\nRESULT " + JSON.stringify(result) + "\\n");
    process.exit(0);
  `;
  const run = spawnSync(
    process.execPath,
    ["--input-type=module", "-e", script],
    { env, cwd: folder, encoding: "utf8" },
  );
  assert.equal(run.status, 0, `the bot's modules did not load: ${run.stderr}`);
  // dotenv prints a line of its own when it loads a file; the answer is the
  // last line that starts with the marker.
  const line = run.stdout
    .split("\n")
    .filter((text) => text.startsWith("RESULT "))
    .pop();
  assert.ok(line, `the bot gave no answer: ${run.stdout}`);
  return JSON.parse(line.slice("RESULT ".length));
}

// The flags the bot gives agy after the prompt and the output format, for a
// chat nobody has changed a setting for.
const flagsBody = `
  const settings = bot.getChatSettings(0);
  const args = bot.buildAgyArgs("hi", settings, "stream-json", undefined, undefined);
  result = { head: args.slice(0, 4), flags: args.slice(4) };
`;

/** @param {any} item */
function checkShape(item) {
  assert.equal(typeof item.env, "string", `${item.name}: env is a string`);
  assert.ok(Array.isArray(item.args), `${item.name}: args is a list`);
}

test("agy flags: the bot, started over each shared .env, passes agy the flags the example says", () => {
  const cases = loadCases("agy-flags.json").filter(
    (item) => item.environment === undefined && item.custom === undefined,
  );
  assert.ok(cases.length > 0, "there are examples with a file alone");
  let checked = 0;
  for (const item of cases) {
    checkShape(item);
    assert.equal(
      item.apps,
      undefined,
      `${item.name}: with a file alone the apps pass what the bot passes, so there is no apps list`,
    );
    const answer = startBot(item.env, {}, flagsBody);
    assert.deepEqual(
      answer.head,
      ["-p", "hi", "--output-format", "stream-json"],
      `${item.name}: the flags follow the prompt and the format`,
    );
    assert.deepEqual(answer.flags, item.args, item.name);
    checked += 1;
  }
  assert.equal(checked, cases.length);
});

test("agy flags: a variable already set in the bot's process wins over the same line of .env", () => {
  const cases = loadCases("agy-flags.json").filter(
    (item) => item.environment !== undefined,
  );
  assert.ok(cases.length > 0, "there are examples with a process environment");
  let checked = 0;
  for (const item of cases) {
    checkShape(item);
    assert.ok(
      item.environment !== null &&
        typeof item.environment === "object" &&
        Object.values(item.environment).every((v) => typeof v === "string"),
      `${item.name}: environment is an object of strings`,
    );
    // The apps do not read their process environment, so these examples
    // say what they pass as well; the apps' own test checks that list.
    assert.ok(Array.isArray(item.apps), `${item.name}: apps is a list`);
    const answer = startBot(item.env, item.environment, flagsBody);
    assert.deepEqual(answer.flags, item.args, item.name);
    checked += 1;
  }
  assert.equal(checked, cases.length);
});

test("agy flags: a command of the user's own is run as written, with no effort flag added", () => {
  const cases = loadCases("agy-flags.json").filter(
    (item) => item.custom !== undefined,
  );
  assert.ok(
    cases.length > 0,
    "there is an example with a command of the user's own",
  );
  // The command is a stand-in that prints the arguments it was started
  // with, so what the bot really ran is what is compared.
  const echo = path.join(scratch, "print-arguments.mjs");
  fs.writeFileSync(
    echo,
    "process.stdout.write(JSON.stringify(process.argv.slice(2)));\n",
  );
  for (const file of [process.execPath, echo]) {
    assert.ok(!/['"]/.test(file), `${file} can be written inside quotes`);
  }
  const provider =
    "CLI_PROVIDER=custom\n" +
    `CLI_COMMAND_TEMPLATE='"${process.execPath}" "${echo}" {prompt}'\n`;
  let checked = 0;
  for (const item of cases) {
    checkShape(item);
    assert.equal(item.custom, true, `${item.name}: custom is true or left out`);
    const answer = startBot(
      item.env + provider,
      {},
      `result = { argv: JSON.parse((await bot.executePrompt("hi")).text) };`,
    );
    assert.deepEqual(answer.argv, ["hi", ...item.args], item.name);
    checked += 1;
  }
  assert.equal(checked, cases.length);
});
