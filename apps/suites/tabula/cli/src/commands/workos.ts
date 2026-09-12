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
import { spawn, execSync, exec } from "child_process";
import { getConfig } from "../utils/config";
import { loadWorkOSApiKey } from "../utils/secrets";

/**
 * Open URL in default browser (cross-platform)
 */
function openBrowser(url: string): void {
  let cmd: string;
  if (process.platform === "darwin") {
    cmd = "open";
  } else if (process.platform === "win32") {
    cmd = "start";
  } else {
    cmd = "xdg-open";
  }
  exec(`${cmd} ${url}`);
}

/**
 * Get Cloud Run service URLs for all environments
 */
function getCloudRunUrls(projectId: string): Map<string, string> {
  const urls = new Map<string, string>();

  try {
    const result = execSync(
      `gcloud run services list --project ${projectId} --format="csv[no-heading](metadata.name,status.url)"`,
      { encoding: "utf-8" },
    );

    result
      .trim()
      .split("\n")
      .filter((line) => line.includes("tabula-api"))
      .forEach((line) => {
        const [name, url] = line.split(",");
        if (name && url) {
          // Extract environment from service name (e.g., tabula-api-stg -> stg)
          const envMatch = name.match(/tabula-api-(\w+)/);
          if (envMatch) {
            urls.set(envMatch[1], url);
          }
        }
      });
  } catch (error) {
    console.error(
      chalk.red(
        "Failed to fetch Cloud Run services. Make sure gcloud is configured.",
      ),
    );
    throw error;
  }

  return urls;
}

/**
 * Generate callback URLs from Cloud Run URLs
 */
function generateCallbackUrls(cloudRunUrls: Map<string, string>): string[] {
  const callbacks: string[] = [];

  cloudRunUrls.forEach((url, _env) => {
    // Append /api/v1/auth/callback to each Cloud Run URL
    callbacks.push(`${url}/api/v1/auth/callback`);
  });

  // Also add localhost for development
  callbacks.push("http://localhost:8080/api/v1/auth/callback");

  return callbacks;
}

const syncRedirectsCommand = new Command("sync-redirects")
  .description("Display WorkOS redirect URIs that need to be configured")
  .option("--open", "Open WorkOS dashboard in browser")
  .option("--json", "Output as JSON")
  .action(async (options) => {
    let config;
    try {
      config = getConfig();
    } catch (error) {
      console.error(
        chalk.red('Configuration not found. Please run "tabcli init" first.'),
      );
      process.exit(1);
    }

    console.log(chalk.blue("🔍 Fetching Cloud Run service URLs...\n"));

    try {
      const cloudRunUrls = getCloudRunUrls(config.projectId);

      if (cloudRunUrls.size === 0) {
        console.log(chalk.yellow("No Cloud Run API services found."));
        console.log(
          chalk.gray("Make sure you have deployed your API services first."),
        );
        process.exit(0);
      }

      console.log(chalk.green("✓ Found Cloud Run services:\n"));
      cloudRunUrls.forEach((url, env) => {
        console.log(`  ${chalk.cyan(env.padEnd(10))} ${url}`);
      });
      console.log();

      const callbackUrls = generateCallbackUrls(cloudRunUrls);

      if (options.json) {
        console.log(JSON.stringify({ redirectUris: callbackUrls }, null, 2));
        return;
      }

      console.log(chalk.blue("📋 Redirect URIs to configure in WorkOS:\n"));
      console.log(
        chalk.gray(
          "Copy and paste these into your WorkOS Dashboard > Redirects:\n",
        ),
      );

      callbackUrls.forEach((url) => {
        console.log(`  ${chalk.white(url)}`);
      });

      console.log();
      console.log(chalk.gray("━".repeat(60)));
      console.log();
      console.log(
        chalk.yellow(
          "⚠️  WorkOS does not support programmatic redirect URI configuration.",
        ),
      );
      console.log(
        chalk.yellow("   You must add these manually in the WorkOS Dashboard."),
      );
      console.log();
      console.log(
        chalk.blue("   Dashboard: ") +
          chalk.underline("https://dashboard.workos.com/redirects"),
      );
      console.log();

      if (options.open) {
        console.log(chalk.green("🌐 Opening WorkOS Dashboard..."));
        openBrowser("https://dashboard.workos.com/redirects");
      } else {
        console.log(
          chalk.gray("   Use --open to open the dashboard in your browser."),
        );
      }
    } catch (error) {
      console.error(
        chalk.red("Error:"),
        error instanceof Error ? error.message : error,
      );
      process.exit(1);
    }
  });

export const workosCommand = new Command("workos")
  .description("WorkOS CLI wrapper with automatic authentication")
  .addCommand(syncRedirectsCommand);

// Default action for passthrough to WorkOS CLI
workosCommand.allowUnknownOption().action(async (_options, command) => {
  // If no subcommand matched, pass through to WorkOS CLI
  let config;
  try {
    config = getConfig();
  } catch (error) {
    console.error(
      chalk.red('Configuration not found. Please run "tabcli init" first.'),
    );
    process.exit(1);
  }

  // Load API Key
  const env = command.opts().env || "dev";
  loadWorkOSApiKey(config, env);

  if (!process.env.WORKOS_API_KEY) {
    console.error(chalk.red("Failed to load WORKOS_API_KEY. Cannot proceed."));
    process.exit(1);
  }

  // Inject for headless mode
  if (process.env.WORKOS_API_KEY) {
    process.env.WORKOS_ACTIVE_ENVIRONMENT = "headless";
    process.env.WORKOS_ENVIRONMENTS_HEADLESS_API_KEY =
      process.env.WORKOS_API_KEY;
    process.env.WORKOS_ENVIRONMENTS_HEADLESS_NAME = "dev";
    process.env.WORKOS_ENVIRONMENTS_HEADLESS_ENDPOINT =
      "https://api.workos.com";
  }

  const args = process.argv;
  const workosIndex = args.findIndex((arg) => arg === "workos");
  const workosArgs = workosIndex >= 0 ? args.slice(workosIndex + 1) : [];

  // Filter out our own options
  const filteredArgs = workosArgs.filter((arg, index) => {
    if (arg === "--env" || arg === "-e") return false;
    if (workosArgs[index - 1] === "--env" || workosArgs[index - 1] === "-e")
      return false;
    return true;
  });

  console.log(chalk.gray(`Running: workos ${filteredArgs.join(" ")}\n`));

  const child = spawn("workos", filteredArgs, {
    stdio: "inherit",
    env: { ...process.env },
  });

  child.on("close", (code) => {
    process.exit(code ?? 0);
  });
});

// Add --env option for environment selection
workosCommand.option(
  "-e, --env <environment>",
  "Environment to use (dev/staging/prod)",
  "dev",
);
