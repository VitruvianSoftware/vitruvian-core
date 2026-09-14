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

export const OPENTELEMETRY_SERVICE_NAME_ANNOTATION =
  "opentelemetry.io/service-name";
export const OTEL_SERVICE_NAME_ANNOTATION = "otel.io/service-name";
export const JAEGER_SERVICE_NAME_ANNOTATION = "jaeger.io/service-name";
export const JAEGER_GROUP_ANNOTATION = "jaeger.io/group";

export const DEFAULT_GRAFANA_TEMPO_URL = "https://grafana.lab.ipv1337.dev";

/**
 * Extracts the OpenTelemetry / Tempo service name configured on the entity.
 */
export function getOpenTelemetryServiceName(
  entity: Entity,
): string | undefined {
  const raw =
    entity?.metadata?.annotations?.[OPENTELEMETRY_SERVICE_NAME_ANNOTATION] ??
    entity?.metadata?.annotations?.[OTEL_SERVICE_NAME_ANNOTATION] ??
    entity?.metadata?.annotations?.[JAEGER_SERVICE_NAME_ANNOTATION] ??
    entity?.metadata?.annotations?.[JAEGER_GROUP_ANNOTATION];

  if (!raw || typeof raw !== "string") {
    return undefined;
  }

  const trimmed = raw.trim();
  return trimmed || undefined;
}

/**
 * Predicate checking whether OpenTelemetry tracing is available for the entity.
 */
export function isOpenTelemetryAvailable(entity: Entity): boolean {
  return Boolean(getOpenTelemetryServiceName(entity));
}

/**
 * Generates a deep link to Grafana Tempo Explore pre-filtered by service name.
 */
export function getTempoExploreUrl(
  entity: Entity,
  options?: { range?: string; minDuration?: string; limit?: number },
): string | undefined {
  const serviceName = getOpenTelemetryServiceName(entity);
  if (!serviceName) {
    return undefined;
  }

  const rangeWindow = options?.range ?? "1h";
  const limit = options?.limit ?? 20;

  const leftParam = {
    datasource: "tempo",
    queries: [
      {
        refId: "A",
        queryType: "search",
        serviceName,
        limit,
        minDuration: options?.minDuration,
      },
    ],
    range: {
      from: `now-${rangeWindow}`,
      to: "now",
    },
  };

  return `${DEFAULT_GRAFANA_TEMPO_URL}/explore?left=${encodeURIComponent(
    JSON.stringify(leftParam),
  )}`;
}
