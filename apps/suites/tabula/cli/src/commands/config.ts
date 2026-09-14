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
import { table } from "table";
import { getConfig, saveConfig } from "../utils/config";

export const configCommand = new Command("config").description(
  "Manage TabCLI configuration",
);

// List all configuration
configCommand
  .command("list")
  .alias("ls")
  .description("List all configuration values")
  .action(() => {
    const config = getConfig();

    const data = [
      [chalk.bold("Key"), chalk.bold("Value")],
      ["Project ID", config.projectId],
      ["Environment", config.environment],
      ["Region", config.region],
      ["Database URL", config.databaseUrl ? "(set)" : "(not set)"],
      ["Created At", config.createdAt],
    ];

    console.log(`\n${table(data)}`);
  });

// Set a configuration value
configCommand
  .command("set")
  .description("Set a configuration value")
  .argument(
    "<key>",
    "Configuration key (projectId, environment, region, databaseUrl)",
  )
  .argument("<value>", "Configuration value")
  .action((key, value) => {
    const config = getConfig();
    const validKeys = ["projectId", "environment", "region", "databaseUrl"];

    if (!validKeys.includes(key)) {
      console.error(
        chalk.red(`Invalid key. Valid keys: ${validKeys.join(", ")}`),
      );
      process.exit(1);
    }

    config[key] = value;
    saveConfig(config);

    console.log(chalk.green(`✓ Set ${key} = ${value}`));
  });

// Get a configuration value
configCommand
  .command("get")
  .description("Get a configuration value")
  .argument("<key>", "Configuration key")
  .action((key) => {
    const config = getConfig();

    if (!(key in config)) {
      console.error(chalk.red(`Key not found: ${key}`));
      process.exit(1);
    }

    console.log(config[key]);
  });

// Unset a configuration value
configCommand
  .command("unset")
  .description("Unset a configuration value")
  .argument("<key>", "Configuration key")
  .action((key) => {
    const config = getConfig();

    if (!(key in config)) {
      console.error(chalk.red(`Key not found: ${key}`));
      process.exit(1);
    }

    delete config[key];
    saveConfig(config);

    console.log(chalk.green(`✓ Unset ${key}`));
  });
