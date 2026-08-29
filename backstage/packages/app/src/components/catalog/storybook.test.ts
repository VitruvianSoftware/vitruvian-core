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

const makeEntity = (annotations?: Record<string, string>): Entity => ({
  apiVersion: "backstage.io/v1alpha1",
  kind: "Component",
  metadata: { name: "test-component", annotations },
  spec: {},
});

describe("Storybook helpers", () => {
  describe("getStorybookUrl", () => {
    it("returns undefined when entity has no annotations", () => {
      expect(getStorybookUrl(makeEntity())).toBeUndefined();
      expect(getStorybookUrl(makeEntity({}))).toBeUndefined();
    });

    it("returns undefined for empty or whitespace-only annotations", () => {
      expect(
        getStorybookUrl(makeEntity({ [STORYBOOK_URL_ANNOTATION]: "   " })),
      ).toBeUndefined();
      expect(
        getStorybookUrl(makeEntity({ [STORYBOOK_URL_ANNOTATION_LEGACY]: "" })),
      ).toBeUndefined();
    });

    it("returns absolute URL when provided via storybook.io/url", () => {
      const url = "https://storybook.ipv1337.dev/?path=/story/tabula--primary";
      expect(
        getStorybookUrl(makeEntity({ [STORYBOOK_URL_ANNOTATION]: url })),
      ).toBe(url);
    });

    it("returns absolute URL when provided via legacy storybook/url", () => {
      const url = "https://storybook.example.com";
      expect(
        getStorybookUrl(makeEntity({ [STORYBOOK_URL_ANNOTATION_LEGACY]: url })),
      ).toBe(url);
    });

    it("returns absolute URL when provided via storybook.com/url", () => {
      const url = "https://storybook.example.com";
      expect(
        getStorybookUrl(makeEntity({ [STORYBOOK_URL_ANNOTATION_COM]: url })),
      ).toBe(url);
    });

    it("returns absolute URL when provided via vitruvian.dev/storybook-url", () => {
      const url = "https://storybook.ipv1337.dev";
      expect(
        getStorybookUrl(
          makeEntity({ [STORYBOOK_URL_ANNOTATION_VITRUVIAN]: url }),
        ),
      ).toBe(url);
    });

    it("handles boolean flag annotations", () => {
      expect(
        getStorybookUrl(makeEntity({ [STORYBOOK_URL_ANNOTATION]: "true" })),
      ).toBe(DEFAULT_STORYBOOK_URL);
      expect(
        getStorybookUrl(makeEntity({ [STORYBOOK_URL_ANNOTATION]: "enabled" })),
      ).toBe(DEFAULT_STORYBOOK_URL);
    });

    it("resolves relative path starting with slash", () => {
      expect(
        getStorybookUrl(
          makeEntity({
            [STORYBOOK_URL_ANNOTATION]: "/?path=/story/components-button",
          }),
        ),
      ).toBe(`${DEFAULT_STORYBOOK_URL}/?path=/story/components-button`);
    });

    it("resolves query string path starting with question mark", () => {
      expect(
        getStorybookUrl(
          makeEntity({
            [STORYBOOK_URL_ANNOTATION]: "?path=/story/oauth-inspector",
          }),
        ),
      ).toBe(`${DEFAULT_STORYBOOK_URL}/?path=/story/oauth-inspector`);
    });

    it("resolves bare story ID into path query parameter", () => {
      expect(
        getStorybookUrl(
          makeEntity({
            [STORYBOOK_URL_ANNOTATION]: "tabula-panel--overview",
          }),
        ),
      ).toBe(`${DEFAULT_STORYBOOK_URL}/?path=/story/tabula-panel--overview`);
    });
  });

  describe("isStorybookAvailable", () => {
    it("returns true when valid Storybook annotation exists", () => {
      expect(
        isStorybookAvailable(
          makeEntity({
            [STORYBOOK_URL_ANNOTATION]: "https://storybook.ipv1337.dev",
          }),
        ),
      ).toBe(true);
    });

    it("returns false when no Storybook annotation exists", () => {
      expect(isStorybookAvailable(makeEntity())).toBe(false);
      expect(
        isStorybookAvailable(
          makeEntity({
            "github.com/project-slug": "VitruvianSoftware/vitruvian-core",
          }),
        ),
      ).toBe(false);
    });
  });
});
