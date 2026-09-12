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

/** Default GitHub organisation whose members may sign in. */
export const DEFAULT_ALLOWED_ORG = "VitruvianSoftware";

/** Shape of the GitHub membership payload we care about. */
type Membership = { state?: string };

/**
 * Minimal seam so tests can drive the resolver without network access, and so
 * the check is expressed against an interface rather than global fetch.
 */
export type MembershipFetcher = (
  org: string,
  accessToken: string,
) => Promise<{ status: number; body: Membership | undefined }>;

export const githubMembershipFetcher: MembershipFetcher = async (
  org,
  accessToken,
) => {
  const res = await fetch(
    `https://api.github.com/user/memberships/orgs/${encodeURIComponent(org)}`,
    {
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
      },
    },
  );

  let body: Membership | undefined;
  try {
    body = (await res.json()) as Membership;
  } catch {
    body = undefined;
  }
  return { status: res.status, body };
};

export class OrgMembershipError extends Error {}

/**
 * Verifies that the signing-in user is an *active* member of `org`, using that
 * user's own OAuth access token.
 *
 * This deliberately needs no service credential: GitHub answers
 * `/user/memberships/orgs/{org}` for the authenticated user, so membership is
 * proven by the person signing in rather than by a PAT or GitHub App the portal
 * would otherwise have to store and rotate. Requires the `read:org` scope, which
 * the provider factory requests via `additionalScopes`.
 *
 * Throws on anything other than proven active membership — 404 (not a member or
 * the token lacks read:org), `state: 'pending'` (invited but not accepted), and
 * transport/API failures all deny rather than fall open.
 */
export async function assertActiveOrgMember(options: {
  org: string;
  accessToken: string;
  fetcher?: MembershipFetcher;
}): Promise<void> {
  const { org, accessToken, fetcher = githubMembershipFetcher } = options;

  if (!accessToken) {
    throw new OrgMembershipError(
      "No GitHub access token on the sign-in result; cannot verify organisation membership",
    );
  }

  let result: { status: number; body: Membership | undefined };
  try {
    result = await fetcher(org, accessToken);
  } catch (e) {
    // Fail closed: an unreachable GitHub must not become an open door.
    throw new OrgMembershipError(
      `Could not verify ${org} membership: ${(e as Error).message}`,
    );
  }

  if (result.status === 404) {
    throw new OrgMembershipError(
      `Sign-in denied: not a member of the ${org} GitHub organisation ` +
        `(or the token is missing the read:org scope)`,
    );
  }
  if (result.status !== 200) {
    throw new OrgMembershipError(
      `Could not verify ${org} membership: GitHub returned ${result.status}`,
    );
  }
  if (result.body?.state !== "active") {
    throw new OrgMembershipError(
      `Sign-in denied: ${org} membership is '${result.body?.state ?? "unknown"}', not 'active'`,
    );
  }
}
