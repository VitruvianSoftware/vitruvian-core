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

import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import {
  annotationIsArchived,
  archivedConversationIds,
} from "./annotations.js";

test("archived in the shapes agy writes", () => {
  assert.equal(
    annotationIsArchived(
      "archived:true archival_status_timestamp:{seconds:1787464769 nanos:503730000} marked_as_unread:false",
    ),
    true,
  );
  assert.equal(
    annotationIsArchived(
      'title:"Daily Briefing"  archived: true  last_user_view_time:{seconds:1  nanos:2}',
    ),
    true,
  );
});

test("not archived without the field", () => {
  assert.equal(
    annotationIsArchived(
      "last_user_view_time:{seconds:1790974412  nanos:316000000}",
    ),
    false,
  );
  assert.equal(annotationIsArchived("archived:false pinned:true"), false);
  assert.equal(annotationIsArchived(""), false);
});

test("a title cannot pass for the field", () => {
  assert.equal(
    annotationIsArchived('title:"why is archived:true ignored" pinned:true'),
    false,
  );
});

test("archived ids are collected across data directories", () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "nexus-annotations-"));
  const app = path.join(home, "antigravity");
  const cli = path.join(home, "antigravity-cli");
  for (const dir of [app, cli])
    fs.mkdirSync(path.join(dir, "annotations"), { recursive: true });
  fs.writeFileSync(path.join(app, "annotations/a.pbtxt"), "archived:true");
  fs.writeFileSync(path.join(app, "annotations/b.pbtxt"), "pinned:true");
  fs.writeFileSync(path.join(cli, "annotations/c.pbtxt"), "archived: true");
  fs.writeFileSync(path.join(cli, "annotations/notes.txt"), "archived:true");

  assert.deepEqual([...archivedConversationIds([app, cli])].sort(), ["a", "c"]);
  assert.deepEqual(
    [...archivedConversationIds([path.join(home, "missing")])],
    [],
  );
});
