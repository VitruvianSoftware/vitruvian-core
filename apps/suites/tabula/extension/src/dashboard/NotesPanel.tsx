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

import React from "react";
import type { Note } from "../types";
import { NoteEditor } from "../components/NoteEditor";
import {
  Button,
  Input,
  EmptyState as DesignEmptyState,
} from "@vitruviansoftware/design-system";
import { useFeatureFlag } from "../lib/flags/use-feature-flag";
import { FEATURE_FLAGS } from "../constants/features";

export interface NotesPanelProps {
  notes: Note[];
  /** Workspace these notes belong to — pins the popout window to it */
  workspaceId?: string;
  showAddNote: boolean;
  newNoteTitle: string;
  newNoteContent: string;
  onShowAddNote: () => void;
  onCancelAddNote: () => void;
  onAddNote: () => void;
  onUpdateNote: (noteId: string, title: string, content: string) => void;
  onDeleteNote: (noteId: string) => void;
  onNewNoteTitleChange: (value: string) => void;
  onNewNoteContentChange: (value: string) => void;
}

export const NotesPanel: React.FC<NotesPanelProps> = ({
  notes,
  workspaceId,
  showAddNote,
  newNoteTitle,
  newNoteContent,
  onShowAddNote,
  onCancelAddNote,
  onAddNote,
  onUpdateNote,
  onDeleteNote,
  onNewNoteTitleChange,
  onNewNoteContentChange,
}) => {
  const useDesignSystem = useFeatureFlag(
    FEATURE_FLAGS.USE_DESIGN_SYSTEM,
    false,
  );

  const handlePopout = (note: Note) => {
    // Open dashboard in new window with note focus, pinned to THIS workspace.
    // Without spaceId the popout follows the shared active workspace and
    // breaks (or edits the wrong note) when the main window switches.
    const spaceParam = workspaceId
      ? `&spaceId=${encodeURIComponent(workspaceId)}`
      : "";
    const url = chrome.runtime.getURL(
      `dashboard.html?view=note&noteId=${note.id}${spaceParam}`,
    );
    chrome.windows.create({
      url,
      type: "popup",
      width: 600,
      height: 800,
    });
  };

  return (
    <>
      <div className="section-header">
        {useDesignSystem ? (
          <Button variant="solid" size="sm" onClick={onShowAddNote}>
            + New Note
          </Button>
        ) : (
          <button className="btn btn-sm btn-secondary" onClick={onShowAddNote}>
            + New Note
          </button>
        )}
      </div>

      {showAddNote &&
        (useDesignSystem ? (
          <div
            style={{
              backgroundColor: "var(--color-bg-card)",
              border: "1px solid var(--color-border)",
              borderRadius: "0",
              padding: "16px",
              marginBottom: "16px",
            }}
          >
            <div style={{ marginBottom: "12px" }}>
              <Input
                placeholder="Note Title"
                value={newNoteTitle}
                onChange={(e: React.ChangeEvent<HTMLInputElement>) =>
                  onNewNoteTitleChange(e.target.value)
                }
                autoFocus
              />
            </div>
            <div style={{ marginBottom: "16px" }}>
              <NoteEditor
                value={newNoteContent}
                onChange={onNewNoteContentChange}
                placeholder="Type something..."
                minRows={5}
              />
            </div>
            <div
              style={{
                display: "flex",
                gap: "8px",
                justifyContent: "flex-end",
              }}
            >
              <Button variant="ghost" size="sm" onClick={onCancelAddNote}>
                Cancel
              </Button>
              <Button
                variant="solid"
                size="sm"
                onClick={onAddNote}
                disabled={!newNoteTitle}
              >
                Save
              </Button>
            </div>
          </div>
        ) : (
          <div className="note-card editing">
            <input
              className="input note-title-input"
              placeholder="Note Title"
              value={newNoteTitle}
              onChange={(e) => onNewNoteTitleChange(e.target.value)}
              autoFocus
            />
            <div style={{ marginBottom: "16px" }}>
              <NoteEditor
                value={newNoteContent}
                onChange={onNewNoteContentChange}
                placeholder="Type something..."
                minRows={5}
              />
            </div>
            <div className="flex gap-sm justify-end">
              <button
                className="btn btn-sm btn-secondary"
                onClick={onCancelAddNote}
              >
                Cancel
              </button>
              <button
                className="btn btn-sm btn-primary"
                onClick={onAddNote}
                disabled={!newNoteTitle}
              >
                Save
              </button>
            </div>
          </div>
        ))}

      <div className="notes-list">
        {notes.length === 0 &&
          !showAddNote &&
          (useDesignSystem ? (
            <DesignEmptyState title="No notes yet.">
              Create one to keep track of ideas.
            </DesignEmptyState>
          ) : (
            <div className="empty-state">
              No notes yet. Create one to keep track of ideas.
            </div>
          ))}
        {notes.map((note) =>
          useDesignSystem ? (
            <div
              key={note.id}
              className="note-card"
              style={{
                backgroundColor: "var(--color-bg-card)",
                border: "1px solid var(--color-border)",
                borderRadius: "0",
                padding: "12px 16px",
                marginBottom: "12px",
              }}
            >
              <div
                className="note-header"
                style={{
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "space-between",
                  marginBottom: "8px",
                }}
              >
                <input
                  className="note-title-display"
                  style={{
                    fontFamily: "var(--font-mono, monospace)",
                    fontWeight: 600,
                    fontSize: "14px",
                    color: "var(--color-text-primary)",
                    border: "none",
                    background: "transparent",
                    outline: "none",
                    flex: 1,
                  }}
                  value={note.title}
                  onChange={(e) =>
                    onUpdateNote(note.id, e.target.value, note.content)
                  }
                />
                <button
                  className="btn-icon danger"
                  style={{
                    background: "none",
                    border: "none",
                    color: "var(--color-accent-danger)",
                    cursor: "pointer",
                    fontSize: "16px",
                    padding: "0 4px",
                  }}
                  onClick={() => onDeleteNote(note.id)}
                  title="Delete note"
                >
                  ×
                </button>
              </div>
              <NoteEditor
                value={note.content}
                onChange={(value) => onUpdateNote(note.id, note.title, value)}
                minRows={Math.max(3, note.content.split("\n").length)}
                onPopout={() => handlePopout(note)}
              />
            </div>
          ) : (
            <div key={note.id} className="note-card">
              <div className="note-header">
                <input
                  className="note-title-display"
                  value={note.title}
                  onChange={(e) =>
                    onUpdateNote(note.id, e.target.value, note.content)
                  }
                />
                <button
                  className="btn-icon danger"
                  onClick={() => onDeleteNote(note.id)}
                >
                  ×
                </button>
              </div>
              <NoteEditor
                value={note.content}
                onChange={(value) => onUpdateNote(note.id, note.title, value)}
                minRows={Math.max(3, note.content.split("\n").length)}
                onPopout={() => handlePopout(note)}
              />
            </div>
          ),
        )}
      </div>
    </>
  );
};
