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
  STABLE_CHANNEL_MESSAGE,
  type InstallChannel,
  atomicInstall,
  defaultExtensionDir,
  readBundleInfo,
  readInstalledChannel,
  resolveBetaArtifact,
  resolveChannel,
  writeInstalledChannel,
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

/** Run an external tool capturing stdout (stderr still inherited). */
export function runToolCapture(cmd: string, args: string[]): string {
  const res = spawnSync(cmd, args, {
    stdio: ["ignore", "pipe", "inherit"],
    encoding: "utf-8",
  });
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
  return res.stdout ?? "";
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
    "Download the channel's latest build into the load-unpacked directory",
  )
  .option("--dir <path>", "extension directory", defaultExtensionDir())
  .option("--repo <owner/repo>", "GitHub repository", DEFAULT_REPO)
  .option(
    "--channel <channel>",
    "release channel: alpha (every main commit) | beta (latest release cut) | stable (M3). Defaults to the installed channel, else alpha.",
  )
  .action((opts: { dir: string; repo: string; channel?: string }) => {
    try {
      const flag = opts.channel?.trim().toLowerCase();
      if (flag === "stable") {
        // Non-fatal by design (spec): guidance, not an error.
        console.log(chalk.yellow(STABLE_CHANNEL_MESSAGE));
        return;
      }

      const target = path.resolve(opts.dir);
      const channel: InstallChannel = resolveChannel(
        flag,
        readInstalledChannel(target),
      );

      // Per-channel artifact: alpha = the rolling dev-latest prerelease;
      // beta = the newest tabula-extension-v* release (the cut's own zip,
      // promoted — never rebuilt).
      let tag = DEV_LATEST_TAG;
      let zipName = "tabula-extension-chrome.zip";
      if (channel === "beta") {
        const listJson = runToolCapture("gh", [
          "release",
          "list",
          "--repo",
          opts.repo,
          "--limit",
          "100",
          "--json",
          "tagName",
        ]);
        const artifact = resolveBetaArtifact(listJson);
        if (!artifact) {
          throw new Error(
            `No tabula-extension-v* release found in ${opts.repo} — the beta channel needs at least one release cut.`,
          );
        }
        tag = artifact.tag;
        zipName = artifact.zipName;
      }

      const downloadDir = fs.mkdtempSync(path.join(os.tmpdir(), "tabula-ext-"));
      // Staging must share a filesystem with the target for an atomic rename.
      const staging = `${target}.staging-${process.pid}`;
      try {
        console.log(`Fetching ${tag} (${channel}) from ${opts.repo}…`);
        try {
          runTool("gh", [
            "release",
            "download",
            tag,
            "--repo",
            opts.repo,
            "--pattern",
            zipName,
            "--dir",
            downloadDir,
            "--clobber",
          ]);
        } catch (downloadError) {
          if (channel === "beta" && downloadError instanceof Error) {
            // release-please creates the release before the workflow
            // attaches the zip — a just-cut release can briefly be empty.
            throw new Error(
              `${downloadError.message} — the release may still be publishing its assets; retry in a minute.`,
            );
          }
          throw downloadError;
        }
        // A run killed mid-unzip strands this dir; with a recycled pid the
        // overlayed unzip below could leak stale files into the install.
        fs.rmSync(staging, { recursive: true, force: true });
        fs.mkdirSync(staging, { recursive: true });
        runTool("unzip", [
          "-o",
          "-q",
          path.join(downloadDir, zipName),
          "-d",
          staging,
        ]);
        atomicInstall(staging, target);
        // Label only a SUCCESSFUL install — a failed update must never
        // relabel the surviving previous install.
        writeInstalledChannel(target, channel);

        const info = readBundleInfo(target);
        const identity = [
          info?.version ? `v${info.version}` : null,
          info?.commit ? `(${info.commit.slice(0, 7)})` : null,
        ]
          .filter(Boolean)
          .join(" ");
        console.log(
          chalk.green(
            `✓ Installed ${channel} ${identity || "build"} → ${target}`,
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
