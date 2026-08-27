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
import { isSdlcAvailable, readSdlcInfo } from "./sdlc";

const entity = (annotations?: Record<string, string>): Entity => ({
  apiVersion: "backstage.io/v1alpha1",
  kind: "Component",
  metadata: { name: "test-service", annotations },
  spec: {},
});

describe("sdlc metadata parser", () => {
  it("returns undefined and isSdlcAvailable=false for entities without SDLC annotations", () => {
    expect(isSdlcAvailable(entity())).toBe(false);
    expect(isSdlcAvailable(entity({}))).toBe(false);
    expect(
      isSdlcAvailable(entity({ "backstage.io/techdocs-ref": "dir:." })),
    ).toBe(false);
    expect(readSdlcInfo(entity())).toBeUndefined();
  });

  it("parses Tabula continuous delivery SDLC metadata", () => {
    const ent = entity({
      "vitruvian.dev/release-model": "continuous-deploy",
      "vitruvian.dev/environments": "development nonproduction production",
      "vitruvian.dev/deploy-workflow": "delivery.yaml",
      "vitruvian.dev/deploy-targets":
        "//tabula/api:image_push //tabula/extension:chrome_zip",
    });

    expect(isSdlcAvailable(ent)).toBe(true);
    const info = readSdlcInfo(ent);
    expect(info).toBeDefined();
    expect(info?.releaseModels).toHaveLength(1);
    expect(info?.releaseModels[0].key).toBe("continuous-deploy");
    expect(info?.releaseModels[0].category).toBe("cloud-run");
    expect(info?.environments).toEqual([
      "development",
      "nonproduction",
      "production",
    ]);
    expect(info?.workflow).toEqual({ name: "delivery.yaml", type: "deploy" });
    expect(info?.deployTargets).toEqual([
      "//tabula/api:image_push",
      "//tabula/extension:chrome_zip",
    ]);
  });

  it("parses multi-strategy release models (e.g. nexus-agent: dmg + npm)", () => {
    const ent = entity({
      "vitruvian.dev/release-model": "dmg-github-releases npm-publish",
      "vitruvian.dev/release-workflow": "apps-release.yml",
      "vitruvian.dev/mirror": "VitruvianSoftware/nexus-agent",
    });

    const info = readSdlcInfo(ent);
    expect(info).toBeDefined();
    expect(info?.releaseModels).toHaveLength(2);
    expect(info?.releaseModels.map((m) => m.key)).toEqual([
      "dmg-github-releases",
      "npm-publish",
    ]);
    expect(info?.workflow).toEqual({
      name: "apps-release.yml",
      type: "release",
    });
    expect(info?.mirror).toBe("VitruvianSoftware/nexus-agent");
  });

  it("gracefully falls back for custom/unrecognized release strategies", () => {
    const ent = entity({
      "vitruvian.dev/release-model": "custom-lambda-deploy",
    });

    const info = readSdlcInfo(ent);
    expect(info?.releaseModels[0]).toEqual({
      key: "custom-lambda-deploy",
      label: "custom-lambda-deploy",
      description: "Custom delivery or packaging strategy.",
      category: "custom",
    });
  });
});
