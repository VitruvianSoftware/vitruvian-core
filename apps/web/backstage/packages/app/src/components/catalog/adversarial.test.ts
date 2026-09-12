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
  DEFAULT_STORYBOOK_URL,
  STORYBOOK_URL_ANNOTATION,
  STORYBOOK_URL_ANNOTATION_LEGACY,
  STORYBOOK_URL_ANNOTATION_COM,
  STORYBOOK_URL_ANNOTATION_VITRUVIAN,
  getStorybookUrl,
  isStorybookAvailable,
} from "./storybook";
import {
  DEFAULT_GRAFANA_TEMPO_URL,
  OPENTELEMETRY_SERVICE_NAME_ANNOTATION,
  OTEL_SERVICE_NAME_ANNOTATION,
  JAEGER_SERVICE_NAME_ANNOTATION,
  JAEGER_GROUP_ANNOTATION,
  getOpenTelemetryServiceName,
  isOpenTelemetryAvailable,
  getTempoExploreUrl,
} from "./opentelemetry";

describe("Adversarial & Boundary Stress Tests", () => {
  // Helper to build partial or malformed entity objects safely
  const createEntity = (
    annotations?: any,
    overrides?: Partial<Entity>,
  ): Entity =>
    ({
      apiVersion: "backstage.io/v1alpha1",
      kind: "Component",
      metadata: {
        name: "stress-test-service",
        annotations,
        ...overrides?.metadata,
      },
      spec: {},
      ...overrides,
    }) as unknown as Entity;

  describe("Storybook Helper: Malformed URLs & Protocol Injection", () => {
    it("handles dangerous URI schemes (javascript:, data:, vbscript:) safely without executing protocol", () => {
      // javascript: scheme should NOT be recognized as https?:// and will be treated as story ID/path on default host
      const jsUrl = "javascript:alert(document.domain)";
      const entity = createEntity({ [STORYBOOK_URL_ANNOTATION]: jsUrl });
      const resolved = getStorybookUrl(entity);

      expect(resolved).toBeDefined();
      // Verifies that it prepends default storybook host rather than emitting bare javascript: URL
      expect(resolved).toBe(
        `${DEFAULT_STORYBOOK_URL}/?path=/story/javascript:alert(document.domain)`,
      );
      expect(resolved?.startsWith("https://storybook.ipv1337.dev")).toBe(true);
    });

    it("handles data: URI schemes safely without raw base64 execution", () => {
      const dataUri =
        "data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==";
      const entity = createEntity({ [STORYBOOK_URL_ANNOTATION]: dataUri });
      const resolved = getStorybookUrl(entity);

      expect(resolved).toBe(`${DEFAULT_STORYBOOK_URL}/?path=/story/${dataUri}`);
    });

    it("handles ftp: and file: URI schemes safely", () => {
      const ftpUri = "ftp://ftp.attack.com/payload";
      const fileUri = "file:///etc/shadow";

      expect(
        getStorybookUrl(createEntity({ [STORYBOOK_URL_ANNOTATION]: ftpUri })),
      ).toBe(`${DEFAULT_STORYBOOK_URL}/?path=/story/${ftpUri}`);

      expect(
        getStorybookUrl(createEntity({ [STORYBOOK_URL_ANNOTATION]: fileUri })),
      ).toBe(`${DEFAULT_STORYBOOK_URL}/?path=/story/${fileUri}`);
    });

    it("handles protocol-relative URLs (//evil.com/embed)", () => {
      const protoRelative = "//evil.com/embed";
      const entity = createEntity({
        [STORYBOOK_URL_ANNOTATION]: protoRelative,
      });
      const resolved = getStorybookUrl(entity);
      // Because it starts with "/", it appends to default host
      expect(resolved).toBe(`${DEFAULT_STORYBOOK_URL}//evil.com/embed`);
      expect(resolved?.startsWith("https://storybook.ipv1337.dev")).toBe(true);
    });

    it("handles path traversal and directory escape sequences", () => {
      const traversal = "../../../etc/passwd";
      const entity = createEntity({ [STORYBOOK_URL_ANNOTATION]: traversal });
      const resolved = getStorybookUrl(entity);
      expect(resolved).toBe(
        `${DEFAULT_STORYBOOK_URL}/?path=/story/../../../etc/passwd`,
      );
    });

    it("handles control characters, newlines, and null bytes safely", () => {
      const payload = "button-story\r\n\t\x00-variant";
      const entity = createEntity({ [STORYBOOK_URL_ANNOTATION]: payload });
      const resolved = getStorybookUrl(entity);
      expect(resolved).toBeDefined();
      expect(resolved).toBe(
        `${DEFAULT_STORYBOOK_URL}/?path=/story/button-story\r\n\t\x00-variant`,
      );
    });

    it("handles ReDoS / catastrophic regex backtracking attempts on protocol matcher", () => {
      const evilString = "http://" + "a".repeat(20000) + "@example.com";
      const startTime = performance.now();
      const resolved = getStorybookUrl(
        createEntity({ [STORYBOOK_URL_ANNOTATION]: evilString }),
      );
      const duration = performance.now() - startTime;

      expect(resolved).toBe(evilString);
      // Ensure regex execution is linear and finishes in under 50ms
      expect(duration).toBeLessThan(50);
    });

    it("strictly respects annotation precedence order", () => {
      const entity = createEntity({
        [STORYBOOK_URL_ANNOTATION]: "https://primary.storybook.dev",
        [STORYBOOK_URL_ANNOTATION_LEGACY]: "https://legacy.storybook.dev",
        [STORYBOOK_URL_ANNOTATION_COM]: "https://com.storybook.dev",
        [STORYBOOK_URL_ANNOTATION_VITRUVIAN]: "https://vitruvian.storybook.dev",
      });
      expect(getStorybookUrl(entity)).toBe("https://primary.storybook.dev");

      delete (entity.metadata.annotations as any)[STORYBOOK_URL_ANNOTATION];
      expect(getStorybookUrl(entity)).toBe("https://legacy.storybook.dev");

      delete (entity.metadata.annotations as any)[
        STORYBOOK_URL_ANNOTATION_LEGACY
      ];
      expect(getStorybookUrl(entity)).toBe("https://com.storybook.dev");

      delete (entity.metadata.annotations as any)[STORYBOOK_URL_ANNOTATION_COM];
      expect(getStorybookUrl(entity)).toBe("https://vitruvian.storybook.dev");
    });
  });

  describe("Storybook Helper: Malformed Entity Shapes & Type Coercion", () => {
    it("handles null, undefined, and non-object entities gracefully", () => {
      expect(getStorybookUrl(null as any)).toBeUndefined();
      expect(getStorybookUrl(undefined as any)).toBeUndefined();
      expect(getStorybookUrl({} as any)).toBeUndefined();
      expect(getStorybookUrl({ metadata: null } as any)).toBeUndefined();
      expect(
        getStorybookUrl({ metadata: { annotations: null } } as any),
      ).toBeUndefined();
      expect(isStorybookAvailable(null as any)).toBe(false);
      expect(isStorybookAvailable(undefined as any)).toBe(false);
    });

    it("handles non-string annotation types (numbers, booleans, objects, arrays) without crashing", () => {
      expect(
        getStorybookUrl(
          createEntity({ [STORYBOOK_URL_ANNOTATION]: 12345 as any }),
        ),
      ).toBeUndefined();
      expect(
        getStorybookUrl(
          createEntity({ [STORYBOOK_URL_ANNOTATION]: true as any }),
        ),
      ).toBeUndefined();
      expect(
        getStorybookUrl(
          createEntity({ [STORYBOOK_URL_ANNOTATION]: { url: "foo" } as any }),
        ),
      ).toBeUndefined();
      expect(
        getStorybookUrl(
          createEntity({ [STORYBOOK_URL_ANNOTATION]: ["https://foo"] as any }),
        ),
      ).toBeUndefined();
    });

    it("handles boolean string variations", () => {
      expect(
        getStorybookUrl(createEntity({ [STORYBOOK_URL_ANNOTATION]: "true" })),
      ).toBe(DEFAULT_STORYBOOK_URL);
      expect(
        getStorybookUrl(
          createEntity({ [STORYBOOK_URL_ANNOTATION]: "enabled" }),
        ),
      ).toBe(DEFAULT_STORYBOOK_URL);
      // "false" is not a boolean flag, so it is treated as story id "false"
      expect(
        getStorybookUrl(createEntity({ [STORYBOOK_URL_ANNOTATION]: "false" })),
      ).toBe(`${DEFAULT_STORYBOOK_URL}/?path=/story/false`);
    });
  });

  describe("OpenTelemetry Helper: Adversarial Service Names & Injection", () => {
    it("safely serializes and URL-encodes special characters, quotes, and HTML in serviceName", () => {
      const adversarialServiceName = `<script>alert('XSS')</script>" AND 1=1 -- \\`;
      const entity = createEntity({
        [OPENTELEMETRY_SERVICE_NAME_ANNOTATION]: adversarialServiceName,
      });

      expect(getOpenTelemetryServiceName(entity)).toBe(adversarialServiceName);
      expect(isOpenTelemetryAvailable(entity)).toBe(true);

      const tempoUrl = getTempoExploreUrl(entity);
      expect(tempoUrl).toBeDefined();
      expect(tempoUrl?.startsWith(DEFAULT_GRAFANA_TEMPO_URL)).toBe(true);

      // Verify that the URL parameter is valid JSON when decoded
      const leftQueryParam = decodeURIComponent(tempoUrl!.split("left=")[1]);
      const parsed = JSON.parse(leftQueryParam);

      expect(parsed.datasource).toBe("tempo");
      expect(parsed.queries[0].serviceName).toBe(adversarialServiceName);
      expect(parsed.queries[0].refId).toBe("A");
      expect(parsed.queries[0].queryType).toBe("search");
    });

    it("handles unicode, emojis, and right-to-left service names", () => {
      const unicodeService = "🚀-payment-service-💳-\u0000-\u202Ereversed";
      const entity = createEntity({
        [OPENTELEMETRY_SERVICE_NAME_ANNOTATION]: unicodeService,
      });

      const tempoUrl = getTempoExploreUrl(entity);
      expect(tempoUrl).toBeDefined();

      const leftQueryParam = decodeURIComponent(tempoUrl!.split("left=")[1]);
      const parsed = JSON.parse(leftQueryParam);
      expect(parsed.queries[0].serviceName).toBe(unicodeService);
    });

    it("strictly respects OpenTelemetry annotation precedence order", () => {
      const entity = createEntity({
        [OPENTELEMETRY_SERVICE_NAME_ANNOTATION]: "primary-otel",
        [OTEL_SERVICE_NAME_ANNOTATION]: "otel-alias",
        [JAEGER_SERVICE_NAME_ANNOTATION]: "jaeger-service",
        [JAEGER_GROUP_ANNOTATION]: "jaeger-group",
      });
      expect(getOpenTelemetryServiceName(entity)).toBe("primary-otel");

      delete (entity.metadata.annotations as any)[
        OPENTELEMETRY_SERVICE_NAME_ANNOTATION
      ];
      expect(getOpenTelemetryServiceName(entity)).toBe("otel-alias");

      delete (entity.metadata.annotations as any)[OTEL_SERVICE_NAME_ANNOTATION];
      expect(getOpenTelemetryServiceName(entity)).toBe("jaeger-service");

      delete (entity.metadata.annotations as any)[
        JAEGER_SERVICE_NAME_ANNOTATION
      ];
      expect(getOpenTelemetryServiceName(entity)).toBe("jaeger-group");
    });
  });

  describe("OpenTelemetry Helper: Boundary Values for Time Filters and Options", () => {
    it("handles extreme, empty, zero, and negative option values safely", () => {
      const entity = createEntity({
        [OPENTELEMETRY_SERVICE_NAME_ANNOTATION]: "billing-worker",
      });

      // Test extreme limit and custom range
      const extremeUrl = getTempoExploreUrl(entity, {
        limit: 10000,
        range: "720h",
        minDuration: "5m",
      });
      expect(extremeUrl).toBeDefined();
      const parsedExtreme = JSON.parse(
        decodeURIComponent(extremeUrl!.split("left=")[1]),
      );
      expect(parsedExtreme.queries[0].limit).toBe(10000);
      expect(parsedExtreme.queries[0].minDuration).toBe("5m");
      expect(parsedExtreme.range.from).toBe("now-720h");

      // Test limit = 0
      const zeroLimitUrl = getTempoExploreUrl(entity, { limit: 0 });
      const parsedZero = JSON.parse(
        decodeURIComponent(zeroLimitUrl!.split("left=")[1]),
      );
      expect(parsedZero.queries[0].limit).toBe(0);

      // Test negative limit
      const negativeLimitUrl = getTempoExploreUrl(entity, { limit: -5 });
      const parsedNegative = JSON.parse(
        decodeURIComponent(negativeLimitUrl!.split("left=")[1]),
      );
      expect(parsedNegative.queries[0].limit).toBe(-5);

      // Test empty string minDuration (omitted or kept)
      const emptyMinDurationUrl = getTempoExploreUrl(entity, {
        minDuration: undefined,
      });
      const parsedEmptyMinDuration = JSON.parse(
        decodeURIComponent(emptyMinDurationUrl!.split("left=")[1]),
      );
      expect(parsedEmptyMinDuration.queries[0].minDuration).toBeUndefined();
    });

    it("handles malformed entity shapes and returns undefined for getTempoExploreUrl", () => {
      expect(getTempoExploreUrl(null as any)).toBeUndefined();
      expect(getTempoExploreUrl(undefined as any)).toBeUndefined();
      expect(getTempoExploreUrl({} as any)).toBeUndefined();
      expect(
        getTempoExploreUrl(createEntity({ "some.other/annotation": "val" })),
      ).toBeUndefined();
    });
  });
});
