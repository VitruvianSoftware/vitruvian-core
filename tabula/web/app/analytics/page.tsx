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

import { useEffect } from "react";
import Link from "next/link";
import { useWorkspaceStore } from "@/lib/store";
import { Section, Task } from "@/types";

interface MetricCardProps {
  title: string;
  value: number | string;
}

function MetricCard({ title, value }: MetricCardProps) {
  return (
    <div className="rounded-lg bg-white p-6 shadow">
      <h3 className="text-sm font-medium text-gray-600">{title}</h3>
      <div className="mt-2 flex items-baseline">
        <p className="text-3xl font-semibold text-gray-900">{value}</p>
      </div>
    </div>
  );
}

export default function AnalyticsPage() {
  const { workspaces, dataSource, loading, error, fetchWorkspaces } =
    useWorkspaceStore();

  useEffect(() => {
    fetchWorkspaces();
  }, [fetchWorkspaces]);

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-gray-50">
        <div className="text-center">
          <div className="mb-4 h-12 w-12 animate-spin rounded-full border-4 border-blue-200 border-t-blue-600 mx-auto" />
          <p className="text-lg text-gray-600">Loading analytics...</p>
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

  // Calculate analytics
  const totalWorkspaces = workspaces.length;
  const totalTabs = workspaces.reduce(
    (acc, ws) => acc + (ws.tabs?.length || 0),
    0,
  );
  const totalResources = workspaces.reduce(
    (acc, ws) =>
      acc +
      (ws.resources?.length || 0) +
      (ws.sections?.reduce(
        (sAcc: number, s: Section) => sAcc + (s.resources?.length || 0),
        0,
      ) || 0),
    0,
  );
  const totalNotes = workspaces.reduce(
    (acc, ws) => acc + (ws.notes?.length || 0),
    0,
  );
  const totalTasks = workspaces.reduce(
    (acc, ws) => acc + (ws.tasks?.length || 0),
    0,
  );
  const completedTasks = workspaces.reduce(
    (acc, ws) => acc + (ws.tasks?.filter((t: Task) => t.completed).length || 0),
    0,
  );

  // Calculate task completion percentage
  const taskCompletionRate =
    totalTasks > 0 ? Math.round((completedTasks / totalTasks) * 100) : 0;

  // Most active workspace (by tabs count)
  const mostActiveWorkspace = [...workspaces].sort(
    (a, b) => (b.tabs?.length || 0) - (a.tabs?.length || 0),
  )[0];

  // Workspace with most resources
  const mostResourcedWorkspace = [...workspaces].sort((a, b) => {
    const aResources =
      (a.resources?.length || 0) +
      (a.sections?.reduce(
        (acc: number, s: Section) => acc + (s.resources?.length || 0),
        0,
      ) || 0);
    const bResources =
      (b.resources?.length || 0) +
      (b.sections?.reduce(
        (acc: number, s: Section) => acc + (s.resources?.length || 0),
        0,
      ) || 0);
    return bResources - aResources;
  })[0];

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <header className="border-b bg-white">
        <div className="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
          <div>
            <Link
              href="/"
              className="mb-2 inline-block text-sm text-blue-600 hover:text-blue-700"
            >
              ← Back to Dashboard
            </Link>
            <h1 className="text-3xl font-bold text-gray-900">Analytics</h1>
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

        {/* Summary Stats - No fake trends */}
        <div className="mb-8 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4">
          <MetricCard title="Total Workspaces" value={totalWorkspaces} />
          <MetricCard title="Total Tabs" value={totalTabs} />
          <MetricCard title="Total Resources" value={totalResources} />
          <MetricCard
            title="Task Completion"
            value={totalTasks > 0 ? `${taskCompletionRate}%` : "N/A"}
          />
        </div>

        {/* Detailed Analytics */}
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
          {/* Workspace Distribution */}
          <div className="rounded-lg bg-white p-6 shadow">
            <h2 className="mb-4 text-lg font-semibold text-gray-900">
              Workspace Distribution
            </h2>
            {workspaces.length === 0 ? (
              <p className="text-gray-500">No workspaces to display.</p>
            ) : (
              <div className="space-y-4">
                {workspaces.slice(0, 5).map((workspace) => {
                  const tabCount = workspace.tabs?.length || 0;
                  const percentage =
                    totalTabs > 0 ? (tabCount / totalTabs) * 100 : 0;

                  return (
                    <div key={workspace.id}>
                      <div className="mb-1 flex items-center justify-between">
                        <span className="text-sm font-medium text-gray-700">
                          {workspace.name}
                        </span>
                        <span className="text-sm text-gray-500">
                          {tabCount} tabs
                        </span>
                      </div>
                      <div className="h-2 w-full rounded-full bg-gray-200">
                        <div
                          className="h-2 rounded-full bg-blue-600"
                          style={{ width: `${percentage}%` }}
                        />
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          {/* Insights */}
          <div className="rounded-lg bg-white p-6 shadow">
            <h2 className="mb-4 text-lg font-semibold text-gray-900">
              Insights
            </h2>
            <div className="space-y-4">
              {mostActiveWorkspace &&
              (mostActiveWorkspace.tabs?.length || 0) > 0 ? (
                <div className="rounded-lg bg-blue-50 p-4">
                  <h3 className="font-medium text-blue-900">
                    Most Active Workspace
                  </h3>
                  <p className="mt-1 text-sm text-blue-700">
                    <strong>{mostActiveWorkspace.name}</strong> has the most
                    tabs ({mostActiveWorkspace.tabs?.length || 0})
                  </p>
                </div>
              ) : (
                <div className="rounded-lg bg-gray-50 p-4">
                  <h3 className="font-medium text-gray-700">
                    Most Active Workspace
                  </h3>
                  <p className="mt-1 text-sm text-gray-500">
                    No tabs tracked yet
                  </p>
                </div>
              )}

              {mostResourcedWorkspace &&
              (mostResourcedWorkspace.resources?.length || 0) > 0 ? (
                <div className="rounded-lg bg-green-50 p-4">
                  <h3 className="font-medium text-green-900">Most Resourced</h3>
                  <p className="mt-1 text-sm text-green-700">
                    <strong>{mostResourcedWorkspace.name}</strong> has the most
                    resources
                  </p>
                </div>
              ) : (
                <div className="rounded-lg bg-gray-50 p-4">
                  <h3 className="font-medium text-gray-700">Most Resourced</h3>
                  <p className="mt-1 text-sm text-gray-500">
                    No resources saved yet
                  </p>
                </div>
              )}

              <div className="rounded-lg bg-purple-50 p-4">
                <h3 className="font-medium text-purple-900">
                  Productivity Score
                </h3>
                <p className="mt-1 text-sm text-purple-700">
                  {totalTasks > 0 ? (
                    <>
                      You have completed {completedTasks} out of {totalTasks}{" "}
                      tasks across all workspaces
                    </>
                  ) : (
                    "No tasks created yet"
                  )}
                </p>
              </div>
            </div>
          </div>
        </div>

        {/* Additional Stats */}
        <div className="mt-8 rounded-lg bg-white p-6 shadow">
          <h2 className="mb-4 text-lg font-semibold text-gray-900">
            Content Breakdown
          </h2>
          <div className="grid grid-cols-1 gap-6 sm:grid-cols-3">
            <div className="text-center">
              <div className="text-3xl font-bold text-blue-600">
                {totalNotes}
              </div>
              <div className="mt-1 text-sm text-gray-600">Total Notes</div>
            </div>
            <div className="text-center">
              <div className="text-3xl font-bold text-green-600">
                {totalResources}
              </div>
              <div className="mt-1 text-sm text-gray-600">Total Resources</div>
            </div>
            <div className="text-center">
              <div className="text-3xl font-bold text-purple-600">
                {totalTabs}
              </div>
              <div className="mt-1 text-sm text-gray-600">Active Tabs</div>
            </div>
          </div>
        </div>
      </main>
    </div>
  );
}
