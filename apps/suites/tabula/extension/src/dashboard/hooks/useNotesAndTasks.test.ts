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

/* eslint-disable @typescript-eslint/no-explicit-any */
/* eslint-disable no-console */
import { renderHook, act } from "@testing-library/react";
import { useNotesAndTasks } from "./useNotesAndTasks";
import { WorkspaceService } from "../../services/workspace";
import { Workspace } from "../../types";

// Mock workspace service
jest.mock("../../services/workspace");

describe("useNotesAndTasks", () => {
  const mockSetActiveWorkspaceData = jest.fn();
  const mockWorkspace: Workspace = {
    id: "ws1",
    name: "Test Workspace",
    tabs: [],
    resources: [],
    sections: [],
    notes: [
      { id: "note1", title: "Note 1", content: "Content 1", updatedAt: 0 },
    ],
    tasks: [{ id: "task1", title: "Task 1", completed: false, createdAt: 0 }],
    position: 0,
    createdAt: Date.now(),
    updatedAt: Date.now(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("Notes", () => {
    it("should add a note", async () => {
      (WorkspaceService.addNote as jest.Mock).mockResolvedValue({
        ...mockWorkspace,
        notes: [
          ...mockWorkspace.notes,
          { id: "new", title: "New", content: "Context", updatedAt: 0 },
        ],
      });

      const { result } = renderHook(() =>
        useNotesAndTasks({
          activeWorkspace: mockWorkspace,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
        }),
      );

      // Set input values
      act(() => {
        result.current.setNewNoteTitle("New Note");
        result.current.setNewNoteContent("Context");
      });

      await act(async () => {
        await result.current.handleAddNote();
      });

      expect(WorkspaceService.addNote).toHaveBeenCalledWith(
        "ws1",
        expect.objectContaining({ title: "New Note", content: "Context" }),
      );
      expect(result.current.showAddNote).toBe(false);
      expect(result.current.newNoteTitle).toBe("");
    });

    it("should update a note (debounced persistence)", async () => {
      jest.useFakeTimers();
      (WorkspaceService.updateNote as jest.Mock).mockResolvedValue(true);

      const { result } = renderHook(() =>
        useNotesAndTasks({
          activeWorkspace: mockWorkspace,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
        }),
      );

      act(() => {
        result.current.handleUpdateNote("note1", "Updated", "Content");
      });

      // Optimistic UI update is immediate; persistence is debounced
      expect(mockSetActiveWorkspaceData).toHaveBeenCalled();
      expect(WorkspaceService.updateNote).not.toHaveBeenCalled();

      await act(async () => {
        jest.advanceTimersByTime(700);
      });

      expect(WorkspaceService.updateNote).toHaveBeenCalledWith("ws1", "note1", {
        title: "Updated",
        content: "Content",
      });
      jest.useRealTimers();
    });

    it("coalesces rapid edits to the same note into one persistence call", async () => {
      jest.useFakeTimers();
      (WorkspaceService.updateNote as jest.Mock).mockResolvedValue(true);

      const { result } = renderHook(() =>
        useNotesAndTasks({
          activeWorkspace: mockWorkspace,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
        }),
      );

      act(() => {
        result.current.handleUpdateNote("note1", "A", "a");
        result.current.handleUpdateNote("note1", "AB", "ab");
        result.current.handleUpdateNote("note1", "ABC", "abc");
      });

      await act(async () => {
        jest.advanceTimersByTime(700);
      });

      expect(WorkspaceService.updateNote).toHaveBeenCalledTimes(1);
      expect(WorkspaceService.updateNote).toHaveBeenCalledWith("ws1", "note1", {
        title: "ABC",
        content: "abc",
      });
      jest.useRealTimers();
    });

    it("should delete a note", async () => {
      const { result } = renderHook(() =>
        useNotesAndTasks({
          activeWorkspace: mockWorkspace,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
        }),
      );

      await act(async () => {
        await result.current.handleDeleteNote("note1");
      });

      expect(WorkspaceService.deleteNote).toHaveBeenCalledWith("ws1", "note1");
    });
  });

  describe("Tasks", () => {
    it("should add a task", async () => {
      (WorkspaceService.addTask as jest.Mock).mockResolvedValue({
        ...mockWorkspace,
        tasks: [
          ...mockWorkspace.tasks,
          { id: "new", title: "New Task", completed: false, createdAt: 0 },
        ],
      });

      const { result } = renderHook(() =>
        useNotesAndTasks({
          activeWorkspace: mockWorkspace,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
        }),
      );

      act(() => {
        result.current.setNewTaskTitle("New Task");
      });

      await act(async () => {
        await result.current.handleAddTask();
      });

      expect(WorkspaceService.addTask).toHaveBeenCalledWith(
        "ws1",
        "New Task",
        expect.any(String),
      );
      expect(result.current.newTaskTitle).toBe("");
    });

    it("should toggle a task", async () => {
      (WorkspaceService.toggleTask as jest.Mock).mockResolvedValue(true);

      const { result } = renderHook(() =>
        useNotesAndTasks({
          activeWorkspace: mockWorkspace,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
        }),
      );

      await act(async () => {
        await result.current.handleToggleTask("task1");
      });

      expect(WorkspaceService.toggleTask).toHaveBeenCalledWith("ws1", "task1");
    });

    it("should delete a task", async () => {
      (WorkspaceService.deleteTask as jest.Mock).mockResolvedValue(undefined);

      const { result } = renderHook(() =>
        useNotesAndTasks({
          activeWorkspace: mockWorkspace,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
        }),
      );

      await act(async () => {
        await result.current.handleDeleteTask("task1");
      });

      expect(WorkspaceService.deleteTask).toHaveBeenCalledWith("ws1", "task1");
    });

    it("should NOT add task without title", async () => {
      const { result } = renderHook(() =>
        useNotesAndTasks({
          activeWorkspace: mockWorkspace,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
        }),
      );

      // Leave title empty
      await act(async () => {
        await result.current.handleAddTask();
      });

      expect(WorkspaceService.addTask).not.toHaveBeenCalled();
    });

    it("should NOT add task with whitespace-only title", async () => {
      const { result } = renderHook(() =>
        useNotesAndTasks({
          activeWorkspace: mockWorkspace,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
        }),
      );

      act(() => {
        result.current.setNewTaskTitle("   ");
      });

      await act(async () => {
        await result.current.handleAddTask();
      });

      expect(WorkspaceService.addTask).not.toHaveBeenCalled();
    });
  });

  describe("Null workspace handling", () => {
    it("should NOT add note without active workspace", async () => {
      const { result } = renderHook(() =>
        useNotesAndTasks({
          activeWorkspace: null,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
        }),
      );

      act(() => {
        result.current.setNewNoteTitle("Test");
      });

      await act(async () => {
        await result.current.handleAddNote();
      });

      expect(WorkspaceService.addNote).not.toHaveBeenCalled();
    });

    it("should NOT update note without active workspace", async () => {
      const { result } = renderHook(() =>
        useNotesAndTasks({
          activeWorkspace: null,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
        }),
      );

      await act(async () => {
        await result.current.handleUpdateNote("note1", "Title", "Content");
      });

      expect(WorkspaceService.updateNote).not.toHaveBeenCalled();
    });

    it("should NOT delete note without active workspace", async () => {
      const { result } = renderHook(() =>
        useNotesAndTasks({
          activeWorkspace: null,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
        }),
      );

      await act(async () => {
        await result.current.handleDeleteNote("note1");
      });

      expect(WorkspaceService.deleteNote).not.toHaveBeenCalled();
    });

    it("should NOT add task without active workspace", async () => {
      const { result } = renderHook(() =>
        useNotesAndTasks({
          activeWorkspace: null,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
        }),
      );

      act(() => {
        result.current.setNewTaskTitle("Test Task");
      });

      await act(async () => {
        await result.current.handleAddTask();
      });

      expect(WorkspaceService.addTask).not.toHaveBeenCalled();
    });

    it("should NOT toggle task without active workspace", async () => {
      const { result } = renderHook(() =>
        useNotesAndTasks({
          activeWorkspace: null,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
        }),
      );

      await act(async () => {
        await result.current.handleToggleTask("task1");
      });

      expect(WorkspaceService.toggleTask).not.toHaveBeenCalled();
    });

    it("should NOT delete task without active workspace", async () => {
      const { result } = renderHook(() =>
        useNotesAndTasks({
          activeWorkspace: null,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
        }),
      );

      await act(async () => {
        await result.current.handleDeleteTask("task1");
      });

      expect(WorkspaceService.deleteTask).not.toHaveBeenCalled();
    });
  });

  describe("Empty notes/tasks arrays", () => {
    it("should handle workspace with undefined notes array", async () => {
      const workspaceWithoutNotes: Workspace = {
        ...mockWorkspace,
        notes: undefined as any,
      };

      (WorkspaceService.addNote as jest.Mock).mockResolvedValue(undefined);

      const { result } = renderHook(() =>
        useNotesAndTasks({
          activeWorkspace: workspaceWithoutNotes,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
        }),
      );

      act(() => {
        result.current.setNewNoteTitle("New Note");
      });

      await act(async () => {
        await result.current.handleAddNote();
      });

      expect(WorkspaceService.addNote).toHaveBeenCalled();
    });

    it("should handle workspace with undefined tasks array", async () => {
      const workspaceWithoutTasks: Workspace = {
        ...mockWorkspace,
        tasks: undefined as any,
      };

      (WorkspaceService.addTask as jest.Mock).mockResolvedValue(undefined);

      const { result } = renderHook(() =>
        useNotesAndTasks({
          activeWorkspace: workspaceWithoutTasks,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
        }),
      );

      act(() => {
        result.current.setNewTaskTitle("New Task");
      });

      await act(async () => {
        await result.current.handleAddTask();
      });

      expect(WorkspaceService.addTask).toHaveBeenCalled();
    });
  });

  describe("Note without title", () => {
    it("should NOT add note without title", async () => {
      const { result } = renderHook(() =>
        useNotesAndTasks({
          activeWorkspace: mockWorkspace,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
        }),
      );

      // Leave title empty
      await act(async () => {
        await result.current.handleAddNote();
      });

      expect(WorkspaceService.addNote).not.toHaveBeenCalled();
    });
  });

  describe("Workspace with undefined notes and tasks", () => {
    it("should handle update note when notes array is undefined", async () => {
      const workspaceWithoutNotes: Workspace = {
        id: "ws1",
        name: "Test",
        tabs: [],
        resources: [],
        sections: [],
        notes: undefined as any,
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };

      jest.useFakeTimers();
      (WorkspaceService.updateNote as jest.Mock).mockResolvedValue(undefined);

      const { result } = renderHook(() =>
        useNotesAndTasks({
          activeWorkspace: workspaceWithoutNotes,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
        }),
      );

      act(() => {
        result.current.handleUpdateNote("note1", "New Title", "New Content");
      });
      await act(async () => {
        jest.advanceTimersByTime(700);
      });

      expect(WorkspaceService.updateNote).toHaveBeenCalled();
      jest.useRealTimers();
    });

    it("should handle delete note when notes array is undefined", async () => {
      const workspaceWithoutNotes: Workspace = {
        id: "ws1",
        name: "Test",
        tabs: [],
        resources: [],
        sections: [],
        notes: undefined as any,
        tasks: [],
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };

      (WorkspaceService.deleteNote as jest.Mock).mockResolvedValue(undefined);

      const { result } = renderHook(() =>
        useNotesAndTasks({
          activeWorkspace: workspaceWithoutNotes,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
        }),
      );

      await act(async () => {
        await result.current.handleDeleteNote("note1");
      });

      expect(WorkspaceService.deleteNote).toHaveBeenCalled();
    });

    it("should handle toggle task when tasks array is undefined", async () => {
      const workspaceWithoutTasks: Workspace = {
        id: "ws1",
        name: "Test",
        tabs: [],
        resources: [],
        sections: [],
        notes: [],
        tasks: undefined as any,
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };

      (WorkspaceService.toggleTask as jest.Mock).mockResolvedValue(undefined);

      const { result } = renderHook(() =>
        useNotesAndTasks({
          activeWorkspace: workspaceWithoutTasks,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
        }),
      );

      await act(async () => {
        await result.current.handleToggleTask("task1");
      });

      expect(WorkspaceService.toggleTask).toHaveBeenCalled();
    });

    it("should handle delete task when tasks array is undefined", async () => {
      const workspaceWithoutTasks: Workspace = {
        id: "ws1",
        name: "Test",
        tabs: [],
        resources: [],
        sections: [],
        notes: [],
        tasks: undefined as any,
        position: 0,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };

      (WorkspaceService.deleteTask as jest.Mock).mockResolvedValue(undefined);

      const { result } = renderHook(() =>
        useNotesAndTasks({
          activeWorkspace: workspaceWithoutTasks,
          setActiveWorkspaceData: mockSetActiveWorkspaceData,
        }),
      );

      await act(async () => {
        await result.current.handleDeleteTask("task1");
      });

      expect(WorkspaceService.deleteTask).toHaveBeenCalled();
    });
  });
});
