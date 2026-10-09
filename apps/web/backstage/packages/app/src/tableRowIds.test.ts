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

import { createRequire } from "module";
import path from "path";

// Backstage's tables are @material-table/core, which reaches the app only
// through @backstage/core-components. Resolve it from there, the way the
// bundler does, so this test sees the copy (and the uuid) the pages get.
const fromCoreComponents = createRequire(
  path.join(
    path.dirname(require.resolve("@backstage/core-components/package.json")),
    "index.js",
  ),
);

describe("the table library Backstage pages render with", () => {
  it("gives every row an id", () => {
    // The real path: every table calls setData on mount, and setData stamps
    // each row with uuid.v4(). With a uuid that has no default export this
    // throws "Cannot read properties of undefined (reading 'v4')", which is
    // the error the whole catalog page showed on 2026-10-09.
    const DataManager = fromCoreComponents(
      "@material-table/core/dist/utils/data-manager",
    ).default;
    const manager = new DataManager();

    manager.setData([{ name: "a" }, { name: "b" }]);

    const ids = manager.data.map(
      (row: { tableData?: { uuid?: unknown } }) => row.tableData?.uuid,
    );
    expect(ids.every((id: unknown) => typeof id === "string")).toBe(true);
    expect(new Set(ids).size).toBe(2);
  });
});
