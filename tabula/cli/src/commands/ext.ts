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

import { Command } from "commander";
import chalk from "chalk";
import { spawnSync } from "child_process";
import fs from "fs";
import os from "os";
import path from "path";
import {
  DEFAULT_REPO,
  DEV_LATEST_TAG,
  atomicInstall,
  defaultExtensionDir,
  readBundleInfo,
} from "../utils/extension";

/** Run an external tool, inheriting stdout/stderr; throw helpful errors. */
export function runTool(cmd: string, args: string[]): void {
  const res = spawnSync(cmd, args, { stdio: ["ignore", "inherit", "inherit"] });
  if (res.error && (res.error as NodeJS.ErrnoException).code === "ENOENT") {
    throw new Error(
      `'${cmd}' not found on PATH — install it first (${
        cmd === "gh" ? "https://cli.github.com + 'gh auth login'" : cmd
      }).`,
    );
  }
  if (res.error) throw res.error;
  if (res.status !== 0) {
    throw new Error(`${cmd} ${args.join(" ")} failed (exit ${res.status})`);
  }
}

export const extCommand = new Command("ext").description(
  "Manage the local load-unpacked dev extension install",
);

extCommand
  .command("path")
  .description("Print the load-unpacked extension directory")
  .option("--dir <path>", "extension directory", defaultExtensionDir())
  .action((opts: { dir: string }) => {
    console.log(path.resolve(opts.dir));
  });

extCommand
  .command("update")
  .description(
    "Download the latest dev build (rolling dev-latest release) into the load-unpacked directory",
  )
  .option("--dir <path>", "extension directory", defaultExtensionDir())
  .option("--repo <owner/repo>", "GitHub repository", DEFAULT_REPO)
  .action((opts: { dir: string; repo: string }) => {
    try {
      const target = path.resolve(opts.dir);
      const downloadDir = fs.mkdtempSync(path.join(os.tmpdir(), "tabula-ext-"));
      // Staging must share a filesystem with the target for an atomic rename.
      const staging = `${target}.staging-${process.pid}`;
      try {
        console.log(`Fetching ${DEV_LATEST_TAG} from ${opts.repo}…`);
        runTool("gh", [
          "release",
          "download",
          DEV_LATEST_TAG,
          "--repo",
          opts.repo,
          "--pattern",
          "tabula-extension-chrome.zip",
          "--dir",
          downloadDir,
          "--clobber",
        ]);
        // A run killed mid-unzip strands this dir; with a recycled pid the
        // overlayed unzip below could leak stale files into the install.
        fs.rmSync(staging, { recursive: true, force: true });
        fs.mkdirSync(staging, { recursive: true });
        runTool("unzip", [
          "-o",
          "-q",
          path.join(downloadDir, "tabula-extension-chrome.zip"),
          "-d",
          staging,
        ]);
        atomicInstall(staging, target);

        const commit = readBundleInfo(target)?.commit;
        console.log(
          chalk.green(
            `✓ Installed dev build ${commit ? commit.slice(0, 7) : "(unknown commit)"} → ${target}`,
          ),
        );
        console.log(
          "  Reload the extension to load it (banner button, or chrome://extensions → ↻).",
        );
        console.log(
          `  First time? chrome://extensions → Developer mode → "Load unpacked" → ${target}`,
        );
      } finally {
        fs.rmSync(downloadDir, { recursive: true, force: true });
        fs.rmSync(staging, { recursive: true, force: true });
      }
    } catch (error) {
      if (error instanceof Error) {
        console.error(chalk.red(error.message));
      }
      process.exit(1);
    }
  });
