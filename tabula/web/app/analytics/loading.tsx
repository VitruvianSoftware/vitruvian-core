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

/**
 * Loading state for analytics page
 */
export default function AnalyticsLoading() {
  return (
    <div className="min-h-screen bg-ink">
      {/* Header skeleton */}
      <header className="border-b bg-ink-2">
        <div className="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
          <div className="h-4 w-32 animate-pulse bg-ink-3 mb-2" />
          <div className="h-8 w-32 animate-pulse bg-ink-3" />
        </div>
      </header>

      {/* Content skeleton */}
      <main className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
        {/* Stats grid skeleton */}
        <div className="mb-8 grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4">
          {[1, 2, 3, 4].map((i) => (
            <div key={i} className="bg-ink-2 p-6 shadow">
              <div className="h-4 w-24 animate-pulse bg-ink-3 mb-2" />
              <div className="h-8 w-16 animate-pulse bg-ink-3" />
            </div>
          ))}
        </div>

        {/* Charts skeleton */}
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
          <div className="bg-ink-2 p-6 shadow">
            <div className="h-6 w-48 animate-pulse bg-ink-3 mb-4" />
            <div className="space-y-4">
              {[1, 2, 3, 4, 5].map((i) => (
                <div key={i}>
                  <div className="flex justify-between mb-1">
                    <div className="h-4 w-24 animate-pulse bg-ink-3" />
                    <div className="h-4 w-12 animate-pulse bg-ink-3" />
                  </div>
                  <div className="h-2 w-full animate-pulse rounded-full bg-ink-3" />
                </div>
              ))}
            </div>
          </div>
          <div className="bg-ink-2 p-6 shadow">
            <div className="h-6 w-24 animate-pulse bg-ink-3 mb-4" />
            <div className="space-y-4">
              {[1, 2, 3].map((i) => (
                <div key={i} className="bg-ink-2 p-4">
                  <div className="h-5 w-32 animate-pulse bg-ink-3 mb-2" />
                  <div className="h-4 w-full animate-pulse bg-ink-3" />
                </div>
              ))}
            </div>
          </div>
        </div>
      </main>
    </div>
  );
}
