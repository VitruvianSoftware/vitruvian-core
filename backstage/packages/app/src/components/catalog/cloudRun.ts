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

/** Kept in sync with the backend's CLOUD_RUN_ANNOTATION by this test's twin. */
export const CLOUD_RUN_ANNOTATION = "vitruvian.dev/cloud-run-services";

export function readCloudRunRefs(entity: Entity): string | undefined {
  return entity.metadata.annotations?.[CLOUD_RUN_ANNOTATION];
}

/**
 * The card renders only for entities that name Cloud Run services.
 *
 * Same reasoning as every other guard on this page: unguarded it would render
 * an empty box on every entity that runs in the cluster instead (which the
 * Kubernetes and ArgoCD cards already cover) or nowhere at all.
 */
export function isCloudRunAvailable(entity: Entity): boolean {
  return Boolean(readCloudRunRefs(entity)?.trim());
}
