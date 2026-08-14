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
