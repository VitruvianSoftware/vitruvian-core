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

/* eslint-disable @next/next/no-img-element */
import { useEffect } from "react";
import Link from "next/link";
import { Button } from "@vitruviansoftware/design-system";
import { useWorkspaceStore } from "@/lib/store";
import { exportWorkspaces, downloadFile, seedDemoData } from "@/lib/data";

interface StatCardProps {
  title: string;
  value: number | string;
  icon: string;
  color: string;
}

function StatCard({ title, value, icon, color }: StatCardProps) {
  const colorClasses: Record<string, string> = {
    blue: "bg-blue-100 text-blue-600",
    purple: "bg-purple-100 text-purple-600",
    green: "bg-green-100 text-green-600",
    yellow: "bg-yellow-100 text-yellow-600",
    indigo: "bg-indigo-100 text-indigo-600",
    pink: "bg-pink-100 text-pink-600",
  };

  return (
    <div className=" bg-ink-2 p-6 shadow">
      <div className="flex items-center justify-between">
        <div>
          <p className="text-sm font-medium text-paper-dim">{title}</p>
          <p className="mt-2 text-3xl font-semibold text-paper">{value}</p>
        </div>
        <div
          className={`flex h-12 w-12 items-center justify-center ${colorClasses[color]}`}
        >
          <span className="text-2xl">{icon}</span>
        </div>
      </div>
    </div>
  );
}

export default function Home() {
  const { stats, dataSource, loading, error, fetchStats, user, login, logout } =
    useWorkspaceStore();

  useEffect(() => {
    fetchStats();
  }, [fetchStats]);

  const handleExport = async (format: "json" | "csv") => {
    try {
      const content = await exportWorkspaces(format);
      const filename = `tabula-export-${new Date().toISOString().split("T")[0]}.${format}`;
      const mimeType = format === "json" ? "application/json" : "text/csv";
      downloadFile(content, filename, mimeType);
    } catch (exportError) {
      console.error("Export failed:", exportError);
    }
  };

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-ink">
        <div className="text-center">
          <div className="mb-4 h-12 w-12 animate-spin rounded-full border-4 border-blue-200 border-t-blue-600 mx-auto" />
          <p className="text-lg text-paper-dim">Loading...</p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-ink">
        <div className="text-center">
          <p className="text-lg text-red-600">{error}</p>
          <Button type="button" onClick={() => fetchStats()}>
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
            <h1 className="text-3xl font-bold text-paper">Tabula Dashboard</h1>
            <div className="flex gap-3">
              <div className="flex gap-3 items-center">
                {user ? (
                  <>
                    <div className="flex items-center gap-2 mr-4">
                      {user.picture && (
                        <img
                          src={user.picture}
                          alt={user.name}
                          className="h-8 w-8 rounded-full border border-hairline"
                        />
                      )}
                      <div className="text-sm">
                        <p className="font-medium text-paper">{user.name}</p>
                        <p className="text-xs text-paper-dim">{user.email}</p>
                      </div>
                    </div>
                    <button
                      type="button"
                      onClick={() => logout()}
                      className="text-sm font-medium text-paper-dim hover:text-paper"
                    >
                      Logout
                    </button>
                  </>
                ) : (
                  <button
                    type="button"
                    onClick={() => login()}
                    className=" bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700 transition-colors"
                  >
                    Login
                  </button>
                )}
                {/* Export buttons only visible if we have data */}
                {(stats?.totalWorkspaces || 0) > 0 && (
                  <>
                    <div className="h-6 w-px bg-hairline mx-2"></div>
                    <button
                      type="button"
                      onClick={() => handleExport("json")}
                      className=" bg-ink-2 border border-hairline px-3 py-1.5 text-sm font-medium text-paper hover:bg-ink transition-colors"
                    >
                      Export JSON
                    </button>
                  </>
                )}
              </div>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
        {/* Data Source Info */}
        {dataSource &&
          (() => {
            const bannerStyles: Record<string, string> = {
              "chrome-storage": "bg-green-50 text-green-800",
              "local-storage": "bg-yellow-50 text-yellow-800",
              api: "bg-blue-50 text-blue-800",
              none: "bg-ink text-paper-dim",
            };
            const style = bannerStyles[dataSource.type] || bannerStyles.none;

            return (
              <div
                className={`mb-6 flex items-center justify-between p-4 ${style}`}
              >
                <p className="text-sm">{dataSource.message}</p>
                {(dataSource.type === "local-storage" ||
                  dataSource.type === "none") &&
                  (stats?.totalWorkspaces === 0 || !stats) && (
                    <button
                      onClick={() => seedDemoData()}
                      className="ml-4 bg-ink-2 px-3 py-1.5 text-xs font-medium text-paper shadow-sm hover:bg-ink border border-hairline"
                    >
                      Load Demo Data
                    </button>
                  )}
              </div>
            );
          })()}

        {/* Stats Grid */}
        <div className="mb-8 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
          <StatCard
            title="Workspaces"
            value={stats?.totalWorkspaces || 0}
            icon="📁"
            color="blue"
          />
          <StatCard
            title="Open Tabs"
            value={stats?.totalTabs || 0}
            icon="🗂️"
            color="purple"
          />
          <StatCard
            title="Resources"
            value={stats?.totalResources || 0}
            icon="🔗"
            color="green"
          />
          <StatCard
            title="Notes"
            value={stats?.totalNotes || 0}
            icon="📝"
            color="yellow"
          />
          <StatCard
            title="Tasks"
            value={`${stats?.completedTasks || 0}/${stats?.totalTasks || 0}`}
            icon="✓"
            color="indigo"
          />
          <StatCard
            title="Completion Rate"
            value={
              stats?.totalTasks
                ? `${Math.round(((stats.completedTasks || 0) / stats.totalTasks) * 100)}%`
                : "N/A"
            }
            icon="📊"
            color="pink"
          />
        </div>

        {/* Quick Actions */}
        <div className=" bg-ink-2 p-6 shadow">
          <h2 className="mb-4 text-xl font-semibold text-paper">
            Quick Actions
          </h2>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <Link
              href="/workspaces"
              className="flex items-center justify-between border border-hairline p-4 transition-all hover:border-blue-500 hover:shadow-md"
            >
              <div>
                <h3 className="font-medium text-paper">View Workspaces</h3>
                <p className="mt-1 text-sm text-paper-dim">
                  Browse all your workspaces
                </p>
              </div>
              <span className="text-2xl">→</span>
            </Link>

            <Link
              href="/analytics"
              className="flex items-center justify-between border border-hairline p-4 transition-all hover:border-blue-500 hover:shadow-md"
            >
              <div>
                <h3 className="font-medium text-paper">Analytics</h3>
                <p className="mt-1 text-sm text-paper-dim">
                  View detailed statistics
                </p>
              </div>
              <span className="text-2xl">→</span>
            </Link>

            <button
              type="button"
              onClick={() => handleExport("json")}
              className="flex items-center justify-between border border-hairline p-4 text-left transition-all hover:border-blue-500 hover:shadow-md"
            >
              <div>
                <h3 className="font-medium text-paper">Export Data</h3>
                <p className="mt-1 text-sm text-paper-dim">
                  Download your data
                </p>
              </div>
              <span className="text-2xl">⬇</span>
            </button>
          </div>
        </div>

        {/* Info Section */}
        <div className="mt-8 bg-blue-50 p-6">
          <h2 className="mb-2 text-lg font-semibold text-blue-900">
            About Tabula Dashboard
          </h2>
          <p className="text-blue-800">
            This web dashboard provides a centralized view of your Tabula
            workspaces, with analytics and data export capabilities. Use the
            navigation above to explore your workspaces and view detailed
            statistics.
          </p>
        </div>
      </main>
    </div>
  );
}
