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
        <button className="btn btn-sm btn-secondary" onClick={onShowAddNote}>
          + New Note
        </button>
      </div>

      {showAddNote && (
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
      )}

      <div className="notes-list">
        {notes.length === 0 && !showAddNote && (
          <div className="empty-state">
            No notes yet. Create one to keep track of ideas.
          </div>
        )}
        {notes.map((note) => (
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
        ))}
      </div>
    </>
  );
};
