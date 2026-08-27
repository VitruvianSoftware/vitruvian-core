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

import type { Entity } from "@backstage/catalog-model";

export type NpmReleaseTarget = {
  type: "npm";
  packageName: string;
  packageUrl: string;
};

export type GitHubReleaseTarget = {
  type: "github";
  repoSlug: string;
  releasesUrl: string;
};

export type ReleaseTarget = NpmReleaseTarget | GitHubReleaseTarget;

export function readReleaseTarget(entity: Entity): ReleaseTarget | undefined {
  const links = (entity.metadata.links ?? []) as Array<{
    url: string;
    title?: string;
  }>;
  const annotations = entity.metadata.annotations ?? {};
  const releaseModel = annotations["vitruvian.dev/release-model"] ?? "";
  const mirror = annotations["vitruvian.dev/mirror"];

  // 1. Explicit links take precedence
  const npmLink = links.find((l) => l.url.includes("npmjs.com/package/"));
  if (npmLink) {
    const match = npmLink.url.match(
      /npmjs\.com\/package\/(@?[^/?#]+(?:\/[^/?#]+)?)/,
    );
    if (match) {
      return {
        type: "npm",
        packageName: match[1],
        packageUrl: npmLink.url,
      };
    }
  }

  const releaseLink = links.find(
    (l) => l.url.includes("/releases") && l.url.includes("github.com/"),
  );
  if (releaseLink) {
    const match = releaseLink.url.match(
      /github\.com\/([^/]+\/[^/]+)(?:\/releases)?/,
    );
    if (match) {
      return {
        type: "github",
        repoSlug: match[1],
        releasesUrl: `https://github.com/${match[1]}/releases`,
      };
    }
  }

  // 2. Annotation fallback if no explicit link
  if (
    mirror &&
    (releaseModel.includes("goreleaser") ||
      releaseModel.includes("dmg-github-releases"))
  ) {
    return {
      type: "github",
      repoSlug: mirror,
      releasesUrl: `https://github.com/${mirror}/releases`,
    };
  }

  if (releaseModel.includes("npm-publish")) {
    const defaultPkgName = `@vitruviansoftware/${entity.metadata.name}`;
    return {
      type: "npm",
      packageName: defaultPkgName,
      packageUrl: `https://www.npmjs.com/package/${defaultPkgName}`,
    };
  }

  return undefined;
}

export function isReleaseAvailable(entity: Entity): boolean {
  return readReleaseTarget(entity) !== undefined;
}

export type ReleaseInfo = {
  version: string;
  publishedAt?: string;
  releaseTitle?: string;
  url: string;
  type: "npm" | "github";
  details?: string;
};
