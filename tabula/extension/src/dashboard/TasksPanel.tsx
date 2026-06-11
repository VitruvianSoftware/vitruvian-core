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
import type { Task } from "../types";

export interface TasksPanelProps {
  tasks: Task[];
  newTaskTitle: string;
  onNewTaskTitleChange: (value: string) => void;
  onAddTask: () => void;
  onToggleTask: (taskId: string) => void;
  onDeleteTask: (taskId: string) => void;
}

export const TasksPanel: React.FC<TasksPanelProps> = ({
  tasks,
  newTaskTitle,
  onNewTaskTitleChange,
  onAddTask,
  onToggleTask,
  onDeleteTask,
}) => {
  return (
    <>
      <div className="section-header">
        <input
          className="input"
          style={{ width: "100%" }}
          placeholder="Add a new task..."
          value={newTaskTitle}
          onChange={(e) => onNewTaskTitleChange(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              onAddTask();
            }
          }}
        />
      </div>

      <div className="tasks-list" style={{ marginTop: "16px" }}>
        {tasks.length === 0 && (
          <div className="empty-state">
            No tasks yet. Stay organized by adding tasks here.
          </div>
        )}

        {tasks.map((task) => (
          <div
            key={task.id}
            className="list-item"
            style={{ alignItems: "center" }}
          >
            <input
              type="checkbox"
              checked={task.completed}
              onChange={() => onToggleTask(task.id)}
              style={{ marginRight: "12px" }}
            />
            <div
              style={{
                flex: 1,
                textDecoration: task.completed ? "line-through" : "none",
                color: task.completed ? "#999" : "inherit",
              }}
            >
              {task.title}
            </div>
            <button
              className="btn-icon danger"
              style={{ opacity: 0.5 }}
              onClick={() => onDeleteTask(task.id)}
            >
              ×
            </button>
          </div>
        ))}
      </div>
    </>
  );
};
