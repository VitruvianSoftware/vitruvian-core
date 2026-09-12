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
 * Tests for TasksPanel component
 *
 * Tests the tasks tab UI including add task input, task list, and callbacks.
 */

import { render, screen, fireEvent } from "@testing-library/react";
import "@testing-library/jest-dom";
import { useFeatureFlag } from "../lib/flags/use-feature-flag";
import { TasksPanel } from "./TasksPanel";
import type { Task } from "../types";

jest.mock("../lib/flags/use-feature-flag", () => ({
  useFeatureFlag: jest.fn(() => false),
}));

describe("TasksPanel", () => {
  const now = Date.now();
  const mockTasks: Task[] = [
    { id: "1", title: "First Task", completed: false, createdAt: now },
    { id: "2", title: "Second Task", completed: true, createdAt: now },
  ];

  const defaultProps = {
    tasks: mockTasks,
    newTaskTitle: "",
    onNewTaskTitleChange: jest.fn(),
    onAddTask: jest.fn(),
    onToggleTask: jest.fn(),
    onDeleteTask: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
    (useFeatureFlag as unknown as jest.Mock).mockReturnValue(false);
  });

  describe("rendering", () => {
    it("should render the add task input", () => {
      render(<TasksPanel {...defaultProps} />);
      expect(
        screen.getByPlaceholderText("Add a new task..."),
      ).toBeInTheDocument();
    });

    it("should render all tasks", () => {
      render(<TasksPanel {...defaultProps} />);
      expect(screen.getByText("First Task")).toBeInTheDocument();
      expect(screen.getByText("Second Task")).toBeInTheDocument();
    });

    it("should show empty state when no tasks", () => {
      render(<TasksPanel {...defaultProps} tasks={[]} />);
      expect(
        screen.getByText("No tasks yet. Stay organized by adding tasks here."),
      ).toBeInTheDocument();
    });

    it("should show completed task with strikethrough style", () => {
      render(<TasksPanel {...defaultProps} />);
      const completedTask = screen.getByText("Second Task");
      expect(completedTask).toHaveStyle({ textDecoration: "line-through" });
    });

    it("should show incomplete task without strikethrough", () => {
      render(<TasksPanel {...defaultProps} />);
      const incompleteTask = screen.getByText("First Task");
      expect(incompleteTask).toHaveStyle({ textDecoration: "none" });
    });
  });

  describe("adding tasks", () => {
    it("should call onNewTaskTitleChange when input changes", () => {
      render(<TasksPanel {...defaultProps} />);
      fireEvent.change(screen.getByPlaceholderText("Add a new task..."), {
        target: { value: "New Task" },
      });
      expect(defaultProps.onNewTaskTitleChange).toHaveBeenCalledWith(
        "New Task",
      );
    });

    it("should call onAddTask when Enter key pressed", () => {
      render(<TasksPanel {...defaultProps} />);
      fireEvent.keyDown(screen.getByPlaceholderText("Add a new task..."), {
        key: "Enter",
      });
      expect(defaultProps.onAddTask).toHaveBeenCalled();
    });

    it("should not call onAddTask for other keys", () => {
      render(<TasksPanel {...defaultProps} />);
      fireEvent.keyDown(screen.getByPlaceholderText("Add a new task..."), {
        key: "a",
      });
      expect(defaultProps.onAddTask).not.toHaveBeenCalled();
    });
  });

  describe("task interactions", () => {
    it("should render checkboxes for each task", () => {
      render(<TasksPanel {...defaultProps} />);
      const checkboxes = screen.getAllByRole("checkbox");
      expect(checkboxes).toHaveLength(2);
    });

    it("should have checked checkbox for completed task", () => {
      render(<TasksPanel {...defaultProps} />);
      const checkboxes = screen.getAllByRole("checkbox");
      expect(checkboxes[1]).toBeChecked();
    });

    it("should have unchecked checkbox for incomplete task", () => {
      render(<TasksPanel {...defaultProps} />);
      const checkboxes = screen.getAllByRole("checkbox");
      expect(checkboxes[0]).not.toBeChecked();
    });

    it("should call onToggleTask when checkbox clicked", () => {
      render(<TasksPanel {...defaultProps} />);
      const checkboxes = screen.getAllByRole("checkbox");
      fireEvent.click(checkboxes[0]);
      expect(defaultProps.onToggleTask).toHaveBeenCalledWith("1");
    });

    it("should call onDeleteTask when delete button clicked", () => {
      render(<TasksPanel {...defaultProps} />);
      const deleteButtons = screen.getAllByText("×");
      fireEvent.click(deleteButtons[0]);
      expect(defaultProps.onDeleteTask).toHaveBeenCalledWith("1");
    });
  });

  describe("when design system is enabled", () => {
    beforeEach(() => {
      (useFeatureFlag as unknown as jest.Mock).mockReturnValue(true);
    });

    it("should render tasks input and task list with design system styling", () => {
      render(<TasksPanel {...defaultProps} />);
      expect(
        screen.getByPlaceholderText("Add a new task..."),
      ).toBeInTheDocument();
      expect(screen.getByText("First Task")).toBeInTheDocument();
      expect(screen.getByText("Second Task")).toBeInTheDocument();
    });
  });
});
