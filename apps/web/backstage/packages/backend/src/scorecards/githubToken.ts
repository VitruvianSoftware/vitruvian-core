// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import type { RootConfigService } from "@backstage/backend-plugin-api";
import {
  DefaultGithubCredentialsProvider,
  ScmIntegrations,
} from "@backstage/integration";

/**
 * Where scorecards get a GitHub token for a repository.
 *
 * A function, not a string: with `integrations.github[].apps` configured the
 * token is a GitHub App installation token that expires after an hour, so it
 * has to be asked for each time (the provider caches and renews it). A string
 * is still accepted for tests and standalone runs.
 */
export type GithubTokenSource =
  string | ((repoUrl: string) => Promise<string | undefined>);

export async function tokenFor(
  source: GithubTokenSource | undefined,
  slug: string,
): Promise<string | undefined> {
  if (typeof source === "function") {
    return source(`https://github.com/${slug}`);
  }
  return source;
}

/**
 * Build the token source scorecards use. An explicit token wins (tests); then
 * Backstage's own GitHub integration config, which serves the GitHub App's
 * installation token (or a configured `token`); then GITHUB_TOKEN / GH_TOKEN
 * for local runs with no integration config. Failures to mint a token degrade
 * to "no token" -- the CI fact then reads unknown -- rather than failing the
 * whole scorecard.
 */
export function githubTokenSource(options: {
  githubToken?: string;
  config?: RootConfigService;
}): GithubTokenSource | undefined {
  if (options.githubToken) {
    return options.githubToken;
  }
  const envToken = process.env.GITHUB_TOKEN ?? process.env.GH_TOKEN;
  let provider: DefaultGithubCredentialsProvider | undefined;
  try {
    if (options.config?.has("integrations.github")) {
      provider = DefaultGithubCredentialsProvider.fromIntegrations(
        ScmIntegrations.fromConfig(options.config),
      );
    }
  } catch {
    // Minimal config schemas in smoke tests: fall through to the env token.
  }
  if (!provider) {
    return envToken;
  }
  const p = provider;
  return async (repoUrl: string) => {
    try {
      const { token } = await p.getCredentials({ url: repoUrl });
      return token ?? envToken;
    } catch {
      return envToken;
    }
  };
}
