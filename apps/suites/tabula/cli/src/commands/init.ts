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
import fs from "fs";
import path from "path";

export const initCommand = new Command("init")
  .description("Initialize Tabula configuration")
  .option("-f, --force", "Overwrite existing configuration")
  .action(async (options) => {
    const configPath = path.join(process.cwd(), ".tabula");
    const configFile = path.join(configPath, "config.json");

    // Check if config already exists
    if (fs.existsSync(configFile) && !options.force) {
      console.log(
        chalk.yellow(
          "⚠ Configuration already exists. Use --force to overwrite.",
        ),
      );
      return;
    }

    console.log(chalk.bold("\n🚀 TabCLI Initialization\n"));

    // Prompt for configuration
    const answers = await inquirer.prompt([
      {
        type: "input",
        name: "projectId",
        message: "GCP Project ID:",
        default: "tabula-dev",
        validate: (input) =>
          input.length > 0 ? true : "Project ID is required",
      },
      {
        type: "list",
        name: "environment",
        message: "Default environment:",
        choices: ["development", "staging", "production"],
        default: "development",
      },
      {
        type: "list",
        name: "region",
        message: "Default GCP region:",
        choices: ["us-central1", "us-east1", "europe-west1", "asia-east1"],
        default: "us-central1",
      },
      {
        type: "input",
        name: "databaseUrl",
        message: "Database URL (leave empty to configure later):",
        default: "",
      },
    ]);

    const spinner = ora("Creating configuration...").start();

    try {
      // Create config directory
      if (!fs.existsSync(configPath)) {
        fs.mkdirSync(configPath, { recursive: true });
      }

      // Create config file
      const config = {
        version: "0.1.0",
        projectId: answers.projectId,
        environment: answers.environment,
        region: answers.region,
        databaseUrl: answers.databaseUrl || undefined,
        createdAt: new Date().toISOString(),
      };

      fs.writeFileSync(configFile, JSON.stringify(config, null, 2));

      spinner.succeed("Configuration created successfully");

      console.log(chalk.green("\n✓ TabCLI initialized"));
      console.log(chalk.gray(`Config saved to: ${configFile}`));
      console.log(chalk.cyan("\nNext steps:"));

      if (!process.env.NEON_API_KEY) {
        console.log("  1. Authenticate with Neon: tabcli auth neon");
        console.log("  2. Run: tabcli config list");
      } else {
        console.log("  1. Run: tabcli config list");
      }

      console.log("  3. Set secrets: tabcli secrets set <KEY>");
      console.log("  4. Initialize database: tabcli db init\n");
    } catch (error) {
      spinner.fail("Failed to create configuration");
      console.error(chalk.red(error));
      process.exit(1);
    }
  });
