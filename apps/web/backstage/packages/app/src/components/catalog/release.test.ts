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
import { isReleaseAvailable, readReleaseTarget } from "./release";

describe("release target reader", () => {
  it("returns undefined for entities without release links or models", () => {
    const raw: Entity = {
      apiVersion: "backstage.io/v1alpha1",
      kind: "Component",
      metadata: { name: "internal-service" },
      spec: {},
    };

    expect(isReleaseAvailable(raw)).toBe(false);
    expect(readReleaseTarget(raw)).toBeUndefined();
  });

  it("detects npm package target from direct npm link", () => {
    const vitruvianSlackMcp: Entity = {
      apiVersion: "backstage.io/v1alpha1",
      kind: "Component",
      metadata: {
        name: "vitruvian-slack-mcp",
        links: [
          {
            url: "https://www.npmjs.com/package/@vitruviansoftware/vitruvian-slack-mcp",
            title: "npm Package",
          },
        ],
      },
      spec: {},
    };

    expect(isReleaseAvailable(vitruvianSlackMcp)).toBe(true);
    const target = readReleaseTarget(vitruvianSlackMcp);
    expect(target).toEqual({
      type: "npm",
      packageName: "@vitruviansoftware/vitruvian-slack-mcp",
      packageUrl:
        "https://www.npmjs.com/package/@vitruviansoftware/vitruvian-slack-mcp",
    });
  });

  it("detects GitHub Releases target from mirror + goreleaser annotation", () => {
    const devx: Entity = {
      apiVersion: "backstage.io/v1alpha1",
      kind: "Component",
      metadata: {
        name: "devx",
        annotations: {
          "vitruvian.dev/release-model": "goreleaser",
          "vitruvian.dev/mirror": "VitruvianSoftware/vitruvian-devx",
        },
        links: [
          {
            url: "https://github.com/VitruvianSoftware/vitruvian-devx/releases",
            title: "Releases",
          },
        ],
      },
      spec: {},
    };

    expect(isReleaseAvailable(devx)).toBe(true);
    const target = readReleaseTarget(devx);
    expect(target).toEqual({
      type: "github",
      repoSlug: "VitruvianSoftware/vitruvian-devx",
      releasesUrl:
        "https://github.com/VitruvianSoftware/vitruvian-devx/releases",
    });
  });

  it("detects macOS DMG release model for vitruvian-code", () => {
    const vitruvianCode: Entity = {
      apiVersion: "backstage.io/v1alpha1",
      kind: "Component",
      metadata: {
        name: "vitruvian-code",
        annotations: {
          "vitruvian.dev/release-model": "dmg-github-releases npm-publish",
          "vitruvian.dev/mirror": "VitruvianSoftware/vitruvian-code",
        },
        links: [
          {
            url: "https://github.com/VitruvianSoftware/vitruvian-code/releases",
            title: "macOS DMG Releases",
          },
        ],
      },
      spec: {},
    };

    expect(isReleaseAvailable(vitruvianCode)).toBe(true);
    const target = readReleaseTarget(vitruvianCode);
    expect(target).toEqual({
      type: "github",
      repoSlug: "VitruvianSoftware/vitruvian-code",
      releasesUrl:
        "https://github.com/VitruvianSoftware/vitruvian-code/releases",
    });
  });
});
