import { OpenFeature } from "@openfeature/web-sdk";
import { ChromeStorageProvider } from "./chrome-storage-provider";

export const FLAGS = {
  USE_DESIGN_SYSTEM: "use-design-system",
} as const;

let initialized = false;

export async function initFeatureFlags() {
  if (initialized) return OpenFeature.getClient();
  await OpenFeature.setProviderAndWait(new ChromeStorageProvider());
  initialized = true;
  return OpenFeature.getClient();
}

export function getFeatureFlagClient() {
  return OpenFeature.getClient();
}
