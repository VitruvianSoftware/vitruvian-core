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
    const mcpSlack: Entity = {
      apiVersion: "backstage.io/v1alpha1",
      kind: "Component",
      metadata: {
        name: "mcp-slack",
        links: [
          {
            url: "https://www.npmjs.com/package/@vitruviansoftware/mcp-slack",
            title: "npm Package",
          },
        ],
      },
      spec: {},
    };

    expect(isReleaseAvailable(mcpSlack)).toBe(true);
    const target = readReleaseTarget(mcpSlack);
    expect(target).toEqual({
      type: "npm",
      packageName: "@vitruviansoftware/mcp-slack",
      packageUrl: "https://www.npmjs.com/package/@vitruviansoftware/mcp-slack",
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
          "vitruvian.dev/mirror": "VitruvianSoftware/devx",
        },
        links: [
          {
            url: "https://github.com/VitruvianSoftware/devx/releases",
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
      repoSlug: "VitruvianSoftware/devx",
      releasesUrl: "https://github.com/VitruvianSoftware/devx/releases",
    });
  });

  it("detects macOS DMG release model for nexus-agent", () => {
    const nexusAgent: Entity = {
      apiVersion: "backstage.io/v1alpha1",
      kind: "Component",
      metadata: {
        name: "nexus-agent",
        annotations: {
          "vitruvian.dev/release-model": "dmg-github-releases npm-publish",
          "vitruvian.dev/mirror": "VitruvianSoftware/nexus-agent",
        },
        links: [
          {
            url: "https://github.com/VitruvianSoftware/nexus-agent/releases",
            title: "macOS DMG Releases",
          },
        ],
      },
      spec: {},
    };

    expect(isReleaseAvailable(nexusAgent)).toBe(true);
    const target = readReleaseTarget(nexusAgent);
    expect(target).toEqual({
      type: "github",
      repoSlug: "VitruvianSoftware/nexus-agent",
      releasesUrl: "https://github.com/VitruvianSoftware/nexus-agent/releases",
    });
  });
});
