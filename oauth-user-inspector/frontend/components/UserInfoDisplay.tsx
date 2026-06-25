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

import React, { useEffect, useMemo, useRef, useState } from "react";
import type { AppUser } from "../types";
import {
  GithubIcon,
  GoogleIcon,
  ClipboardIcon,
  ClipboardCheckIcon,
} from "./icons";
import { getFieldDoc, getAllFieldDocs } from "../fieldDocs";
import JsonTree from "./JsonTree";
import TokenDisplay from "./TokenDisplay";
import ApiExplorer from "./ApiExplorer";
import CodeSnippetGenerator from "./CodeSnippetGenerator";
import { getProviderEndpoints } from "../utils/apiEndpoints";

interface UserInfoDisplayProps {
  user: AppUser;
  safeMode?: boolean;
  importedSnapshot?: any | null;
  onTokenRefresh?: () => void;
  onTokenRevocation?: () => void;
}

const isUrl = (val: string) => /^https?:\/\//i.test(val);
const renderPrimitive = (value: any): string => {
  if (value === null || value === undefined) return "—";
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "number") return value.toString();
  if (typeof value === "string") return value;
  return "";
};

const ProviderIcon: React.FC<{
  provider: AppUser["provider"];
  className?: string;
}> = ({ provider, className }) => {
  switch (provider) {
    case "github":
      return <GithubIcon className={className} />;
    case "google":
      return <GoogleIcon className={className} />;
    default:
      return null;
  }
};

const UserInfoDisplay: React.FC<UserInfoDisplayProps> = ({
  user,
  safeMode = false,
  importedSnapshot,
  onTokenRefresh,
  onTokenRevocation,
}) => {
  const [isCopied, setIsCopied] = useState(false);
  const [viewMode, setViewMode] = useState<
    "both" | "table" | "json" | "api" | "snippets"
  >(() => {
    const stored = localStorage.getItem("view_mode");
    return stored === "table" ||
      stored === "json" ||
      stored === "both" ||
      stored === "api" ||
      stored === "snippets"
      ? stored
      : "both";
  });
  const exportSnapshot = () => {
    try {
      const snapshot = {
        capturedAt: new Date().toISOString(),
        provider: user.provider,
        username: user.username,
        viewMode,
        rawData: user.rawData,
        // Intentionally exclude accessToken by default for safety; include masked
        accessTokenMasked: user.accessToken
          ? user.accessToken.replace(/.(?=.{4})/g, "•")
          : undefined,
      };
      const blob = new Blob([JSON.stringify(snapshot, null, 2)], {
        type: "application/json",
      });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `oauth-user-snapshot-${user.provider}-${user.username}-${Date.now()}.json`;
      a.click();
      URL.revokeObjectURL(url);
    } catch (e) {
      console.error("Failed to export snapshot", e);
    }
  };
  const updateViewMode = (
    mode: "both" | "table" | "json" | "api" | "snippets",
  ) => {
    setViewMode(mode);
    localStorage.setItem("view_mode", mode);
  };

  const handleCopy = () => {
    navigator.clipboard.writeText(JSON.stringify(user.rawData, null, 2)).then(
      () => {
        setIsCopied(true);
        setTimeout(() => setIsCopied(false), 2000);
      },
      (err) => {
        console.error("Could not copy text: ", err);
      },
    );
  };

  // Build a stable ordered list of top-level primitive fields for table view
  const [search, setSearch] = useState("");
  const searchInputRef = useRef<HTMLInputElement | null>(null);
  const [diffEnabled, setDiffEnabled] = useState<boolean>(
    () => localStorage.getItem("diff_enabled") === "true",
  );
  const [showAllFields, setShowAllFields] = useState<boolean>(
    () => localStorage.getItem("show_all_fields") === "true",
  );
  const snapshotRaw = importedSnapshot?.rawData;
  type DiffStatus = "unchanged" | "added" | "removed" | "changed";
  interface TableEntry {
    key: string;
    value: any;
    previousValue?: any;
    status: DiffStatus;
  }

  const tableEntries = useMemo(() => {
    const raw: Record<string, any> = user.rawData as any;

    // Get all potential fields for this provider when showAllFields is enabled
    let fieldsToShow: string[];

    if (showAllFields) {
      // Get all documented fields for this provider
      const allFieldDocs = getAllFieldDocs(user.provider);
      const allDocumentedFields = Object.keys(allFieldDocs);

      // Get primitive fields from current data
      const primitiveKeys = Object.keys(raw).filter((k) => {
        const v = raw[k];
        return v === null || ["string", "number", "boolean"].includes(typeof v);
      });

      // Combine both sets, preferring documented fields
      const combinedFields = new Set([
        ...allDocumentedFields,
        ...primitiveKeys,
      ]);
      fieldsToShow = Array.from(combinedFields);
    } else {
      // Original behavior: only show primitive fields that exist in data
      fieldsToShow = Object.keys(raw).filter((k) => {
        const v = raw[k];
        return v === null || ["string", "number", "boolean"].includes(typeof v);
      });
    }

    // Preferred ordering for common GitHub fields
    const preferredOrder = [
      "login",
      "id",
      "node_id",
      "avatar_url",
      "gravatar_id",
      "url",
      "html_url",
      "followers_url",
      "following_url",
      "gists_url",
      "starred_url",
      "subscriptions_url",
      "organizations_url",
      "repos_url",
      "events_url",
      "received_events_url",
      "type",
      "site_admin",
      "name",
      "company",
      "blog",
      "location",
      "email",
      "hireable",
      "bio",
      "twitter_username",
      "public_repos",
      "public_gists",
      "followers",
      "following",
      "created_at",
      "updated_at",
    ];

    fieldsToShow.sort((a, b) => {
      const ai = preferredOrder.indexOf(a);
      const bi = preferredOrder.indexOf(b);
      if (ai !== -1 && bi !== -1) return ai - bi;
      if (ai !== -1) return -1;
      if (bi !== -1) return 1;
      return a.localeCompare(b);
    });

    const entries: TableEntry[] = fieldsToShow.map((key) => ({
      key,
      value: raw[key],
      status: "unchanged" as DiffStatus,
    }));

    if (diffEnabled && snapshotRaw && typeof snapshotRaw === "object") {
      const prev: Record<string, any> = snapshotRaw as any;
      const prevPrimitiveKeys = Object.keys(prev).filter((k) => {
        const v = prev[k];
        return v === null || ["string", "number", "boolean"].includes(typeof v);
      });
      const currentSet = new Set(
        fieldsToShow.filter((k) => raw[k] !== undefined),
      );
      const prevSet = new Set(prevPrimitiveKeys);
      // Mark added / changed
      for (const e of entries) {
        if (!prevSet.has(e.key)) {
          e.status = "added";
        } else {
          const prevVal = prev[e.key];
          if (prevVal !== e.value) {
            e.status = "changed";
            e.previousValue = prevVal;
          }
        }
      }
      // Collect removed
      for (const k of prevPrimitiveKeys) {
        if (!currentSet.has(k)) {
          entries.push({
            key: k,
            value: undefined,
            previousValue: prev[k],
            status: "removed",
          });
        }
      }
    }

    let filtered = entries;
    if (search.trim()) {
      const q = search.toLowerCase();
      filtered = entries.filter(
        (e) =>
          e.key.toLowerCase().includes(q) ||
          (e.value !== undefined &&
            String(e.value).toLowerCase().includes(q)) ||
          (e.previousValue !== undefined &&
            String(e.previousValue).toLowerCase().includes(q)),
      );
    }
    // For deterministic ordering when diff, ensure removed keys appear after normal ordering
    filtered.sort((a, b) => {
      const ai = preferredOrder.indexOf(a.key);
      const bi = preferredOrder.indexOf(b.key);
      if (ai !== -1 && bi !== -1) return ai - bi;
      if (ai !== -1) return -1;
      if (bi !== -1) return 1;
      return a.key.localeCompare(b.key);
    });
    // Ensure removed at bottom
    filtered.sort((a, b) => {
      const order = (s: DiffStatus) => (s === "removed" ? 1 : 0);
      return order(a.status) - order(b.status);
    });
    return filtered;
  }, [
    user.rawData,
    search,
    diffEnabled,
    snapshotRaw,
    showAllFields,
    user.provider,
  ]);

  const diffSummary = useMemo(() => {
    if (!diffEnabled) return null;
    let added = 0,
      removed = 0,
      changed = 0;
    for (const e of tableEntries) {
      if (e.status === "added") added++;
      else if (e.status === "removed") removed++;
      else if (e.status === "changed") changed++;
    }
    if (!added && !removed && !changed) return null;
    return { added, removed, changed };
  }, [diffEnabled, tableEntries]);

  const toggleDiff = () => {
    const next = !diffEnabled;
    setDiffEnabled(next);
    localStorage.setItem("diff_enabled", String(next));
  };

  const toggleShowAllFields = () => {
    const next = !showAllFields;
    setShowAllFields(next);
    localStorage.setItem("show_all_fields", String(next));
  };

  // Keyboard shortcuts
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      const meta = e.metaKey || e.ctrlKey; // Support Cmd (mac) and Ctrl (win/linux)
      if (meta && e.key.toLowerCase() === "k") {
        // Cmd+K focus search
        e.preventDefault();
        if (searchInputRef.current) searchInputRef.current.focus();
      } else if (meta && e.key.toLowerCase() === "e") {
        // Cmd+E export
        e.preventDefault();
        exportSnapshot();
      } else if (meta && e.shiftKey && e.key.toLowerCase() === "c") {
        // Cmd+Shift+C copy JSON
        e.preventDefault();
        handleCopy();
      }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [exportSnapshot, handleCopy]);

  return (
    <div className="mt-8 w-full animate-fade-in">
      {/* Header */}
      <div className="flex flex-col sm:flex-row items-center sm:items-start text-center sm:text-left bg-slate-800/50 p-6 rounded-t-xl border-b border-slate-700">
        <img
          src={user.avatarUrl}
          alt={`${user.username}'s avatar`}
          className="w-24 h-24 rounded-full border-4 border-slate-600 shadow-lg"
        />
        <div className="mt-4 sm:mt-0 sm:ml-6 w-full">
          <div className="flex items-center justify-center sm:justify-start gap-3 flex-wrap">
            <ProviderIcon
              provider={user.provider}
              className="w-8 h-8 text-white"
            />
            <h2 className="text-3xl font-bold text-white break-all">
              {safeMode ? "••••••" : user.name || user.username}
            </h2>
          </div>
          <div className="flex flex-col sm:flex-row sm:items-center sm:gap-4 mt-2">
            <a
              href={user.profileUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="text-lg text-blue-400 hover:text-blue-300 break-all"
            >
              @{safeMode ? "masked" : user.username}
            </a>
            {user.email && (
              <p className="text-slate-400 break-all">
                {safeMode ? "hidden@example.com" : user.email}
              </p>
            )}
          </div>
          {/* Enhanced Token Display */}
          {!safeMode && (
            <TokenDisplay
              accessToken={user.accessToken}
              idToken={user.idToken}
              refreshToken={user.refreshToken}
              safeMode={safeMode}
            />
          )}

          {/* Token Management Actions */}
          {(user.accessToken || user.refreshToken) && !safeMode && (
            <div className="mt-4 bg-slate-900/60 border border-slate-700 rounded-md p-3 space-y-2">
              <div className="w-full mb-2">
                <h4 className="text-xs uppercase tracking-wide text-slate-400 mb-1">
                  Token Lifecycle Management
                </h4>
                <p className="text-[10px] text-slate-500 leading-relaxed">
                  Demonstrates OAuth token refresh and revocation best practices
                  for secure application development.
                </p>
              </div>

              <div className="flex flex-wrap gap-2">
                {user.refreshToken && onTokenRefresh ? (
                  <div className="flex flex-col">
                    <button
                      onClick={onTokenRefresh}
                      className="text-[10px] px-3 py-1.5 rounded bg-blue-700/60 border border-blue-600 text-blue-200 hover:bg-blue-700 transition-colors"
                      title="Use refresh token to get a new access token without re-authentication"
                    >
                      🔄 Refresh Token
                    </button>
                    <div className="text-[9px] text-slate-500 mt-1 max-w-48">
                      Refresh tokens allow getting new access tokens without
                      re-authentication
                    </div>
                  </div>
                ) : (
                  <div className="flex flex-col">
                    <div className="text-[10px] px-3 py-1.5 rounded bg-slate-700/40 border border-slate-600 text-slate-400">
                      🔄 No Refresh Token
                    </div>
                    <div className="text-[9px] text-slate-500 mt-1 max-w-48">
                      {user.provider === "github"
                        ? "GitHub OAuth Apps don't support refresh tokens (only GitHub Apps do)"
                        : "This session doesn't have a refresh token available"}
                    </div>
                  </div>
                )}

                {onTokenRevocation && (
                  <div className="flex flex-col">
                    <button
                      onClick={onTokenRevocation}
                      className="text-[10px] px-3 py-1.5 rounded bg-red-700/60 border border-red-600 text-red-200 hover:bg-red-700 transition-colors"
                      title="Revoke the access token immediately for security (will log you out)"
                    >
                      🚫 Revoke Token
                    </button>
                    <div className="text-[9px] text-slate-500 mt-1 max-w-48">
                      Immediately invalidates the token - important for security
                      when compromised
                    </div>
                  </div>
                )}
              </div>
            </div>
          )}
          {(user.scopes ||
            user.tokenType ||
            user.tokenExpiresAt ||
            user.jwtPayload) && (
            <div className="mt-4 bg-slate-900/60 border border-slate-700 rounded-md p-3 text-left space-y-2">
              <h4 className="text-xs uppercase tracking-wide text-slate-400">
                Token Analysis
              </h4>
              <ul className="text-[10px] sm:text-xs space-y-1 text-slate-300">
                {user.tokenType && (
                  <li>
                    <span className="text-slate-500">Type:</span>{" "}
                    {user.tokenType}
                  </li>
                )}
                {user.scopes && user.scopes.length > 0 && (
                  <li>
                    <span className="text-slate-500">Scopes:</span>{" "}
                    {user.scopes.join(", ")}
                  </li>
                )}
                {user.tokenExpiresAt && (
                  <li>
                    <span className="text-slate-500">Expires:</span>{" "}
                    {new Date(user.tokenExpiresAt).toLocaleString()} (
                    {Math.max(
                      0,
                      Math.round((user.tokenExpiresAt - Date.now()) / 1000),
                    )}
                    s)
                  </li>
                )}
                {user.jwtPayload && (
                  <li className="break-all">
                    <span className="text-slate-500">JWT aud:</span>{" "}
                    {user.jwtPayload.aud || "—"}
                  </li>
                )}
              </ul>
            </div>
          )}
        </div>
      </div>
      {/* Body: table + JSON */}
      <div className="bg-slate-800/50 p-0 rounded-b-xl overflow-hidden">
        <div className="flex flex-wrap gap-2 p-4 border-b border-slate-700 bg-slate-900/40">
          <span className="text-xs uppercase tracking-wide text-slate-400 self-center">
            View Mode:
          </span>
          {(["both", "table", "json", "api", "snippets"] as const).map((m) => (
            <button
              key={m}
              onClick={() => updateViewMode(m)}
              className={`text-xs px-3 py-1 rounded border transition-colors ${viewMode === m ? "bg-slate-600 border-slate-500 text-white" : "bg-slate-700/40 border-slate-600 text-slate-300 hover:bg-slate-700"}`}
            >
              {m === "both"
                ? "Both"
                : m === "table"
                  ? "Table"
                  : m === "json"
                    ? "JSON"
                    : m === "api"
                      ? "API Explorer"
                      : "Code Snippets"}
            </button>
          ))}
          {importedSnapshot && (
            <button
              onClick={toggleDiff}
              className={`text-xs px-3 py-1 rounded border transition-colors ${diffEnabled ? "bg-amber-600/70 border-amber-500 text-white" : "bg-slate-700/40 border-slate-600 text-slate-300 hover:bg-slate-700"}`}
              title={
                diffEnabled
                  ? "Disable diff highlighting"
                  : "Enable visual diff vs imported snapshot"
              }
            >
              Diff {diffEnabled ? "On" : "Off"}
            </button>
          )}
          <button
            onClick={toggleShowAllFields}
            className={`text-xs px-3 py-1 rounded border transition-colors ${showAllFields ? "bg-blue-600/70 border-blue-500 text-white" : "bg-slate-700/40 border-slate-600 text-slate-300 hover:bg-slate-700"}`}
            title={
              showAllFields
                ? "Show only fields present in current data"
                : "Show all documented schema fields for this provider"
            }
          >
            Schema {showAllFields ? "On" : "Off"}
          </button>
          <button
            onClick={exportSnapshot}
            className="ml-auto text-xs px-3 py-1 rounded border bg-slate-700/40 border-slate-600 text-slate-300 hover:bg-slate-700 transition-colors"
          >
            Export Snapshot
          </button>
          {importedSnapshot && (
            <span className="text-[10px] text-emerald-300 self-center">
              Snapshot Loaded
            </span>
          )}
        </div>
        <div className={viewMode === "both" ? "grid md:grid-cols-2 gap-0" : ""}>
          {/* API Explorer Section */}
          {viewMode === "api" && (
            <div className="p-6">
              <ApiExplorer user={user} />
            </div>
          )}

          {/* Code Snippets Section */}
          {viewMode === "snippets" && (
            <div className="p-6">
              <CodeSnippetGenerator user={user} />
            </div>
          )}

          {/* Structured Table */}
          {viewMode !== "json" &&
            viewMode !== "api" &&
            viewMode !== "snippets" && (
              <div
                className={`p-6 ${viewMode === "both" ? "border-b md:border-b-0 md:border-r" : ""} border-slate-700 overflow-x-auto`}
              >
                <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 mb-4">
                  <h3 className="text-xl font-semibold text-slate-200">
                    Provider Data Dump
                  </h3>
                  <input
                    type="text"
                    value={search}
                    onChange={(e) => setSearch(e.target.value)}
                    placeholder="Filter (key or value)"
                    ref={searchInputRef}
                    className="w-full sm:w-64 text-sm px-3 py-1.5 bg-slate-900/70 border border-slate-600 rounded-md focus:outline-none focus:ring-2 focus:ring-slate-500 text-slate-200 placeholder-slate-500"
                  />
                </div>
                {diffSummary && (
                  <div className="flex flex-wrap gap-3 mb-3 text-[11px] font-mono">
                    <span className="px-2 py-0.5 rounded bg-emerald-900/40 border border-emerald-600 text-emerald-300">
                      added: {diffSummary.added}
                    </span>
                    <span className="px-2 py-0.5 rounded bg-amber-900/40 border border-amber-600 text-amber-300">
                      changed: {diffSummary.changed}
                    </span>
                    <span className="px-2 py-0.5 rounded bg-rose-900/40 border border-rose-600 text-rose-300">
                      removed: {diffSummary.removed}
                    </span>
                  </div>
                )}
                <table className="w-full text-left text-sm border-collapse">
                  <thead>
                    <tr className="text-slate-400 text-xs uppercase tracking-wide">
                      <th className="py-2 pr-3 font-medium">Field</th>
                      <th className="py-2 font-medium">Value</th>
                    </tr>
                  </thead>
                  <tbody>
                    {tableEntries.map(
                      ({ key, value, previousValue, status }) => {
                        const display = renderPrimitive(value);
                        const isLink =
                          typeof value === "string" && isUrl(value);
                        const isFieldPresent = value !== undefined;
                        const isSchemaField = showAllFields && !isFieldPresent;
                        const plainValue =
                          value === undefined
                            ? previousValue === undefined
                              ? ""
                              : String(previousValue)
                            : typeof value === "string" ||
                                typeof value === "number" ||
                                typeof value === "boolean"
                              ? String(value)
                              : JSON.stringify(value);
                        const doc = getFieldDoc(user.provider, key);

                        let statusClasses = "";
                        if (diffEnabled) {
                          statusClasses =
                            status === "added"
                              ? "bg-emerald-900/20 border-l-2 border-emerald-500"
                              : status === "changed"
                                ? "bg-amber-900/20 border-l-2 border-amber-500"
                                : status === "removed"
                                  ? "bg-rose-900/20 border-l-2 border-rose-500 opacity-80"
                                  : "";
                        } else if (showAllFields && isSchemaField) {
                          statusClasses =
                            "bg-slate-800/30 border-l-2 border-slate-500";
                        }

                        return (
                          <tr
                            key={key}
                            className={`border-t border-slate-700/60 hover:bg-slate-700/30 ${statusClasses}`}
                          >
                            <td className="py-2 pr-3 align-top text-slate-300 font-mono text-[11px] sm:text-xs break-all">
                              <div className="flex items-start gap-1 group">
                                <span
                                  className={
                                    isSchemaField ? "text-slate-500" : ""
                                  }
                                >
                                  {key}
                                </span>
                                {diffEnabled && status !== "unchanged" && (
                                  <span className="text-[9px] uppercase tracking-wide rounded px-1 py-0.5 bg-slate-600/60 text-slate-200">
                                    {status}
                                  </span>
                                )}
                                {showAllFields && isSchemaField && (
                                  <span className="text-[9px] uppercase tracking-wide rounded px-1 py-0.5 bg-slate-600/40 text-slate-400">
                                    schema
                                  </span>
                                )}
                                {doc && (
                                  <span className="relative inline-block">
                                    <span
                                      className="w-3 h-3 mt-[2px] text-[9px] leading-none flex items-center justify-center rounded-full bg-slate-600 text-slate-100 cursor-help group-hover:bg-slate-500"
                                      title={`${doc.description}${doc.docsUrl ? `\nDocs: ${doc.docsUrl}` : ""}`}
                                      aria-label={`Field info: ${doc.description}`}
                                    >
                                      i
                                    </span>
                                  </span>
                                )}
                              </div>
                            </td>
                            <td className="py-2 align-top text-slate-100 text-[11px] sm:text-xs break-all">
                              <div className="flex items-start gap-2">
                                <div className="flex-1 min-w-0">
                                  {status === "removed" ? (
                                    <span
                                      className="line-through text-slate-500"
                                      title="Removed in current data"
                                    >
                                      {renderPrimitive(previousValue)}
                                    </span>
                                  ) : isSchemaField ? (
                                    <span
                                      className="text-slate-500 italic"
                                      title="Field documented but not present in current data"
                                    >
                                      (not present)
                                    </span>
                                  ) : isLink ? (
                                    <a
                                      href={value as string}
                                      target="_blank"
                                      rel="noopener noreferrer"
                                      className="text-blue-400 hover:text-blue-300"
                                    >
                                      Link
                                    </a>
                                  ) : (
                                    display || (
                                      <span className="text-slate-500">
                                        (object)
                                      </span>
                                    )
                                  )}
                                  {status === "changed" && (
                                    <div className="mt-1 text-[10px] text-amber-300/80">
                                      prev: {renderPrimitive(previousValue)}
                                    </div>
                                  )}
                                </div>
                                {!isSchemaField && (
                                  <button
                                    onClick={() =>
                                      navigator.clipboard.writeText(plainValue)
                                    }
                                    className="shrink-0 p-1 rounded bg-slate-700/50 hover:bg-slate-600 text-slate-300 border border-slate-600"
                                    title={
                                      status === "removed"
                                        ? "Copy previous value"
                                        : "Copy value"
                                    }
                                  >
                                    <ClipboardIcon className="w-3 h-3" />
                                  </button>
                                )}
                              </div>
                            </td>
                          </tr>
                        );
                      },
                    )}
                    {tableEntries.length === 0 && (
                      <tr>
                        <td
                          colSpan={2}
                          className="py-4 text-center text-slate-500 text-xs"
                        >
                          No matching fields
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            )}
          {/* Raw JSON */}
          {viewMode !== "table" &&
            viewMode !== "api" &&
            viewMode !== "snippets" && (
              <div className="p-6">
                <div className="flex justify-between items-center mb-3">
                  <h3 className="text-xl font-semibold text-slate-200">
                    Raw JSON Data
                  </h3>
                  <div className="flex gap-2">
                    <JsonViewToggle
                      copyHandler={handleCopy}
                      isCopied={isCopied}
                    />
                  </div>
                </div>
                <JsonViewContainer data={user.rawData} />
              </div>
            )}
        </div>
      </div>
    </div>
  );
};

// Local component state for JSON view mode (tree/raw) persisted via localStorage
const JsonViewToggle: React.FC<{
  copyHandler: () => void;
  isCopied: boolean;
}> = ({ copyHandler, isCopied }) => {
  const [mode, setMode] = useState<"tree" | "raw">(() => {
    const stored = localStorage.getItem("json_view_mode");
    return stored === "raw" ? "raw" : "tree";
  });
  useEffect(() => {
    localStorage.setItem("json_view_mode", mode);
  }, [mode]);
  return (
    <>
      <div className="flex items-center bg-slate-700/40 border border-slate-600 rounded-md overflow-hidden text-[11px]">
        {(["tree", "raw"] as const).map((m) => (
          <button
            key={m}
            onClick={() => setMode(m)}
            className={`px-2 py-1 ${mode === m ? "bg-slate-600 text-white" : "text-slate-300 hover:bg-slate-600/40"}`}
            title={m === "tree" ? "Tree view" : "Raw JSON view"}
          >
            {m}
          </button>
        ))}
      </div>
      <button
        onClick={copyHandler}
        className="flex items-center px-3 py-1.5 bg-slate-700/50 border border-slate-600 rounded-md text-xs text-slate-300 hover:bg-slate-700 transition-all"
      >
        {isCopied ? (
          <>
            <ClipboardCheckIcon className="w-4 h-4 mr-1.5 text-green-400" />
            Copied!
          </>
        ) : (
          <>
            <ClipboardIcon className="w-4 h-4 mr-1.5" />
            Copy JSON
          </>
        )}
      </button>
    </>
  );
};

const JsonViewContainer: React.FC<{ data: any }> = ({ data }) => {
  const [mode, setMode] = useState<"tree" | "raw">(() => {
    const stored = localStorage.getItem("json_view_mode");
    return stored === "raw" ? "raw" : "tree";
  });
  useEffect(() => {
    const handler = () =>
      setMode(
        localStorage.getItem("json_view_mode") === "raw" ? "raw" : "tree",
      );
    window.addEventListener("storage", handler);
    return () => window.removeEventListener("storage", handler);
  }, []);
  return (
    <div className="max-h-[50vh] overflow-y-auto bg-slate-900/70 p-4 rounded-lg border border-slate-700 font-mono">
      {mode === "tree" ? (
        <JsonTree data={data} />
      ) : (
        <pre className="text-xs text-slate-200 whitespace-pre-wrap break-all">
          {JSON.stringify(data, null, 2)}
        </pre>
      )}
    </div>
  );
};

export default UserInfoDisplay;
