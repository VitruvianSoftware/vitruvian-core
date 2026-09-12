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

import {
  type MembershipFetcher,
  assertActiveOrgMember,
} from "./githubOrgSignIn";

const ORG = "VitruvianSoftware";

const fetcherReturning =
  (status: number, body?: { state?: string }): MembershipFetcher =>
  async () => ({ status, body });

const call = (fetcher: MembershipFetcher, accessToken = "gho_token") =>
  assertActiveOrgMember({ org: ORG, accessToken, fetcher });

describe("assertActiveOrgMember", () => {
  it("allows an active member through", async () => {
    await expect(
      call(fetcherReturning(200, { state: "active" })),
    ).resolves.toBeUndefined();
  });

  it("denies a non-member (GitHub answers 404)", async () => {
    await expect(call(fetcherReturning(404))).rejects.toThrow(
      /not a member of the VitruvianSoftware GitHub organisation/,
    );
  });

  it("denies an invited-but-not-accepted member (state: pending)", async () => {
    await expect(
      call(fetcherReturning(200, { state: "pending" })),
    ).rejects.toThrow(/is 'pending', not 'active'/);
  });

  it("denies when the membership payload has no state at all", async () => {
    await expect(call(fetcherReturning(200, {}))).rejects.toThrow(
      /is 'unknown', not 'active'/,
    );
  });

  it.each([401, 403, 500, 502])(
    "fails closed on an unexpected %s from GitHub",
    async (status) => {
      await expect(call(fetcherReturning(status))).rejects.toThrow(
        /Could not verify VitruvianSoftware membership: GitHub returned/,
      );
    },
  );

  it("fails closed when the request throws (GitHub unreachable)", async () => {
    const boom: MembershipFetcher = async () => {
      throw new Error("ECONNREFUSED");
    };
    await expect(call(boom)).rejects.toThrow(
      /Could not verify .* ECONNREFUSED/,
    );
  });

  it("denies when there is no access token to check with", async () => {
    await expect(
      call(fetcherReturning(200, { state: "active" }), ""),
    ).rejects.toThrow(/No GitHub access token/);
  });

  it("asks GitHub about the configured org, url-encoded", async () => {
    const seen: string[] = [];
    const spy: MembershipFetcher = async (org, token) => {
      seen.push(`${org}|${token}`);
      return { status: 200, body: { state: "active" } };
    };
    await assertActiveOrgMember({
      org: "Some Org",
      accessToken: "tok",
      fetcher: spy,
    });
    expect(seen).toEqual(["Some Org|tok"]);
  });
});
