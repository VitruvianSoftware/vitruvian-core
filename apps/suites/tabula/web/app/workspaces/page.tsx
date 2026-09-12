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
import {
  Button,
  Input,
  Plate,
  EmptyState,
} from "@vitruviansoftware/design-system";

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
    <Plate
      live
      enter
      className="bg-ink-2 p-6 shadow transition-shadow hover:shadow-lg"
    >
      <div className="mb-4 flex items-start justify-between">
        <div className="flex items-center gap-3">
          {workspace.icon && <span className="text-2xl">{workspace.icon}</span>}
          <div>
            <h3 className="text-lg font-semibold text-paper">
              {workspace.name}
            </h3>
            {workspace.description && (
              <p className="mt-1 text-sm text-paper-dim">
                {workspace.description}
              </p>
            )}
          </div>
        </div>
      </div>

      <div className="space-y-2">
        <div className="flex items-center justify-between text-sm">
          <span className="text-paper-dim">Tabs:</span>
          <span className="font-medium text-paper">{tabCount}</span>
        </div>
        <div className="flex items-center justify-between text-sm">
          <span className="text-paper-dim">Resources:</span>
          <span className="font-medium text-paper">{resourceCount}</span>
        </div>
        <div className="flex items-center justify-between text-sm">
          <span className="text-paper-dim">Notes:</span>
          <span className="font-medium text-paper">{noteCount}</span>
        </div>
        <div className="flex items-center justify-between text-sm">
          <span className="text-paper-dim">Tasks:</span>
          <span className="font-medium text-paper">
            {completedTasks}/{taskCount}
          </span>
        </div>
      </div>

      {workspace.tabs && workspace.tabs.length > 0 && (
        <div className="mt-4 border-t pt-4">
          <p className="mb-2 text-xs font-semibold uppercase text-paper-dim">
            Recent Tabs
          </p>
          <div className="space-y-1">
            {workspace.tabs.slice(0, 3).map((tab, index) => (
              <div
                key={`${tab.url}-${index}`}
                className="truncate text-sm text-paper"
              >
                • {tab.title || tab.url}
              </div>
            ))}
            {workspace.tabs.length > 3 && (
              <div className="text-xs text-paper-dim">
                +{workspace.tabs.length - 3} more tabs
              </div>
            )}
          </div>
        </div>
      )}
    </Plate>
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
      <div className="flex min-h-screen items-center justify-center bg-ink">
        <div className="text-center">
          <div className="mb-4 h-12 w-12 animate-spin rounded-full border-4 border-blue-200 border-t-blue-600 mx-auto" />
          <p className="text-lg text-paper-dim">Loading workspaces...</p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-ink">
        <div className="text-center">
          <p className="text-lg text-red-600">{error}</p>
          <Button
            type="button"
            onClick={() => fetchWorkspaces()}
            className="mt-4"
          >
            Retry
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-ink">
      {/* Header */}
      <header className="border-b bg-ink-2">
        <div className="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between">
            <div>
              <Link
                href="/"
                className="mb-2 inline-block text-sm text-blue-600 hover:text-blue-700"
              >
                ← Back to Dashboard
              </Link>
              <h1 className="text-3xl font-bold text-paper">Workspaces</h1>
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
          <Input
            type="text"
            placeholder="Search workspaces..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
          />
        </div>

        {/* Workspaces Grid */}
        {filteredWorkspaces.length === 0 ? (
          <EmptyState
            title={
              searchQuery
                ? "No workspaces found matching your search."
                : "No workspaces yet."
            }
          >
            Create workspaces in the Tabula browser extension.
          </EmptyState>
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
