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
  mapService,
  parseCloudRunRefs,
  serviceUrl,
  type CloudRunRef,
} from "./refs";

describe("parseCloudRunRefs", () => {
  it("parses the real tabula annotation, two services per environment", () => {
    const { refs, invalid } = parseCloudRunRefs(
      [
        "development/api=prj-d-bu2-oss-floating-c3d1/us-central1/tabula-api-development",
        "development/web=prj-d-bu2-oss-floating-c3d1/us-central1/tabula-web-development",
        "production/api=prj-p-bu2-oss-floating-8663/us-central1/tabula-api-production",
      ].join("\n"),
    );
    expect(invalid).toEqual([]);
    expect(refs).toHaveLength(3);
    expect(refs[0]).toEqual({
      label: "development/api",
      project: "prj-d-bu2-oss-floating-c3d1",
      region: "us-central1",
      service: "tabula-api-development",
    });
  });

  it("accepts a single-line comma-separated annotation", () => {
    const { refs } = parseCloudRunRefs("a=p/r/s,b=p2/r2/s2");
    expect(refs.map((r) => r.label)).toEqual(["a", "b"]);
  });

  it("skips a malformed entry instead of losing the whole card", () => {
    const { refs, invalid } = parseCloudRunRefs(
      "good=p/r/s\nnonsense\nalso-bad=p/r\n",
    );
    expect(refs.map((r) => r.label)).toEqual(["good"]);
    expect(invalid).toEqual(["nonsense", "also-bad=p/r"]);
  });

  // The guard that matters: a crafted annotation must not be able to steer the
  // request at a different API path once interpolated into the URL.
  it("rejects components containing path separators or traversal", () => {
    const { refs, invalid } = parseCloudRunRefs(
      "evil=p/r/..%2f..%2fsomething\nevil2=p/r/s?x=1\nevil3=p/r/a b",
    );
    expect(refs).toEqual([]);
    expect(invalid).toHaveLength(3);
  });

  it("is empty for a missing annotation", () => {
    expect(parseCloudRunRefs(undefined).refs).toEqual([]);
    expect(parseCloudRunRefs("").refs).toEqual([]);
  });
});

describe("serviceUrl", () => {
  it("targets the Cloud Run Admin v2 service endpoint", () => {
    const ref: CloudRunRef = {
      label: "production",
      project: "prj-p-bu1-oss-floating-16e0",
      region: "us-central1",
      service: "oauth-user-inspector-production",
    };
    expect(serviceUrl(ref)).toBe(
      "https://run.googleapis.com/v2/projects/prj-p-bu1-oss-floating-16e0" +
        "/locations/us-central1/services/oauth-user-inspector-production",
    );
  });
});

describe("mapService", () => {
  const ref: CloudRunRef = {
    label: "production",
    project: "p",
    region: "r",
    service: "tabula-api-production",
  };

  it("shortens revision paths and drops zero-percent traffic", () => {
    const got = mapService(ref, {
      uri: "https://x.run.app",
      latestReadyRevision:
        "projects/p/locations/r/services/tabula-api-production/revisions/tabula-api-production-f26ed976-817449",
      trafficStatuses: [
        {
          revision: "projects/p/locations/r/services/s/revisions/rev-a",
          percent: 100,
        },
        {
          revision: "projects/p/locations/r/services/s/revisions/rev-b",
          percent: 0,
        },
      ],
      terminalCondition: { state: "CONDITION_SUCCEEDED" },
    });
    expect(got.revision).toBe("tabula-api-production-f26ed976-817449");
    expect(got.traffic).toEqual([{ revision: "rev-a", percent: 100 }]);
    expect(got.ready).toBe(true);
  });

  // A missing condition must not read as healthy -- "unknown" is honest,
  // "ready" is a lie the card would render in green.
  it("treats an absent or failed terminalCondition as NOT ready", () => {
    expect(mapService(ref, {}).ready).toBe(false);
    expect(
      mapService(ref, {
        terminalCondition: { state: "CONDITION_FAILED", message: "boom" },
      }),
    ).toMatchObject({ ready: false, message: "boom" });
  });

  it("tolerates a service with no traffic statuses at all", () => {
    expect(mapService(ref, { uri: "https://x" }).traffic).toEqual([]);
  });
});
