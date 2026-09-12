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
import { isCloudRunAvailable, readCloudRunRefs } from "./cloudRun";

const entity = (annotations?: Record<string, string>): Entity => ({
  apiVersion: "backstage.io/v1alpha1",
  kind: "Component",
  metadata: { name: "x", annotations },
  spec: {},
});

describe("isCloudRunAvailable", () => {
  it("is true when the annotation names services", () => {
    expect(
      isCloudRunAvailable(
        entity({
          "vitruvian.dev/cloud-run-services":
            "production=prj-p-bu1-oss-floating-16e0/us-central1/oauth-user-inspector-production",
        }),
      ),
    ).toBe(true);
  });

  it("is false when absent, empty, or whitespace-only", () => {
    expect(isCloudRunAvailable(entity())).toBe(false);
    expect(isCloudRunAvailable(entity({}))).toBe(false);
    expect(
      isCloudRunAvailable(
        entity({ "vitruvian.dev/cloud-run-services": "   \n " }),
      ),
    ).toBe(false);
  });

  it("does not fire on the in-cluster annotations, which other cards own", () => {
    expect(
      isCloudRunAvailable(entity({ "argocd/app-name": "backstage" })),
    ).toBe(false);
  });

  it("reads the raw annotation for the backend to parse", () => {
    const raw = "a=p/r/s";
    expect(
      readCloudRunRefs(entity({ "vitruvian.dev/cloud-run-services": raw })),
    ).toBe(raw);
  });
});
