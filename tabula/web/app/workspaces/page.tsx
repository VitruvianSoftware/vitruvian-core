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

"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useWorkspaceStore } from "@/lib/store";
import type { Workspace } from "@/types";

interface WorkspaceCardProps {
  workspace: Workspace;
}

function WorkspaceCard({ workspace }: WorkspaceCardProps) {
  const tabCount = workspace.tabs?.length || 0;
  const resourceCount =
    (workspace.resources?.length || 0) +
    (workspace.sections?.reduce(
      (acc, s) => acc + (s.resources?.length || 0),
      0,
    ) || 0);
  const noteCount = workspace.notes?.length || 0;
  const taskCount = workspace.tasks?.length || 0;
  const completedTasks =
    workspace.tasks?.filter((t) => t.completed).length || 0;

  return (
    <div className="rounded-lg bg-white p-6 shadow transition-shadow hover:shadow-lg">
      <div className="mb-4 flex items-start justify-between">
        <div className="flex items-center gap-3">
          {workspace.icon && <span className="text-2xl">{workspace.icon}</span>}
          <div>
            <h3 className="text-lg font-semibold text-gray-900">
              {workspace.name}
            </h3>
            {workspace.description && (
              <p className="mt-1 text-sm text-gray-600">
                {workspace.description}
              </p>
            )}
          </div>
        </div>
      </div>

      <div className="space-y-2">
        <div className="flex items-center justify-between text-sm">
          <span className="text-gray-600">Tabs:</span>
          <span className="font-medium text-gray-900">{tabCount}</span>
        </div>
        <div className="flex items-center justify-between text-sm">
          <span className="text-gray-600">Resources:</span>
          <span className="font-medium text-gray-900">{resourceCount}</span>
        </div>
        <div className="flex items-center justify-between text-sm">
          <span className="text-gray-600">Notes:</span>
          <span className="font-medium text-gray-900">{noteCount}</span>
        </div>
        <div className="flex items-center justify-between text-sm">
          <span className="text-gray-600">Tasks:</span>
          <span className="font-medium text-gray-900">
            {completedTasks}/{taskCount}
          </span>
        </div>
      </div>

      {workspace.tabs && workspace.tabs.length > 0 && (
        <div className="mt-4 border-t pt-4">
          <p className="mb-2 text-xs font-semibold uppercase text-gray-500">
            Recent Tabs
          </p>
          <div className="space-y-1">
            {workspace.tabs.slice(0, 3).map((tab, index) => (
              <div
                key={`${tab.url}-${index}`}
                className="truncate text-sm text-gray-700"
              >
                • {tab.title || tab.url}
              </div>
            ))}
            {workspace.tabs.length > 3 && (
              <div className="text-xs text-gray-500">
                +{workspace.tabs.length - 3} more tabs
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

export default function WorkspacesPage() {
  const { workspaces, dataSource, loading, error, fetchWorkspaces } =
    useWorkspaceStore();
  const [searchQuery, setSearchQuery] = useState("");

  useEffect(() => {
    fetchWorkspaces();
  }, [fetchWorkspaces]);

  const filteredWorkspaces = workspaces.filter(
    (workspace) =>
      workspace.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
      workspace.description?.toLowerCase().includes(searchQuery.toLowerCase()),
  );

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-gray-50">
        <div className="text-center">
          <div className="mb-4 h-12 w-12 animate-spin rounded-full border-4 border-blue-200 border-t-blue-600 mx-auto" />
          <p className="text-lg text-gray-600">Loading workspaces...</p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-gray-50">
        <div className="text-center">
          <p className="text-lg text-red-600">{error}</p>
          <button
            type="button"
            onClick={() => fetchWorkspaces()}
            className="mt-4 rounded-md bg-blue-600 px-4 py-2 text-white hover:bg-blue-700"
          >
            Retry
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <header className="border-b bg-white">
        <div className="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between">
            <div>
              <Link
                href="/"
                className="mb-2 inline-block text-sm text-blue-600 hover:text-blue-700"
              >
                ← Back to Dashboard
              </Link>
              <h1 className="text-3xl font-bold text-gray-900">Workspaces</h1>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
        {/* Data Source Info */}
        {dataSource && dataSource.type !== "chrome-storage" && (
          <div className="mb-6 rounded-lg bg-yellow-50 p-4 text-yellow-800">
            <p className="text-sm">{dataSource.message}</p>
          </div>
        )}

        {/* Search */}
        <div className="mb-6">
          <input
            type="text"
            placeholder="Search workspaces..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full rounded-lg border border-gray-300 px-4 py-2 focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
          />
        </div>

        {/* Workspaces Grid */}
        {filteredWorkspaces.length === 0 ? (
          <div className="rounded-lg bg-white p-12 text-center shadow">
            <p className="text-lg text-gray-600">
              {searchQuery
                ? "No workspaces found matching your search."
                : "No workspaces yet."}
            </p>
            <p className="mt-2 text-sm text-gray-500">
              Create workspaces in the Tabula browser extension.
            </p>
          </div>
        ) : (
          <div className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
            {filteredWorkspaces.map((workspace) => (
              <WorkspaceCard key={workspace.id} workspace={workspace} />
            ))}
          </div>
        )}
      </main>
    </div>
  );
}
