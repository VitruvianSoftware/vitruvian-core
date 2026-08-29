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

export const STORYBOOK_URL_ANNOTATION = "storybook.io/url";
export const STORYBOOK_URL_ANNOTATION_LEGACY = "storybook/url";
export const STORYBOOK_URL_ANNOTATION_COM = "storybook.com/url";
export const STORYBOOK_URL_ANNOTATION_VITRUVIAN = "vitruvian.dev/storybook-url";

export const DEFAULT_STORYBOOK_URL = "https://storybook.ipv1337.dev";

/**
 * Resolves the Storybook URL for a catalog entity.
 * Supports absolute URLs, relative story paths, and boolean flags.
 */
export function getStorybookUrl(entity: Entity): string | undefined {
  const raw =
    entity?.metadata?.annotations?.[STORYBOOK_URL_ANNOTATION] ??
    entity?.metadata?.annotations?.[STORYBOOK_URL_ANNOTATION_LEGACY] ??
    entity?.metadata?.annotations?.[STORYBOOK_URL_ANNOTATION_COM] ??
    entity?.metadata?.annotations?.[STORYBOOK_URL_ANNOTATION_VITRUVIAN];

  if (!raw || typeof raw !== "string") {
    return undefined;
  }

  const trimmed = raw.trim();
  if (!trimmed) {
    return undefined;
  }

  if (trimmed === "true" || trimmed === "enabled") {
    return DEFAULT_STORYBOOK_URL;
  }

  if (/^https?:\/\//i.test(trimmed)) {
    return trimmed;
  }

  if (trimmed.startsWith("/")) {
    return `${DEFAULT_STORYBOOK_URL}${trimmed}`;
  }

  if (trimmed.startsWith("?")) {
    return `${DEFAULT_STORYBOOK_URL}/${trimmed}`;
  }

  return `${DEFAULT_STORYBOOK_URL}/?path=/story/${trimmed}`;
}

/**
 * Predicate checking whether Storybook previews are available for the entity.
 */
export function isStorybookAvailable(entity: Entity): boolean {
  return Boolean(getStorybookUrl(entity));
}
