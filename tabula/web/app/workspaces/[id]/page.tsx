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

import { useEffect, useState, type ReactNode } from "react";
import { useParams } from "next/navigation";
import type { Workspace } from "@tabula/shared";
import { SharingService, ApiError } from "@/lib/sharing";
import { SpaceView } from "@/app/components/space/SpaceView";

type LoadError = "auth" | "notfound" | "error";

/**
 * Read-only viewer for a single space the logged-in user can access (#140).
 * The space is fetched API-authoritatively (it isn't in the visitor's local
 * storage); read-only vs editable is enforced server-side by #139, and a 404 is
 * deliberately existence-masked (no access and not-found look identical).
 */
export default function SpaceDetailPage() {
  const params = useParams<{ id: string }>();
  const id = typeof params?.id === "string" ? params.id : "";

  const [space, setSpace] = useState<Workspace | null>(null);
  const [error, setError] = useState<LoadError | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;
    setLoading(true);
    setError(null);
    SharingService.getSpace(id)
      .then((s) => {
        if (!active) return;
        setSpace(s);
        setLoading(false);
      })
      .catch((e: unknown) => {
        if (!active) return;
        if (e instanceof ApiError && e.status === 401) setError("auth");
        else if (e instanceof ApiError && e.status === 404)
          setError("notfound");
        else setError("error");
        setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [id]);

  if (loading) return <Centered>Loading space…</Centered>;
  if (error === "auth")
    return <Centered>Please log in to view this space.</Centered>;
  if (error === "notfound")
    return (
      <Centered>This space was not found, or you don’t have access.</Centered>
    );
  if (error || !space)
    return <Centered>Something went wrong loading this space.</Centered>;

  return <SpaceView space={space} />;
}

function Centered({ children }: { children: ReactNode }) {
  return (
    <div className="flex min-h-[50vh] items-center justify-center px-4 text-center text-sm text-gray-500">
      {children}
    </div>
  );
}
