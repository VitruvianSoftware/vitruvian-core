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
import { extCommand, runTool, runToolCapture } from "./ext";

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

describe("update --channel option", () => {
  it("declares the --channel option", () => {
    const updateCmd = extCommand.commands.find((c) => c.name() === "update")!;
    const chOpt = updateCmd.options.find((o) => o.long === "--channel");
    expect(chOpt).toBeDefined();
    expect(chOpt!.defaultValue).toBeUndefined(); // installed channel decides
  });
});

describe("update action branching", () => {
  let exitSpy: jest.SpyInstance;
  let logSpy: jest.SpyInstance;
  let errorSpy: jest.SpyInstance;

  beforeEach(() => {
    jest.clearAllMocks();
    exitSpy = jest
      .spyOn(process, "exit")
      .mockImplementation((() => undefined) as never);
    logSpy = jest.spyOn(console, "log").mockImplementation(() => {});
    errorSpy = jest.spyOn(console, "error").mockImplementation(() => {});
  });

  afterEach(() => {
    exitSpy.mockRestore();
    logSpy.mockRestore();
    errorSpy.mockRestore();
  });

  it("stable (any casing) prints guidance and never spawns a tool", () => {
    const updateCmd = extCommand.commands.find((c) => c.name() === "update")!;
    updateCmd.parse(["--channel", "STABLE"], { from: "user" });
    expect(spawnSync).not.toHaveBeenCalled();
    expect(exitSpy).not.toHaveBeenCalled();
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("Web Store listing (M3)"),
    );
  });

  it("beta plumbs the resolved tag into the download args", () => {
    (spawnSync as jest.Mock)
      .mockReturnValueOnce({
        error: undefined,
        status: 0,
        stdout: JSON.stringify([{ tagName: "tabula-extension-v0.1.10" }]),
      })
      // download call fails — we only care about its argument plumbing
      .mockReturnValueOnce({ error: undefined, status: 1 });
    const updateCmd = extCommand.commands.find((c) => c.name() === "update")!;
    updateCmd.parse(
      ["--channel", "beta", "--dir", "/tmp/tabula-ext-beta-test"],
      {
        from: "user",
      },
    );

    const downloadArgs = (spawnSync as jest.Mock).mock.calls[1][1] as string[];
    expect(downloadArgs).toEqual(
      expect.arrayContaining([
        "download",
        "tabula-extension-v0.1.10",
        "--pattern",
        "tabula-extension-v0.1.10-chrome.zip",
      ]),
    );
    expect(exitSpy).toHaveBeenCalledWith(1); // download failed -> command failed
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("may still be publishing"),
    );
  });
});

describe("runToolCapture", () => {
  it("returns captured stdout on success", () => {
    (spawnSync as jest.Mock).mockReturnValue({
      error: undefined,
      status: 0,
      stdout: '[{"tagName":"tabula-extension-v0.1.9"}]',
    });
    expect(runToolCapture("gh", ["release", "list"])).toBe(
      '[{"tagName":"tabula-extension-v0.1.9"}]',
    );
  });

  it("explains when the tool is not installed", () => {
    (spawnSync as jest.Mock).mockReturnValue({
      error: Object.assign(new Error("spawn gh ENOENT"), { code: "ENOENT" }),
      status: null,
    });
    expect(() => runToolCapture("gh", ["release", "list"])).toThrow(
      /'gh' not found on PATH/,
    );
  });

  it("surfaces non-zero exits with the command line", () => {
    (spawnSync as jest.Mock).mockReturnValue({
      error: undefined,
      status: 1,
      stdout: "",
    });
    expect(() => runToolCapture("gh", ["release", "list"])).toThrow(
      /gh release list failed \(exit 1\)/,
    );
  });
});
