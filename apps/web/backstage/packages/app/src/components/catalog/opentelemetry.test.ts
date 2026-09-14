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
import {
  OPENTELEMETRY_SERVICE_NAME_ANNOTATION,
  OTEL_SERVICE_NAME_ANNOTATION,
  JAEGER_SERVICE_NAME_ANNOTATION,
  JAEGER_GROUP_ANNOTATION,
  getOpenTelemetryServiceName,
  isOpenTelemetryAvailable,
  getTempoExploreUrl,
} from "./opentelemetry";

const makeEntity = (annotations?: Record<string, string>): Entity => ({
  apiVersion: "backstage.io/v1alpha1",
  kind: "Component",
  metadata: { name: "test-service", annotations },
  spec: {},
});

describe("OpenTelemetry helpers", () => {
  describe("getOpenTelemetryServiceName", () => {
    it("returns undefined for empty annotations", () => {
      expect(getOpenTelemetryServiceName(makeEntity())).toBeUndefined();
      expect(getOpenTelemetryServiceName(makeEntity({}))).toBeUndefined();
    });

    it("returns undefined for whitespace-only annotations", () => {
      expect(
        getOpenTelemetryServiceName(
          makeEntity({ [OPENTELEMETRY_SERVICE_NAME_ANNOTATION]: "   " }),
        ),
      ).toBeUndefined();
    });

    it("resolves opentelemetry.io/service-name", () => {
      expect(
        getOpenTelemetryServiceName(
          makeEntity({
            [OPENTELEMETRY_SERVICE_NAME_ANNOTATION]: "tabula-api",
          }),
        ),
      ).toBe("tabula-api");
    });

    it("resolves otel.io/service-name alias", () => {
      expect(
        getOpenTelemetryServiceName(
          makeEntity({
            [OTEL_SERVICE_NAME_ANNOTATION]: "oauth-inspector",
          }),
        ),
      ).toBe("oauth-inspector");
    });

    it("resolves jaeger.io/service-name alias", () => {
      expect(
        getOpenTelemetryServiceName(
          makeEntity({
            [JAEGER_SERVICE_NAME_ANNOTATION]: "backstage",
          }),
        ),
      ).toBe("backstage");
    });

    it("resolves jaeger.io/group alias", () => {
      expect(
        getOpenTelemetryServiceName(
          makeEntity({
            [JAEGER_GROUP_ANNOTATION]: "mcp-slack",
          }),
        ),
      ).toBe("mcp-slack");
    });
  });

  describe("isOpenTelemetryAvailable", () => {
    it("returns true when service name is present", () => {
      expect(
        isOpenTelemetryAvailable(
          makeEntity({
            [OPENTELEMETRY_SERVICE_NAME_ANNOTATION]: "whoami",
          }),
        ),
      ).toBe(true);
    });

    it("returns false when service name is absent", () => {
      expect(isOpenTelemetryAvailable(makeEntity())).toBe(false);
      expect(
        isOpenTelemetryAvailable(
          makeEntity({ "github.com/project-slug": "VitruvianSoftware/repo" }),
        ),
      ).toBe(false);
    });
  });

  describe("getTempoExploreUrl", () => {
    it("returns undefined if entity has no service name", () => {
      expect(getTempoExploreUrl(makeEntity())).toBeUndefined();
    });

    it("builds valid Grafana Tempo explore URL with defaults", () => {
      const entity = makeEntity({
        [OPENTELEMETRY_SERVICE_NAME_ANNOTATION]: "backstage",
      });
      const url = getTempoExploreUrl(entity);
      expect(url).toBeDefined();
      expect(url).toContain("https://grafana.lab.ipv1337.dev/explore?left=");

      const params = JSON.parse(decodeURIComponent(url!.split("left=")[1]));
      expect(params.datasource).toBe("tempo");
      expect(params.queries[0].serviceName).toBe("backstage");
      expect(params.range.from).toBe("now-1h");
      expect(params.range.to).toBe("now");
    });

    it("accepts custom range and minDuration options", () => {
      const entity = makeEntity({
        [OPENTELEMETRY_SERVICE_NAME_ANNOTATION]: "tabula-api",
      });
      const url = getTempoExploreUrl(entity, {
        range: "6h",
        minDuration: "100ms",
        limit: 50,
      });
      expect(url).toBeDefined();

      const params = JSON.parse(decodeURIComponent(url!.split("left=")[1]));
      expect(params.datasource).toBe("tempo");
      expect(params.queries[0].serviceName).toBe("tabula-api");
      expect(params.queries[0].minDuration).toBe("100ms");
      expect(params.queries[0].limit).toBe(50);
      expect(params.range.from).toBe("now-6h");
    });
  });
});
