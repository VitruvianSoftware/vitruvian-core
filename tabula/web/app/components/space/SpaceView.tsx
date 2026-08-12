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

import { useState, type ReactNode } from "react";
import type { Workspace, Resource, Note, Task } from "@tabula/shared";
import { safeHref } from "@/lib/safeHref";
import { Plate, Tabs, EmptyState } from "@vitruviansoftware/design-system";

type SpaceTab = "resources" | "notes" | "tasks";

/**
 * Read-only rendering of a shared space (resources, notes, tasks). Everything
 * here treats the space content as UNTRUSTED: resource URLs pass through
 * safeHref (a malicious owner could store a `javascript:` URL — see lib/safeHref)
 * and note bodies render as escaped React text (never dangerouslySetInnerHTML),
 * so a shared space can never execute script in the tabula.com origin.
 */
export function SpaceView({ space }: { space: Workspace }) {
  const [tab, setTab] = useState<SpaceTab>("resources");

  // Resources living directly on the space (no section) plus section resources.
  const looseResources = space.resources ?? [];
  const sections = space.sections ?? [];
  const notes = space.notes ?? [];
  const tasks = space.tasks ?? [];

  const resourceCount =
    looseResources.length +
    sections.reduce((n, s) => n + (s.resources?.length ?? 0), 0);

  const tabs: { key: SpaceTab; label: string; count: number }[] = [
    { key: "resources", label: "Resources", count: resourceCount },
    { key: "notes", label: "Notes", count: notes.length },
    { key: "tasks", label: "Tasks", count: tasks.length },
  ];

  return (
    <div className="mx-auto max-w-3xl px-4 py-8">
      <header className="mb-6">
        <h1 className="text-2xl font-semibold text-paper">{space.name}</h1>
        {space.description ? (
          <p className="mt-1 text-sm text-paper-dim">{space.description}</p>
        ) : null}
      </header>

      <div className="mb-6">
        <Tabs
          tabs={tabs.map((t) => ({
            id: t.key,
            label: (
              <>
                {t.label}
                <span className="ml-1.5 text-xs text-paper-dim">{t.count}</span>
              </>
            ),
          }))}
          active={tab}
          onChange={(id) => setTab(id as SpaceTab)}
        />
      </div>

      {tab === "resources" ? (
        <ResourcesPanel sections={sections} looseResources={looseResources} />
      ) : null}
      {tab === "notes" ? <NotesPanel notes={notes} /> : null}
      {tab === "tasks" ? <TasksPanel tasks={tasks} /> : null}
    </div>
  );
}

function ResourcesPanel({
  sections,
  looseResources,
}: {
  sections: Workspace["sections"];
  looseResources: Resource[];
}) {
  if (sections.length === 0 && looseResources.length === 0) {
    return <EmptyState title="No resources in this space yet." />;
  }
  return (
    <div className="space-y-6">
      {looseResources.length > 0 ? (
        <ResourceList resources={looseResources} />
      ) : null}
      {sections.map((section) => (
        <section key={section.id}>
          <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-paper-dim">
            {section.title}
          </h2>
          <ResourceList resources={section.resources ?? []} />
        </section>
      ))}
    </div>
  );
}

function ResourceList({ resources }: { resources: Resource[] }) {
  return (
    <ul className="space-y-1">
      {resources.map((r) => (
        <ResourceItem key={r.id} resource={r} />
      ))}
    </ul>
  );
}

function ResourceItem({ resource }: { resource: Resource }) {
  const href = safeHref(resource.url);
  return (
    <li className="px-3 py-2 hover:bg-ink-2">
      {href ? (
        <a
          href={href}
          target="_blank"
          rel="noopener noreferrer"
          className="block"
        >
          <span className="text-sm font-medium text-paper">
            {resource.title}
          </span>
          <span className="block truncate text-xs text-paper-dim">
            {resource.url}
          </span>
        </a>
      ) : (
        // Non-http(s) URL: render inert so a javascript:/data: URL cannot run.
        <div>
          <span className="text-sm font-medium text-paper">
            {resource.title}
          </span>
          <span className="block truncate text-xs text-paper-dim">
            {resource.url}
          </span>
        </div>
      )}
    </li>
  );
}

function NotesPanel({ notes }: { notes: Note[] }) {
  if (notes.length === 0) {
    return <EmptyState title="No notes in this space yet." />;
  }
  return (
    <div className="space-y-4">
      {notes.map((note) => (
        <Plate as="article" key={note.id} className="p-4">
          <h3 className="mb-1 text-sm font-semibold text-paper">
            {note.title}
          </h3>
          {/* Escaped React text node — never dangerouslySetInnerHTML. */}
          <p className="whitespace-pre-wrap text-sm text-paper-dim">
            {note.content}
          </p>
        </Plate>
      ))}
    </div>
  );
}

function TasksPanel({ tasks }: { tasks: Task[] }) {
  if (tasks.length === 0) {
    return <EmptyState title="No tasks in this space yet." />;
  }
  return (
    <ul className="space-y-1">
      {tasks.map((task) => (
        <li key={task.id} className="flex items-center gap-2 px-1 py-1.5">
          <input
            type="checkbox"
            checked={task.completed}
            disabled
            readOnly
            aria-label={task.title}
          />
          <span
            className={`text-sm ${
              task.completed ? "text-paper-dim line-through" : "text-paper"
            }`}
          >
            {task.title}
          </span>
        </li>
      ))}
    </ul>
  );
}
