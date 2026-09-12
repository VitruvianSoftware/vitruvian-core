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
import path from "path";

export interface Config {
  projectId: string;
  region: string;
  neonOrgId?: string;
  environments?: Record<string, { projectId: string }>;
  [key: string]: unknown;
}

/**
 * Get TabCLI configuration
 */
export function getConfig(): Config {
  const configFile = path.join(process.cwd(), ".tabula", "config.json");

  if (!fs.existsSync(configFile)) {
    throw new Error("Configuration not found. Run: tabcli init");
  }

  try {
    const content = fs.readFileSync(configFile, "utf-8");
    return JSON.parse(content) as Config;
  } catch (error) {
    throw new Error(
      `Failed to parse configuration file: ${(error as Error).message}`,
    );
  }
}

/**
 * Save TabCLI configuration
 */
export function saveConfig(config: Config) {
  const configFile = path.join(process.cwd(), ".tabula", "config.json");

  try {
    fs.writeFileSync(configFile, JSON.stringify(config, null, 2));
  } catch (error) {
    throw new Error(
      `Failed to save configuration: ${(error as Error).message}`,
    );
  }
}

/**
 * Escape shell argument to prevent command injection
 */
export function escapeShellArg(arg: string): string {
  // Replace single quotes with '\'' and wrap in single quotes
  return `'${arg.replace(/'/g, "'\\''")}'`;
}
