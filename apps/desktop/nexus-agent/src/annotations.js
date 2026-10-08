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

import fs from "node:fs";
import path from "node:path";

// What the user did to an Antigravity conversation. agy keeps it out of the
// conversation index, in `annotations/<id>.pbtxt` (protobuf text) beside the
// conversation, so the index's `killed` column says nothing about archiving:
// it marks an aborted run.

// A quoted string, or the `archived` field. Strings are matched so a title
// cannot pass for the field.
const ARCHIVED_FIELD =
  /"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|\barchived\s*:\s*(true|false)\b/g;

/**
 * Whether an annotation (`archived:true` or `archived: true`) marks its
 * conversation archived.
 * @param {string} text
 * @returns {boolean}
 */
export function annotationIsArchived(text) {
  let archived = false;
  for (const match of text.matchAll(ARCHIVED_FIELD)) {
    if (match[1]) archived = match[1] === "true";
  }
  return archived;
}

/**
 * The conversations marked archived in the `annotations` folder of each of
 * agy's data directories.
 * @param {string[]} dataDirs
 * @returns {Set<string>}
 */
export function archivedConversationIds(dataDirs) {
  /** @type {Set<string>} */
  const archived = new Set();
  for (const dir of dataDirs) {
    const annotations = path.join(dir, "annotations");
    /** @type {string[]} */
    let names = [];
    try {
      names = fs.readdirSync(annotations);
    } catch {
      /* no annotations in this data directory */
    }
    for (const name of names) {
      if (!name.endsWith(".pbtxt")) continue;
      try {
        const text = fs.readFileSync(path.join(annotations, name), "utf8");
        if (annotationIsArchived(text))
          archived.add(name.slice(0, -".pbtxt".length));
      } catch {
        /* unreadable annotation: treat as not archived */
      }
    }
  }
  return archived;
}
