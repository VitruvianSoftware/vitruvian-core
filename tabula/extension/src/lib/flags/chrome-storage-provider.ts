/**
 * Copyright (c) 2026 VitruvianSoftware
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import {
  Provider,
  ResolutionDetails,
  ProviderEvents,
  OpenFeatureEventEmitter,
  JsonValue,
} from "@openfeature/web-sdk";

export class ChromeStorageProvider implements Provider {
  readonly metadata = {
    name: "ChromeStorageProvider",
  };

  events = new OpenFeatureEventEmitter();
  private cache: Record<string, any> = {};
  private readonly storageKey = "tabula_feature_flags";

  async initialize(): Promise<void> {
    if (
      typeof chrome !== "undefined" &&
      chrome.storage &&
      chrome.storage.local
    ) {
      // Read initial state
      const data = await chrome.storage.local.get(this.storageKey);
      this.cache = data[this.storageKey] || {};

      // Subscribe to changes
      chrome.storage.onChanged.addListener((changes, areaName) => {
        if (areaName === "local" && changes[this.storageKey]) {
          this.cache = changes[this.storageKey].newValue || {};
          this.events.emit(ProviderEvents.ConfigurationChanged);
        }
      });
    } else {
      // Fallback for non-extension environment
      this.cache = {};
    }
  }

  resolveBooleanEvaluation(
    flagKey: string,
    defaultValue: boolean,
  ): ResolutionDetails<boolean> {
    if (flagKey in this.cache) {
      return { value: Boolean(this.cache[flagKey]) };
    }
    return { value: defaultValue, reason: "DEFAULT" };
  }

  resolveStringEvaluation(
    flagKey: string,
    defaultValue: string,
  ): ResolutionDetails<string> {
    if (flagKey in this.cache) {
      return { value: String(this.cache[flagKey]) };
    }
    return { value: defaultValue, reason: "DEFAULT" };
  }

  resolveNumberEvaluation(
    flagKey: string,
    defaultValue: number,
  ): ResolutionDetails<number> {
    if (flagKey in this.cache) {
      return { value: Number(this.cache[flagKey]) };
    }
    return { value: defaultValue, reason: "DEFAULT" };
  }

  resolveObjectEvaluation<T extends JsonValue>(
    flagKey: string,
    defaultValue: T,
  ): ResolutionDetails<T> {
    if (flagKey in this.cache) {
      return { value: this.cache[flagKey] as T };
    }
    return { value: defaultValue, reason: "DEFAULT" };
  }
}
