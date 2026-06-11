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
import inquirer from "inquirer";
import ora from "ora";
import { execSync } from "child_process";
import { getConfig, saveConfig } from "../utils/config";

export const authCommand = new Command("auth").description(
  "Manage authentication for external services",
);

authCommand
  .command("neon")
  .description("Authenticate with Neon (Serverless Postgres)")
  .action(async () => {
    console.log(chalk.bold("\n🔌 Neon Authentication Setup\n"));

    // Check if already authenticated
    if (process.env.NEON_API_KEY) {
      const spinner = ora("Checking existing authentication...").start();
      try {
        execSync("npx neonctl me", { stdio: "ignore" });
        spinner.succeed("Already authenticated with Neon!");

        // Sync to config if missing
        try {
          const config = getConfig();
          if (!config.neonApiKey) {
            config.neonApiKey = process.env.NEON_API_KEY;
            saveConfig(config);
            console.log(chalk.green("✓ Synced API Key to local configuration"));
          }
        } catch (e) {
          // Ignore
        }

        const { reauth } = await inquirer.prompt([
          {
            type: "confirm",
            name: "reauth",
            message: "Do you want to re-authenticate?",
            default: false,
          },
        ]);

        if (!reauth) return;
      } catch (e) {
        spinner.fail("Existing NEON_API_KEY is invalid or expired.");
      }
    }

    console.log(chalk.blue("To authenticate, you need a Neon API Key."));
    console.log(
      `1. Go to ${chalk.underline("https://console.neon.tech/app/settings/api-keys")}`,
    );
    console.log("2. Create a new API key");
    console.log("");

    const { apiKey } = await inquirer.prompt([
      {
        type: "password",
        name: "apiKey",
        message: "Enter your Neon API Key:",
        validate: (input) => (input.length > 0 ? true : "API Key is required"),
      },
    ]);

    const spinner = ora("Verifying API Key...").start();

    try {
      // Verify key
      execSync("npx neonctl me", {
        env: { ...process.env, NEON_API_KEY: apiKey },
        stdio: "ignore",
      });
      spinner.succeed("Authentication successful!");

      // Try to store in Google Secret Manager first
      let storedInGsm = false;
      try {
        const config = getConfig();
        if (config.projectId) {
          const gsmSpinner = ora(
            "Storing key in Google Secret Manager...",
          ).start();
          try {
            execSync(
              `printf '%s' "${apiKey}" | gcloud secrets create NEON_API_KEY --data-file=- --project=${config.projectId} 2>/dev/null || printf '%s' "${apiKey}" | gcloud secrets versions add NEON_API_KEY --data-file=- --project=${config.projectId}`,
              { stdio: "pipe" },
            );
            gsmSpinner.succeed("API Key saved to Google Secret Manager");
            storedInGsm = true;
          } catch (e) {
            gsmSpinner.warn(
              "Could not store in Google Secret Manager (Project might not exist yet)",
            );
          }
        }
      } catch (e) {
        // Config might not exist
      }

      // Fallback: Save to local config if not in GSM
      if (!storedInGsm) {
        try {
          const config = getConfig();
          config.neonApiKey = apiKey;
          saveConfig(config);
          console.log(
            chalk.yellow(
              "⚠ Stored API Key in local configuration (GSM unavailable)",
            ),
          );
        } catch (e) {
          console.error(chalk.red("Failed to save API Key configuration"));
        }
      } else {
        // If stored in GSM, ensure we don't have it locally
        try {
          const config = getConfig();
          if (config.neonApiKey) {
            delete config.neonApiKey;
            saveConfig(config);
            console.log(
              chalk.green("✓ Removed API Key from local configuration"),
            );
          }
        } catch (e) {
          // Ignore error if config cannot be read/saved during cleanup
        }
      }
    } catch (error) {
      spinner.fail("Authentication failed. Please check your API Key.");
      process.exit(1);
    }
  });

authCommand
  .command("gcloud")
  .description("Authenticate with Google Cloud Platform")
  .action(async () => {
    console.log(chalk.bold("\n☁️  Google Cloud Authentication\n"));

    const spinner = ora("Checking gcloud installation...").start();
    try {
      execSync("gcloud --version", { stdio: "ignore" });
      spinner.succeed("gcloud CLI is installed");
    } catch (error: unknown) {
      spinner.fail("gcloud CLI check failed");
      const err = error as { code?: string; message: string };
      if (err.code === "ENOENT") {
        console.error(chalk.red("gcloud CLI is not installed or not in PATH."));
        console.error(chalk.red("Please install Google Cloud SDK first."));
      } else {
        console.error(
          chalk.red(`An error occurred while checking gcloud: ${err.message}`),
        );
      }
      process.exit(1);
    }

    console.log(chalk.blue("Launching gcloud authentication..."));

    try {
      // 1. Authenticate gcloud CLI (for running gcloud commands)
      console.log(chalk.yellow("\nStep 1: Authenticating gcloud CLI..."));
      execSync("gcloud auth login", { stdio: "inherit" });

      // 2. Authenticate Application Default Credentials (for Terraform/Code)
      console.log(
        chalk.yellow("\nStep 2: Setting up Application Default Credentials..."),
      );
      execSync("gcloud auth application-default login", { stdio: "inherit" });

      console.log(
        chalk.green("\n✅ Successfully authenticated with Google Cloud!"),
      );
    } catch (error) {
      console.error(chalk.red("\n❌ Authentication failed"));
      process.exit(1);
    }
  });
