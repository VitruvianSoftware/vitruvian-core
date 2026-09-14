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
import ora from "ora";
import { execSync } from "child_process";
import path from "path";
import { getConfig } from "../utils/config";

function getEnv(isLocal = false) {
  const env = { ...process.env };
  if (!isLocal) {
    try {
      const config = getConfig();
      if (config.databaseUrl) {
        env.DATABASE_URL = config.databaseUrl as string;
      }
    } catch (e) {
      // If config fails (e.g. not initialized), just return process.env
    }
  }
  return env;
}

export const dbCommand = new Command("db").description(
  "Database management commands",
);

// Initialize database (run migrations)
dbCommand
  .command("init")
  .description("Initialize database with schema")
  .option("-l, --local", "Use local database configuration")
  .action(async (options) => {
    const spinner = ora("Initializing database...").start();

    try {
      const apiPath = path.join(process.cwd(), "api");

      // Generate Prisma client
      spinner.text = "Generating Prisma client...";
      execSync("npx prisma generate", {
        cwd: apiPath,
        stdio: "pipe",
        env: getEnv(options.local),
      });

      // Run migrations
      spinner.text = "Running migrations...";
      execSync("npx prisma migrate deploy", {
        cwd: apiPath,
        stdio: "pipe",
        env: getEnv(options.local),
      });

      spinner.succeed("Database initialized successfully");
      console.log(chalk.green("\n✓ Database is ready"));
    } catch (error) {
      spinner.fail("Database initialization failed");
      if (error instanceof Error) {
        console.error(chalk.red(error.message));
      }
      process.exit(1);
    }
  });

// Run database migrations
dbCommand
  .command("migrate")
  .description("Run database migrations")
  .option("--name <name>", "Migration name", "migration")
  .option("-l, --local", "Use local database configuration")
  .action(async (options) => {
    const spinner = ora("Running migrations...").start();

    try {
      const apiPath = path.join(process.cwd(), "api");

      execSync(`npx prisma migrate dev --name ${options.name}`, {
        cwd: apiPath,
        stdio: "inherit",
        env: getEnv(options.local),
      });

      spinner.succeed("Migrations completed");
    } catch (error) {
      spinner.fail("Migration failed");
      if (error instanceof Error) {
        console.error(chalk.red(error.message));
      }
      process.exit(1);
    }
  });

// Reset database
dbCommand
  .command("reset")
  .description("Reset database (WARNING: deletes all data)")
  .option("-f, --force", "Skip confirmation")
  .option("-l, --local", "Use local database configuration")
  .action(async (options) => {
    if (!options.force) {
      console.log(chalk.yellow("⚠ This will delete all data in the database!"));
      console.log(chalk.gray("Use --force to skip this confirmation"));
      return;
    }

    const spinner = ora("Resetting database...").start();

    try {
      const apiPath = path.join(process.cwd(), "api");

      execSync("npx prisma migrate reset --force", {
        cwd: apiPath,
        stdio: "pipe",
        env: getEnv(options.local),
      });

      spinner.succeed("Database reset successfully");
    } catch (error) {
      spinner.fail("Database reset failed");
      if (error instanceof Error) {
        console.error(chalk.red(error.message));
      }
      process.exit(1);
    }
  });

// Open Prisma Studio
dbCommand
  .command("studio")
  .description("Open Prisma Studio (database GUI)")
  .option("-l, --local", "Use local database configuration")
  .action((options) => {
    console.log(chalk.cyan("Opening Prisma Studio..."));
    const apiPath = path.join(process.cwd(), "api");

    execSync("npx prisma studio", {
      cwd: apiPath,
      stdio: "inherit",
      env: getEnv(options.local),
    });
  });

// List database records
dbCommand
  .command("list")
  .description("List database records for a model")
  .argument("<model>", "Model name (e.g. user, workspace)")
  .option("-l, --local", "Use local database configuration")
  .action(async (model, options) => {
    const spinner = ora(`Fetching ${model} records...`).start();

    try {
      const apiPath = path.join(process.cwd(), "api");

      // Execute script in API context to use correct Prisma Client
      const result = execSync(`npx tsx scripts/db-list.ts ${model}`, {
        cwd: apiPath,
        encoding: "utf-8",
        stdio: ["ignore", "pipe", "ignore"], // Capture stdout, ignore stderr/in
        env: getEnv(options.local),
      });

      const data = JSON.parse(result);
      spinner.stop();

      if (data.length === 0) {
        console.log(chalk.yellow(`No records found for model "${model}".`));
      } else {
        console.log(chalk.bold(`\n${model} Records (${data.length}):\n`));
        // Flatten objects for table display if needed, or simple table
        console.table(data);
      }
    } catch (error) {
      spinner.fail("Failed to list records");
      if (error instanceof Error) {
        // Try to parse script error from stdout if it JSON failed,
        // but typically script prints to stderr or console.error which we might have missed?
        // Changed stdio to pipe for stdout only.
        console.error(
          chalk.red(
            "Make sure the model name exists and database is connected.",
          ),
        );
      }
      process.exit(1);
    }
  });

// Database status
dbCommand
  .command("status")
  .description("Check database connection and migration status")
  .option("-l, --local", "Use local database configuration")
  .action(async (options) => {
    const spinner = ora("Checking database status...").start();

    try {
      const apiPath = path.join(process.cwd(), "api");

      const output = execSync("npx prisma migrate status", {
        cwd: apiPath,
        encoding: "utf-8",
        env: getEnv(options.local),
      });

      spinner.succeed("Database status checked");
      console.log(`\n${output}`);
    } catch (error) {
      spinner.fail("Failed to check database status");
      if (error instanceof Error) {
        console.error(chalk.red(error.message));
      }
      process.exit(1);
    }
  });
