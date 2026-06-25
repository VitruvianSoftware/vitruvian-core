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

import React, { useState, useEffect } from "react";
import { AuthProvider } from "../types";

interface ScopeSelectorProps {
  provider: AuthProvider;
  onScopeChange: (scopes: string) => void;
  initialScopes?: string;
}

// Define common scopes for each provider
const DEFAULT_SCOPES: Record<AuthProvider, string[]> = {
  github: [
    "read:user",
    "user:email",
    "public_repo",
    "repo",
    "admin:repo_hook",
    "gist",
    "notifications",
    "user:follow",
    "delete_repo",
    "write:repo_hook",
    "admin:org",
    "admin:public_key",
    "admin:org_hook",
  ],
  google: [
    "https://www.googleapis.com/auth/userinfo.profile",
    "https://www.googleapis.com/auth/userinfo.email",
    "https://www.googleapis.com/auth/drive",
    "https://www.googleapis.com/auth/calendar",
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/contacts.readonly",
    "https://www.googleapis.com/auth/youtube.readonly",
  ],
  gitlab: [
    "read_user",
    "read_repository",
    "write_repository",
    "api",
    "read_registry",
    "write_registry",
  ],
  auth0: [
    "openid",
    "profile",
    "email",
    "offline_access",
    "read:current_user",
    "update:current_user_metadata",
  ],
  linkedin: [
    "r_liteprofile",
    "r_emailaddress",
    "w_member_social",
    "r_ads",
    "r_ads_reporting",
    "rw_ads",
    "r_organization_social",
  ],
};

// Default scope combinations that work out of the box
const PROVIDER_DEFAULTS: Record<AuthProvider, string> = {
  github: "read:user,user:email",
  google:
    "https://www.googleapis.com/auth/userinfo.profile https://www.googleapis.com/auth/userinfo.email",
  gitlab: "read_user",
  auth0: "openid profile email",
  linkedin: "r_liteprofile r_emailaddress",
};

const ScopeSelector: React.FC<ScopeSelectorProps> = ({
  provider,
  onScopeChange,
  initialScopes,
}) => {
  const [selectedScopes, setSelectedScopes] = useState<string[]>([]);
  const [customInput, setCustomInput] = useState("");
  const [mode, setMode] = useState<"preset" | "custom">("preset");

  // Initialize with default or provided scopes - only when provider changes or initially
  useEffect(() => {
    const scopes = initialScopes || PROVIDER_DEFAULTS[provider];
    const scopeArray =
      provider === "google"
        ? scopes.split(" ")
        : scopes.split(/[, ]+/).filter(Boolean);

    setSelectedScopes(scopeArray);
    setCustomInput(scopes);

    // Determine if current scopes match any preset combination
    const isPreset = scopes === PROVIDER_DEFAULTS[provider];
    setMode(isPreset ? "preset" : "custom");

    // Only call onScopeChange during initialization to avoid infinite loops
    onScopeChange(scopes);
  }, [provider]); // Remove initialScopes dependency to prevent loops

  // Update parent when scopes change (but not during initialization)
  useEffect(() => {
    const scopeString =
      mode === "custom"
        ? customInput
        : provider === "google"
          ? selectedScopes.join(" ")
          : selectedScopes.join(",");

    // Only update if we have scopes to avoid calling with empty string on mount
    if (selectedScopes.length > 0 || customInput.trim()) {
      onScopeChange(scopeString);
    }
  }, [selectedScopes, customInput, mode, provider, onScopeChange]);

  const handleScopeToggle = (scope: string) => {
    setSelectedScopes((prev) =>
      prev.includes(scope) ? prev.filter((s) => s !== scope) : [...prev, scope],
    );
  };

  const handleModeChange = (newMode: "preset" | "custom") => {
    setMode(newMode);

    if (newMode === "preset") {
      // Reset to current selected scopes
      const scopeString =
        provider === "google"
          ? selectedScopes.join(" ")
          : selectedScopes.join(",");
      setCustomInput(scopeString);
    } else {
      // Switch to custom mode with current scope string
      const currentString =
        provider === "google"
          ? selectedScopes.join(" ")
          : selectedScopes.join(",");
      setCustomInput(currentString);
    }
  };

  const handleCustomInputChange = (value: string) => {
    setCustomInput(value);

    // Update selectedScopes to reflect custom input for consistency
    const scopeArray =
      provider === "google"
        ? value.split(" ").filter(Boolean)
        : value.split(/[, ]+/).filter(Boolean);
    setSelectedScopes(scopeArray);
  };

  const resetToDefault = () => {
    const defaultScopes = PROVIDER_DEFAULTS[provider];
    const scopeArray =
      provider === "google"
        ? defaultScopes.split(" ")
        : defaultScopes.split(/[, ]+/).filter(Boolean);

    setSelectedScopes(scopeArray);
    setCustomInput(defaultScopes);
    setMode("preset");
  };

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <label className="block text-sm font-medium text-slate-300">
          OAuth Scopes
        </label>
        <div className="flex gap-2">
          <button
            type="button"
            onClick={() => handleModeChange("preset")}
            className={`px-2 py-1 text-xs rounded border transition-colors ${
              mode === "preset"
                ? "border-blue-400 bg-blue-500/20 text-blue-300"
                : "border-slate-600 text-slate-400 hover:text-slate-200 hover:bg-slate-700"
            }`}
          >
            Select
          </button>
          <button
            type="button"
            onClick={() => handleModeChange("custom")}
            className={`px-2 py-1 text-xs rounded border transition-colors ${
              mode === "custom"
                ? "border-blue-400 bg-blue-500/20 text-blue-300"
                : "border-slate-600 text-slate-400 hover:text-slate-200 hover:bg-slate-700"
            }`}
          >
            Custom
          </button>
        </div>
      </div>

      {mode === "preset" ? (
        <div className="bg-slate-900/50 border border-slate-700 rounded-md p-3 max-h-48 overflow-y-auto">
          <div className="grid grid-cols-1 gap-2">
            {DEFAULT_SCOPES[provider].map((scope) => (
              <label
                key={scope}
                className="flex items-center space-x-2 text-sm cursor-pointer hover:bg-slate-700/30 rounded px-2 py-1"
              >
                <input
                  type="checkbox"
                  checked={selectedScopes.includes(scope)}
                  onChange={() => handleScopeToggle(scope)}
                  className="rounded border-slate-600 bg-slate-700 text-blue-500 focus:ring-blue-500 focus:ring-offset-slate-800"
                />
                <span
                  className={`font-mono text-xs ${
                    selectedScopes.includes(scope)
                      ? "text-slate-200"
                      : "text-slate-400"
                  }`}
                >
                  {scope}
                </span>
              </label>
            ))}
          </div>
          <div className="mt-3 pt-2 border-t border-slate-700">
            <button
              type="button"
              onClick={resetToDefault}
              className="text-xs px-2 py-1 rounded border border-slate-600 text-slate-400 hover:text-slate-200 hover:bg-slate-700"
            >
              Reset to Default
            </button>
          </div>
        </div>
      ) : (
        <div>
          <textarea
            value={customInput}
            onChange={(e) => handleCustomInputChange(e.target.value)}
            placeholder={`Enter scopes separated by ${provider === "google" ? "spaces" : "commas or spaces"}`}
            className="w-full px-3 py-2 bg-slate-900 border border-slate-700 rounded-md text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-500 transition-colors font-mono text-sm"
            rows={3}
          />
          <p className="mt-1 text-xs text-slate-400">
            {provider === "google"
              ? "Separate Google scopes with spaces"
              : "Separate scopes with commas or spaces"}
          </p>
        </div>
      )}

      <div className="text-xs text-slate-500">
        Selected: {selectedScopes.length} scope
        {selectedScopes.length !== 1 ? "s" : ""}
      </div>
    </div>
  );
};

export default ScopeSelector;
