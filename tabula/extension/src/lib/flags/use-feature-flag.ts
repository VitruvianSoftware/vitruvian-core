import { useState, useEffect } from "react";
import { getFeatureFlagClient } from "./index";
import { ProviderEvents } from "@openfeature/web-sdk";

export function useFeatureFlag(
  flagKey: string,
  defaultValue: boolean,
): boolean {
  const client = getFeatureFlagClient();
  const [value, setValue] = useState(() =>
    client.getBooleanValue(flagKey, defaultValue),
  );

  useEffect(() => {
    // Initial sync
    setValue(client.getBooleanValue(flagKey, defaultValue));

    const handler = () => {
      setValue(client.getBooleanValue(flagKey, defaultValue));
    };

    client.addHandler(ProviderEvents.ConfigurationChanged, handler);
    return () => {
      client.removeHandler(ProviderEvents.ConfigurationChanged, handler);
    };
  }, [client, flagKey, defaultValue]);

  return value;
}

export async function setFeatureFlag(flagKey: string, value: boolean) {
  if (typeof chrome !== "undefined" && chrome.storage && chrome.storage.local) {
    const storageKey = "tabula_feature_flags";
    const data = await chrome.storage.local.get(storageKey);
    const flags: Record<string, any> = data[storageKey] || {};
    flags[flagKey] = value;
    await chrome.storage.local.set({ [storageKey]: flags });
  }
}
