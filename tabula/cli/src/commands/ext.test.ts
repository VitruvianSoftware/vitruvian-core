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

import os from "os";
import path from "path";

jest.mock("child_process", () => ({
  spawnSync: jest.fn(),
}));
// eslint-disable-next-line import/first
import { spawnSync } from "child_process";
// eslint-disable-next-line import/first
import { extCommand, runTool } from "./ext";

describe("extCommand wiring", () => {
  it("exposes update and path subcommands", () => {
    const names = extCommand.commands.map((c) => c.name());
    expect(names).toContain("update");
    expect(names).toContain("path");
  });

  it("path defaults to ~/.tabula/extension", () => {
    const pathCmd = extCommand.commands.find((c) => c.name() === "path")!;
    const dirOpt = pathCmd.options.find((o) => o.long === "--dir")!;
    expect(dirOpt.defaultValue).toBe(
      path.join(os.homedir(), ".tabula", "extension"),
    );
  });
});

describe("runTool", () => {
  it("explains when the tool is not installed", () => {
    (spawnSync as jest.Mock).mockReturnValue({
      error: Object.assign(new Error("spawn gh ENOENT"), { code: "ENOENT" }),
      status: null,
    });
    expect(() => runTool("gh", ["release", "download"])).toThrow(
      /'gh' not found on PATH/,
    );
  });

  it("surfaces non-zero exits with the command line", () => {
    (spawnSync as jest.Mock).mockReturnValue({ error: undefined, status: 1 });
    expect(() => runTool("unzip", ["-o"])).toThrow(
      /unzip -o failed \(exit 1\)/,
    );
  });
});
