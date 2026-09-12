#!/usr/bin/env node
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
import { configCommand } from "./commands/config";
import { dbCommand } from "./commands/db";
import { initCommand } from "./commands/init";
import { versionCommand } from "./commands/version";
import { authCommand } from "./commands/auth";
import { workosCommand } from "./commands/workos";
import { extCommand } from "./commands/ext";

const program = new Command();

// CLI metadata
program
  .name("tabcli")
  .description(
    "TabCLI - Command-line tool for managing Tabula infrastructure and operations",
  )
  .version("0.1.0")
  .addHelpText(
    "after",
    `
${chalk.bold("Examples:")}
  $ tabcli init                    # Initialize Tabula configuration
  $ tabcli auth neon               # Authenticate with Neon
  $ tabcli auth gcloud             # Authenticate with GCP
  $ tabcli config set project my-project
  $ tabcli db migrate              # Run database migrations
  $ tabcli ext update              # Pull the latest dev extension build

${chalk.bold("Documentation:")}
  For more information, visit: https://github.com/VitruvianSoftware/vitruvian-core
`,
  );

// Register commands
program.addCommand(initCommand);
program.addCommand(configCommand);
program.addCommand(dbCommand);
program.addCommand(versionCommand);
program.addCommand(authCommand);
program.addCommand(workosCommand);
program.addCommand(extCommand);

// Parse arguments
program.parse(process.argv);

// Show help if no command provided
if (!process.argv.slice(2).length) {
  program.outputHelp();
}
