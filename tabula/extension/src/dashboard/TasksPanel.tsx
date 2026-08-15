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
import { Input } from "@vitruviansoftware/design-system";
import { useFeatureFlag } from "../lib/flags/use-feature-flag";
import { FEATURE_FLAGS } from "../constants/features";

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
  const useDesignSystem = useFeatureFlag(
    FEATURE_FLAGS.USE_DESIGN_SYSTEM,
    false,
  );

  return (
    <>
      <div className="section-header">
        {useDesignSystem ? (
          <div style={{ width: "100%" }}>
            <Input
              placeholder="Add a new task..."
              value={newTaskTitle}
              onChange={(e: React.ChangeEvent<HTMLInputElement>) =>
                onNewTaskTitleChange(e.target.value)
              }
              onKeyDown={(e: React.KeyboardEvent<HTMLInputElement>) => {
                if (e.key === "Enter") {
                  onAddTask();
                }
              }}
            />
          </div>
        ) : (
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
        )}
      </div>

      <div className="tasks-list" style={{ marginTop: "16px" }}>
        {tasks.length === 0 && (
          <div
            className="empty-state"
            style={
              useDesignSystem
                ? {
                    fontFamily: "var(--font-mono, monospace)",
                    fontSize: "12px",
                    color: "var(--paper-dim, #736d64)",
                  }
                : undefined
            }
          >
            No tasks yet. Stay organized by adding tasks here.
          </div>
        )}

        {tasks.map((task) =>
          useDesignSystem ? (
            <div
              key={task.id}
              style={{
                display: "flex",
                alignItems: "center",
                padding: "8px 12px",
                marginBottom: "4px",
                backgroundColor: "var(--paper, #fbf7ee)",
                border: "1px solid var(--border-hairline, rgba(0,0,0,0.1))",
              }}
            >
              <input
                type="checkbox"
                checked={task.completed}
                onChange={() => onToggleTask(task.id)}
                style={{ marginRight: "12px", cursor: "pointer" }}
              />
              <div
                style={{
                  flex: 1,
                  textDecoration: task.completed ? "line-through" : "none",
                  color: task.completed
                    ? "var(--paper-dim, #736d64)"
                    : "var(--ink, #1f1d1a)",
                  fontSize: "13px",
                }}
              >
                {task.title}
              </div>
              <button
                style={{
                  background: "none",
                  border: "none",
                  color: "var(--accent, #991b1b)",
                  cursor: "pointer",
                  fontSize: "16px",
                  padding: "0 4px",
                }}
                onClick={() => onDeleteTask(task.id)}
                title="Delete task"
              >
                ×
              </button>
            </div>
          ) : (
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
          ),
        )}
      </div>
    </>
  );
};
