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

import fs from "fs";
import os from "os";
import path from "path";
import {
  atomicInstall,
  compareSemver,
  defaultExtensionDir,
  readBundleInfo,
  readInstalledChannel,
  resolveBetaArtifact,
  resolveChannel,
  resolveLatestExtensionTag,
  validateBundleDir,
  writeInstalledChannel,
} from "./extension";

const mkTmp = (): string =>
  fs.mkdtempSync(path.join(os.tmpdir(), "tabula-ext-test-"));

const writeBundle = (dir: string, commit = "abc1234"): void => {
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(
    path.join(dir, "manifest.json"),
    JSON.stringify({ name: "Tabula" }),
  );
  fs.writeFileSync(
    path.join(dir, "build_info.json"),
    JSON.stringify({ commit }),
  );
};

describe("defaultExtensionDir", () => {
  it("is ~/.tabula/extension", () => {
    expect(defaultExtensionDir()).toBe(
      path.join(os.homedir(), ".tabula", "extension"),
    );
  });
});

describe("readBundleInfo", () => {
  it("reads commit from build_info.json", () => {
    const dir = mkTmp();
    writeBundle(dir, "deadbee");
    expect(readBundleInfo(dir)).toEqual({ commit: "deadbee" });
  });

  it("returns null when the file is missing or invalid", () => {
    const dir = mkTmp();
    expect(readBundleInfo(dir)).toBeNull();
    fs.writeFileSync(path.join(dir, "build_info.json"), "not json");
    expect(readBundleInfo(dir)).toBeNull();
  });
});

describe("validateBundleDir", () => {
  it("throws when manifest.json is missing", () => {
    const dir = mkTmp();
    expect(() => validateBundleDir(dir)).toThrow(/manifest\.json/);
  });
});

describe("atomicInstall", () => {
  it("installs a fresh bundle when no previous install exists", () => {
    const root = mkTmp();
    const staging = path.join(root, "staging");
    const target = path.join(root, "extension");
    writeBundle(staging);

    atomicInstall(staging, target);

    expect(fs.existsSync(path.join(target, "manifest.json"))).toBe(true);
    expect(fs.existsSync(staging)).toBe(false); // staging was moved, not copied
  });

  it("replaces a previous install and leaves no leftovers", () => {
    const root = mkTmp();
    const staging = path.join(root, "staging");
    const target = path.join(root, "extension");
    writeBundle(target, "oldcommit");
    writeBundle(staging, "newcommit");

    atomicInstall(staging, target);

    expect(readBundleInfo(target)).toEqual({ commit: "newcommit" });
    // no .old-* / staging dirs left behind
    expect(fs.readdirSync(root)).toEqual(["extension"]);
  });

  it("leaves the existing install untouched when the staging bundle is invalid", () => {
    const root = mkTmp();
    const staging = path.join(root, "staging");
    const target = path.join(root, "extension");
    writeBundle(target, "oldcommit");
    fs.mkdirSync(staging, { recursive: true }); // no manifest.json -> invalid

    expect(() => atomicInstall(staging, target)).toThrow(/manifest\.json/);
    expect(readBundleInfo(target)).toEqual({ commit: "oldcommit" });
  });

  it("rolls the previous install back when the final swap fails", () => {
    const root = mkTmp();
    const staging = path.join(root, "staging");
    const target = path.join(root, "extension");
    writeBundle(target, "oldcommit");
    writeBundle(staging, "newcommit");

    // Force the staging -> target rename to fail after the old dir was moved:
    // 1st call (target -> old) real, 2nd (staging -> target) throws, then real
    // again so the rollback rename succeeds.
    const realRename = jest.requireActual("fs")
      .renameSync as typeof fs.renameSync;
    const renameSpy = jest
      .spyOn(fs, "renameSync")
      .mockImplementationOnce((a, b) => realRename(a, b))
      .mockImplementationOnce(() => {
        throw new Error("simulated rename failure");
      })
      .mockImplementation((a, b) => realRename(a, b));

    expect(() => atomicInstall(staging, target)).toThrow(
      /simulated rename failure/,
    );
    renameSpy.mockRestore();

    expect(readBundleInfo(target)).toEqual({ commit: "oldcommit" });
    expect(readBundleInfo(staging)).toEqual({ commit: "newcommit" }); // bundle not consumed on failure
  });
});

describe("channel helpers", () => {
  it("readInstalledChannel reads a valid channel.json", () => {
    const dir = mkTmp();
    fs.writeFileSync(
      path.join(dir, "channel.json"),
      JSON.stringify({ channel: "beta" }),
    );
    expect(readInstalledChannel(dir)).toBe("beta");
  });

  it("readInstalledChannel returns null for absent, corrupt, or unknown values", () => {
    const dir = mkTmp();
    expect(readInstalledChannel(dir)).toBeNull();
    fs.writeFileSync(path.join(dir, "channel.json"), "not json");
    expect(readInstalledChannel(dir)).toBeNull();
    fs.writeFileSync(
      path.join(dir, "channel.json"),
      JSON.stringify({ channel: "stable" }),
    );
    expect(readInstalledChannel(dir)).toBeNull();
  });

  it("writeInstalledChannel round-trips", () => {
    const dir = mkTmp();
    writeInstalledChannel(dir, "alpha");
    expect(readInstalledChannel(dir)).toBe("alpha");
  });
});

describe("resolveChannel", () => {
  it("explicit flag wins over installed channel", () => {
    expect(resolveChannel("beta", "alpha")).toBe("beta");
  });

  it("falls back to the installed channel, then alpha", () => {
    expect(resolveChannel(undefined, "beta")).toBe("beta");
    expect(resolveChannel(undefined, null)).toBe("alpha");
  });

  it("explains that stable arrives with the Web Store listing (M3)", () => {
    expect(() => resolveChannel("stable", null)).toThrow(/Web Store.*M3/);
  });

  it("rejects unknown channels listing the valid ones", () => {
    expect(() => resolveChannel("nightly", null)).toThrow(
      /alpha, beta, stable/,
    );
  });
});

describe("compareSemver", () => {
  it("orders numerically per segment", () => {
    expect(compareSemver("0.10.0", "0.9.9")).toBeGreaterThan(0);
    expect(compareSemver("1.0.0", "1.0.0")).toBe(0);
    expect(compareSemver("0.1.9", "0.2.0")).toBeLessThan(0);
  });

  it("treats missing segments as zero", () => {
    expect(compareSemver("1.0", "1.0.0")).toBe(0);
    expect(compareSemver("1.0.1", "1.0")).toBeGreaterThan(0);
  });
});

describe("resolveLatestExtensionTag", () => {
  it("picks the highest tabula-extension-v* among monorepo tag noise", () => {
    const json = JSON.stringify([
      { tagName: "tabula-cli-v0.3.0" },
      { tagName: "tabula-extension-v0.1.9" },
      { tagName: "tabula-extension-dev-latest" },
      { tagName: "tabula-extension-v0.1.10" },
      { tagName: "devx-v1.2.3" },
      { tagName: "tabula-extension-v0.1.2" },
    ]);
    expect(resolveLatestExtensionTag(json)).toBe("tabula-extension-v0.1.10");
  });

  it("returns null when no extension release exists", () => {
    expect(
      resolveLatestExtensionTag(JSON.stringify([{ tagName: "devx-v1.0.0" }])),
    ).toBeNull();
    expect(resolveLatestExtensionTag("[]")).toBeNull();
  });

  it("returns null on unparseable input", () => {
    expect(resolveLatestExtensionTag("gh exploded")).toBeNull();
  });
});

describe("resolveBetaArtifact", () => {
  it("returns the tag and its -chrome.zip asset name", () => {
    const json = JSON.stringify([{ tagName: "tabula-extension-v0.1.10" }]);
    expect(resolveBetaArtifact(json)).toEqual({
      tag: "tabula-extension-v0.1.10",
      zipName: "tabula-extension-v0.1.10-chrome.zip",
    });
  });

  it("returns null when no extension release exists", () => {
    expect(resolveBetaArtifact("[]")).toBeNull();
  });
});
