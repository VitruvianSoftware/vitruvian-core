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

const getCredentials = jest.fn();
jest.mock("@backstage/integration", () => ({
  ScmIntegrations: { fromConfig: jest.fn(() => ({})) },
  DefaultGithubCredentialsProvider: {
    fromIntegrations: jest.fn(() => ({ getCredentials })),
  },
}));

import type { RootConfigService } from "@backstage/backend-plugin-api";
import { githubTokenSource, tokenFor } from "./githubToken";

const withGithubIntegration = {
  has: (key: string) => key === "integrations.github",
} as unknown as RootConfigService;

describe("scorecard GitHub token source", () => {
  const savedEnv = { ...process.env };
  beforeEach(() => {
    getCredentials.mockReset();
    delete process.env.GITHUB_TOKEN;
    delete process.env.GH_TOKEN;
  });
  afterAll(() => {
    process.env = savedEnv;
  });

  it("passes a fixed token through and asks a function per repository", async () => {
    expect(await tokenFor("fixed", "o/r")).toBe("fixed");
    const fn = jest.fn(async (url: string) => `t-for-${url}`);
    expect(await tokenFor(fn, "VitruvianSoftware/x")).toBe(
      "t-for-https://github.com/VitruvianSoftware/x",
    );
    expect(await tokenFor(undefined, "o/r")).toBeUndefined();
  });

  it("prefers an explicit token over everything", async () => {
    process.env.GITHUB_TOKEN = "env";
    const src = githubTokenSource({
      githubToken: "explicit",
      config: withGithubIntegration,
    });
    expect(await tokenFor(src, "o/r")).toBe("explicit");
    expect(getCredentials).not.toHaveBeenCalled();
  });

  it("falls back to GITHUB_TOKEN when there is no integration config", async () => {
    process.env.GITHUB_TOKEN = "env";
    expect(await tokenFor(githubTokenSource({}), "o/r")).toBe("env");
  });

  it("asks the integration (the GitHub App) for each repository's token", async () => {
    getCredentials.mockResolvedValue({ type: "app", token: "ghs_app" });
    const src = githubTokenSource({ config: withGithubIntegration });
    expect(await tokenFor(src, "VitruvianSoftware/vitruvian-core")).toBe(
      "ghs_app",
    );
    expect(getCredentials).toHaveBeenCalledWith({
      url: "https://github.com/VitruvianSoftware/vitruvian-core",
    });
  });

  it("degrades to the env token, not an error, when minting fails", async () => {
    process.env.GITHUB_TOKEN = "env";
    getCredentials.mockRejectedValue(new Error("no installation"));
    const src = githubTokenSource({ config: withGithubIntegration });
    expect(await tokenFor(src, "o/r")).toBe("env");
  });
});
