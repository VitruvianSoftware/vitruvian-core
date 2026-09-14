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

import { execSync } from "child_process";
import chalk from "chalk";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function getProjectId(config: any, env: string = "dev"): string {
  if (
    config.environments &&
    config.environments[env] &&
    config.environments[env].projectId
  ) {
    return config.environments[env].projectId;
  }
  return config.projectId;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function loadWorkOSApiKey(config: any, env: string) {
  if (process.env.WORKOS_API_KEY) return;

  const projectId = getProjectId(config, env);

  try {
    const key = execSync(
      `gcloud secrets versions access latest --secret=WORKOS_API_KEY --project=${projectId}`,
      { encoding: "utf-8", stdio: ["ignore", "pipe", "ignore"] },
    ).trim();
    if (key) {
      process.env.WORKOS_API_KEY = key;
      return;
    }
  } catch (e) {
    // Ignore
  }

  console.warn(
    chalk.yellow(
      "\n⚠️  WORKOS_API_KEY not found in environment or Secret Manager.",
    ),
  );
  console.warn(chalk.yellow("WorkOS operations will likely fail."));
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function loadWorkOSClientId(config: any, env: string) {
  if (process.env.WORKOS_CLIENT_ID) return;

  const projectId = getProjectId(config, env);

  try {
    const clientId = execSync(
      `gcloud secrets versions access latest --secret=WORKOS_CLIENT_ID --project=${projectId}`,
      { encoding: "utf-8", stdio: ["ignore", "pipe", "ignore"] },
    ).trim();
    if (clientId) {
      process.env.WORKOS_CLIENT_ID = clientId;
      return;
    }
  } catch (e) {
    // Ignore
  }

  console.warn(
    chalk.yellow(
      "\n⚠️  WORKOS_CLIENT_ID not found in environment or Secret Manager.",
    ),
  );
  console.warn(chalk.yellow("WorkOS integration might fail."));
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function loadNeonApiKey(config: any, env: string) {
  if (process.env.NEON_API_KEY) return;

  const projectId = getProjectId(config, env);

  // 1. Try GSM
  try {
    const apiKey = execSync(
      `gcloud secrets versions access latest --secret=NEON_API_KEY --project=${projectId}`,
      { encoding: "utf-8", stdio: ["ignore", "pipe", "ignore"] },
    ).trim();
    if (apiKey) {
      process.env.NEON_API_KEY = apiKey;
      return;
    }
  } catch (e) {
    // Ignore GSM error
  }

  // 2. Config
  if (config.neonApiKey) {
    process.env.NEON_API_KEY = config.neonApiKey;
    return;
  }

  console.warn(
    chalk.yellow(
      "\n⚠️  NEON_API_KEY not found in environment, config, or Secret Manager.",
    ),
  );
  console.warn(
    chalk.yellow("Terraform operations involving Neon will likely fail."),
  );
  console.warn(
    chalk.yellow('Run "tabcli auth neon" or export NEON_API_KEY manually.\n'),
  );
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function loadUpstashCredentials(config: any, env: string) {
  if (process.env.UPSTASH_EMAIL && process.env.UPSTASH_API_KEY) return;

  const projectId = getProjectId(config, env);

  // Try fetching UPSTASH_EMAIL
  if (!process.env.UPSTASH_EMAIL) {
    try {
      const email = execSync(
        `gcloud secrets versions access latest --secret=UPSTASH_EMAIL --project=${projectId}`,
        { encoding: "utf-8", stdio: ["ignore", "pipe", "ignore"] },
      ).trim();
      if (email) {
        process.env.UPSTASH_EMAIL = email;
      }
    } catch (e) {
      // Ignore
    }
  }

  // Try fetching UPSTASH_API_KEY
  if (!process.env.UPSTASH_API_KEY) {
    try {
      const apiKey = execSync(
        `gcloud secrets versions access latest --secret=UPSTASH_API_KEY --project=${projectId}`,
        { encoding: "utf-8", stdio: ["ignore", "pipe", "ignore"] },
      ).trim();
      if (apiKey) {
        process.env.UPSTASH_API_KEY = apiKey;
      }
    } catch (e) {
      // Ignore
    }
  }

  if (!process.env.UPSTASH_EMAIL || !process.env.UPSTASH_API_KEY) {
    console.warn(
      chalk.yellow(
        "\n⚠️  Upstash credentials not found in environment or Secret Manager.",
      ),
    );
    console.warn(
      chalk.yellow("Terraform operations involving Upstash will likely fail."),
    );
    console.warn(
      chalk.yellow(
        'Use "tabcli infra secrets set UPSTASH_EMAIL/UPSTASH_API_KEY" to set them.\n',
      ),
    );
  }
}
