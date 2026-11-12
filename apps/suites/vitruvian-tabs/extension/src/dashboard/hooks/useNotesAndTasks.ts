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
 * Custom hook for Notes and Tasks management in the Dashboard
 *
 * Handles CRUD operations for notes and tasks with optimistic updates.
 */

import { useState, useRef, useEffect } from "react";
import type { Workspace } from "../../types";
import { WorkspaceService } from "../../services/workspace";

const genId = (prefix: string) =>
  `${prefix}_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

/** Debounce window for persisting note edits (per keystroke would be O(n) writes) */
const NOTE_SAVE_DEBOUNCE_MS = 600;

export interface UseNotesAndTasksProps {
  activeWorkspace: Workspace | null;
  setActiveWorkspaceData: (ws: Workspace) => void;
}

export interface UseNotesAndTasksReturn {
  // Note state
  showAddNote: boolean;
  setShowAddNote: (show: boolean) => void;
  newNoteTitle: string;
  setNewNoteTitle: (title: string) => void;
  newNoteContent: string;
  setNewNoteContent: (content: string) => void;
  // Note handlers
  handleAddNote: () => Promise<void>;
  handleUpdateNote: (
    noteId: string,
    title: string,
    content: string,
  ) => Promise<void>;
  handleDeleteNote: (noteId: string) => Promise<void>;
  // Task state
  newTaskTitle: string;
  setNewTaskTitle: (title: string) => void;
  // Task handlers
  handleAddTask: () => Promise<void>;
  handleToggleTask: (taskId: string) => Promise<void>;
  handleDeleteTask: (taskId: string) => Promise<void>;
}

export const useNotesAndTasks = ({
  activeWorkspace,
  setActiveWorkspaceData,
}: UseNotesAndTasksProps): UseNotesAndTasksReturn => {
  // Note state
  const [showAddNote, setShowAddNote] = useState(false);
  const [newNoteTitle, setNewNoteTitle] = useState("");
  const [newNoteContent, setNewNoteContent] = useState("");

  // Task state
  const [newTaskTitle, setNewTaskTitle] = useState("");

  // Pending debounced note saves, keyed by noteId, so rapid typing collapses
  // into one persistence call instead of one per keystroke.
  const noteSaveTimers = useRef<Map<string, ReturnType<typeof setTimeout>>>(
    new Map(),
  );

  // Flush any pending note saves on unmount so no edits are lost
  useEffect(() => {
    const timers = noteSaveTimers.current;
    return () => {
      timers.forEach((timer) => clearTimeout(timer));
    };
  }, []);

  // Note handlers
  const handleAddNote = async () => {
    if (activeWorkspace && newNoteTitle) {
      // Generate the canonical id up front so the optimistic note, its update
      // routing, and any popout URL all reference the persisted id
      const id = genId("note");
      const newNote = {
        id,
        title: newNoteTitle,
        content: newNoteContent,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };

      const updatedNotes = [newNote, ...(activeWorkspace.notes || [])];
      setActiveWorkspaceData({ ...activeWorkspace, notes: updatedNotes });

      const updated = await WorkspaceService.addNote(activeWorkspace.id, {
        id,
        title: newNoteTitle,
        content: newNoteContent,
      });
      // Reconcile immediately rather than waiting for the storage echo
      setActiveWorkspaceData(updated);
      setShowAddNote(false);
      setNewNoteTitle("");
      setNewNoteContent("");
    }
  };

  const handleUpdateNote = async (
    noteId: string,
    title: string,
    content: string,
  ) => {
    if (activeWorkspace) {
      const workspaceId = activeWorkspace.id;
      // Optimistic update is immediate for a responsive editor
      const updatedNotes = (activeWorkspace.notes || []).map((note) =>
        note.id === noteId
          ? { ...note, title, content, updatedAt: Date.now() }
          : note,
      );
      setActiveWorkspaceData({ ...activeWorkspace, notes: updatedNotes });

      // Persistence is debounced per note: a typing burst becomes one write
      // (the whole-workspace storage write + queued PUT are O(workspace size))
      const timers = noteSaveTimers.current;
      const existing = timers.get(noteId);
      if (existing) clearTimeout(existing);
      timers.set(
        noteId,
        setTimeout(() => {
          timers.delete(noteId);
          WorkspaceService.updateNote(workspaceId, noteId, {
            title,
            content,
          }).catch((err) => {
            // eslint-disable-next-line no-console
            console.error("Failed to persist note edit:", err);
          });
        }, NOTE_SAVE_DEBOUNCE_MS),
      );
    }
  };

  const handleDeleteNote = async (noteId: string) => {
    if (activeWorkspace) {
      // Cancel any pending debounced save for this note (it's being deleted)
      const pending = noteSaveTimers.current.get(noteId);
      if (pending) {
        clearTimeout(pending);
        noteSaveTimers.current.delete(noteId);
      }
      // Optimistic update
      const updatedNotes = (activeWorkspace.notes || []).filter(
        (n) => n.id !== noteId,
      );
      setActiveWorkspaceData({ ...activeWorkspace, notes: updatedNotes });

      await WorkspaceService.deleteNote(activeWorkspace.id, noteId);
    }
  };

  // Task handlers
  const handleAddTask = async () => {
    if (activeWorkspace && newTaskTitle.trim()) {
      // Canonical id up front so the optimistic task matches the persisted one
      const id = genId("task");
      const newTask = {
        id,
        title: newTaskTitle,
        completed: false,
        createdAt: Date.now(),
      };

      const updatedTasks = [newTask, ...(activeWorkspace.tasks || [])];
      setActiveWorkspaceData({ ...activeWorkspace, tasks: updatedTasks });

      const updated = await WorkspaceService.addTask(
        activeWorkspace.id,
        newTaskTitle,
        id,
      );
      setActiveWorkspaceData(updated);
      setNewTaskTitle("");
    }
  };

  const handleToggleTask = async (taskId: string) => {
    if (activeWorkspace) {
      // Optimistic
      const updatedTasks = (activeWorkspace.tasks || []).map((t) =>
        t.id === taskId ? { ...t, completed: !t.completed } : t,
      );
      setActiveWorkspaceData({ ...activeWorkspace, tasks: updatedTasks });

      await WorkspaceService.toggleTask(activeWorkspace.id, taskId);
    }
  };

  const handleDeleteTask = async (taskId: string) => {
    if (activeWorkspace) {
      // Optimistic
      const updatedTasks = (activeWorkspace.tasks || []).filter(
        (t) => t.id !== taskId,
      );
      setActiveWorkspaceData({ ...activeWorkspace, tasks: updatedTasks });

      await WorkspaceService.deleteTask(activeWorkspace.id, taskId);
    }
  };

  return {
    // Note state
    showAddNote,
    setShowAddNote,
    newNoteTitle,
    setNewNoteTitle,
    newNoteContent,
    setNewNoteContent,
    // Note handlers
    handleAddNote,
    handleUpdateNote,
    handleDeleteNote,
    // Task state
    newTaskTitle,
    setNewTaskTitle,
    // Task handlers
    handleAddTask,
    handleToggleTask,
    handleDeleteTask,
  };
};
