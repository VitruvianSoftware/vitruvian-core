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

import { useRef, useState } from "react";
import type { Workspace } from "@tabula/shared";
import { SharingService, ApiError } from "@/lib/sharing";

type SaveStatus =
  "idle" | "saving" | "saved" | "conflict" | "forbidden" | "error";

const DEBOUNCE_MS = 700;

/**
 * Editable view of a shared space for an EDIT collaborator (#140). Save-on-change
 * with optimistic concurrency — NOT real-time co-edit (that is M4). Notes and
 * task completion are editable; each change debounces a PUT carrying the last
 * known `baseVersion`. The server (#139) is the real gate: a VIEW collaborator
 * who reaches this anyway gets a 403 and the editor locks. A 409 means someone
 * else changed the space, so editing locks rather than clobbering — the user
 * reloads to continue.
 */
export function EditableSpace({ space: initial }: { space: Workspace }) {
  const [space, setSpace] = useState<Workspace>(initial);
  const [status, setStatus] = useState<SaveStatus>("idle");
  const baseVersion = useRef<number | undefined>(initial.version);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  // A conflict or a permission denial stops further auto-saving until reload.
  const locked = status === "conflict" || status === "forbidden";

  function scheduleSave(next: Workspace) {
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => {
      void persist(next);
    }, DEBOUNCE_MS);
  }

  async function persist(next: Workspace) {
    setStatus("saving");
    try {
      const saved = await SharingService.saveSpace(
        space.id,
        { notes: next.notes, tasks: next.tasks },
        baseVersion.current,
      );
      baseVersion.current = saved.version;
      setStatus("saved");
    } catch (e) {
      if (e instanceof ApiError && e.status === 409) setStatus("conflict");
      else if (e instanceof ApiError && e.status === 403)
        setStatus("forbidden");
      else setStatus("error");
    }
  }

  function editNote(id: string, content: string) {
    const next = {
      ...space,
      notes: space.notes.map((n) => (n.id === id ? { ...n, content } : n)),
    };
    setSpace(next);
    if (!locked) scheduleSave(next);
  }

  function toggleTask(id: string) {
    const next = {
      ...space,
      tasks: space.tasks.map((t) =>
        t.id === id ? { ...t, completed: !t.completed } : t,
      ),
    };
    setSpace(next);
    if (!locked) scheduleSave(next);
  }

  return (
    <div className="mx-auto max-w-3xl px-4 py-8">
      <header className="mb-4 flex items-center justify-between">
        <h1 className="text-2xl font-semibold text-gray-900 dark:text-gray-100">
          {space.name}
        </h1>
        <StatusPill status={status} />
      </header>

      <section className="mb-8">
        <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-gray-500">
          Notes
        </h2>
        {space.notes.length === 0 ? (
          <p className="text-sm text-gray-400">No notes.</p>
        ) : (
          <div className="space-y-4">
            {space.notes.map((note) => (
              <div
                key={note.id}
                className="rounded-lg border border-gray-200 p-3 dark:border-gray-700"
              >
                <div className="mb-1 text-sm font-semibold text-gray-900 dark:text-gray-100">
                  {note.title}
                </div>
                <textarea
                  aria-label={`Edit note ${note.title}`}
                  value={note.content}
                  disabled={locked}
                  onChange={(e) => editNote(note.id, e.target.value)}
                  className="w-full resize-y rounded border border-gray-200 p-2 text-sm dark:border-gray-700 dark:bg-gray-900"
                  rows={3}
                />
              </div>
            ))}
          </div>
        )}
      </section>

      <section>
        <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-gray-500">
          Tasks
        </h2>
        {space.tasks.length === 0 ? (
          <p className="text-sm text-gray-400">No tasks.</p>
        ) : (
          <ul className="space-y-1">
            {space.tasks.map((task) => (
              <li key={task.id} className="flex items-center gap-2 px-1 py-1.5">
                <input
                  type="checkbox"
                  checked={task.completed}
                  disabled={locked}
                  onChange={() => toggleTask(task.id)}
                  aria-label={task.title}
                />
                <span
                  className={`text-sm ${
                    task.completed
                      ? "text-gray-400 line-through"
                      : "text-gray-900 dark:text-gray-100"
                  }`}
                >
                  {task.title}
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}

function StatusPill({ status }: { status: SaveStatus }) {
  const text: Record<SaveStatus, string | null> = {
    idle: null,
    saving: "Saving…",
    saved: "Saved",
    conflict: "Updated elsewhere — reload to keep editing",
    forbidden: "You have view-only access",
    error: "Save failed — retry",
  };
  const label = text[status];
  if (!label) return null;
  const tone =
    status === "saved"
      ? "text-green-600"
      : status === "saving"
        ? "text-gray-400"
        : "text-amber-600";
  return (
    <span className={`text-xs font-medium ${tone}`} role="status">
      {label}
    </span>
  );
}
