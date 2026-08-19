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

/**
 * A Cloud Run service, as named by an entity annotation.
 *
 * The annotation is explicit rather than derived. Deriving
 * `<app>-<env>` from the entity name and an environments list would be
 * shorter, but it is wrong the moment a service does not follow that shape --
 * tabula has TWO services per environment (api and web), and the projects are
 * random-suffixed (`prj-d-bu2-oss-floating-c3d1`), so nothing about the
 * location is guessable from the entity.
 */
export type CloudRunRef = {
  /** Label shown in the card, e.g. "production" or "production/api". */
  label: string;
  project: string;
  region: string;
  service: string;
};

export const CLOUD_RUN_ANNOTATION = "vitruvian.dev/cloud-run-services";

/**
 * Parses the annotation into refs.
 *
 * Format, one per line (commas also accepted so a single-line annotation
 * works):
 *
 *   development=prj-d-bu2-oss-floating-c3d1/us-central1/tabula-api-development
 *
 * Malformed entries are SKIPPED rather than thrown on: one typo in a six-line
 * annotation should cost that row, not the whole card. `invalid` reports them
 * so the caller can surface the problem instead of silently showing less than
 * the user expects.
 */
export function parseCloudRunRefs(raw: string | undefined): {
  refs: CloudRunRef[];
  invalid: string[];
} {
  const refs: CloudRunRef[] = [];
  const invalid: string[] = [];
  if (!raw) return { refs, invalid };

  for (const entry of raw.split(/[\n,]/)) {
    const line = entry.trim();
    if (!line) continue;

    const eq = line.indexOf("=");
    if (eq <= 0) {
      invalid.push(line);
      continue;
    }
    const label = line.slice(0, eq).trim();
    const parts = line
      .slice(eq + 1)
      .trim()
      .split("/");
    if (parts.length !== 3 || parts.some((p) => !p.trim())) {
      invalid.push(line);
      continue;
    }
    const [project, region, service] = parts.map((p) => p.trim());
    // A path separator smuggled through any component would let a crafted
    // annotation address a different API path entirely once interpolated into
    // the request URL below.
    if ([project, region, service].some((p) => /[^A-Za-z0-9-]/.test(p))) {
      invalid.push(line);
      continue;
    }
    refs.push({ label, project, region, service });
  }
  return { refs, invalid };
}

/** Cloud Run Admin API v2 endpoint for a single service. */
export function serviceUrl(ref: CloudRunRef): string {
  return (
    `https://run.googleapis.com/v2/projects/${ref.project}` +
    `/locations/${ref.region}/services/${ref.service}`
  );
}

type ApiService = {
  uri?: string;
  latestReadyRevision?: string;
  trafficStatuses?: { revision?: string; percent?: number; type?: string }[];
  terminalCondition?: { type?: string; state?: string; message?: string };
};

export type CloudRunStatus = {
  label: string;
  service: string;
  url?: string;
  /** Short revision name, not the full resource path. */
  revision?: string;
  traffic: { revision: string; percent: number }[];
  ready: boolean;
  message?: string;
};

/**
 * Maps the API response into what the card renders.
 *
 * `latestReadyRevision` is a full resource path; only its last segment is
 * meaningful to a human, and the full path makes the column unreadable.
 */
export function mapService(ref: CloudRunRef, s: ApiService): CloudRunStatus {
  const short = (p?: string) => (p ? p.split("/").pop() : undefined);
  return {
    label: ref.label,
    service: ref.service,
    url: s.uri,
    revision: short(s.latestReadyRevision),
    traffic: (s.trafficStatuses ?? [])
      .filter((t) => (t.percent ?? 0) > 0)
      .map((t) => ({
        revision: short(t.revision) ?? "latest",
        percent: t.percent ?? 0,
      })),
    // Absent terminalCondition is treated as NOT ready: a card that claims
    // healthy because a field was missing is worse than one that says unknown.
    ready: s.terminalCondition?.state === "CONDITION_SUCCEEDED",
    message: s.terminalCondition?.message,
  };
}
