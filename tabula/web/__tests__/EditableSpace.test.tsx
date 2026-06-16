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

import { render, screen, fireEvent, act } from "@testing-library/react";
import type { Workspace } from "@tabula/shared";
import { EditableSpace } from "@/app/components/space/EditableSpace";
import { SharingService, ApiError } from "@/lib/sharing";

jest.mock("@/lib/sharing", () => {
  class MockApiError extends Error {
    status: number;
    constructor(status: number, message: string) {
      super(message);
      this.name = "ApiError";
      this.status = status;
    }
  }
  return { ApiError: MockApiError, SharingService: { saveSpace: jest.fn() } };
});

const mockSave = SharingService.saveSpace as jest.Mock;

const space = (overrides: Partial<Workspace> = {}): Workspace => ({
  id: "ws_1",
  name: "Editable",
  version: 2,
  position: 0,
  tabs: [],
  resources: [],
  sections: [],
  notes: [{ id: "n1", title: "Note", content: "hi", updatedAt: 0 }],
  tasks: [{ id: "t1", title: "Task", completed: false, createdAt: 0 }],
  createdAt: 0,
  updatedAt: 0,
  ...overrides,
});

describe("EditableSpace", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.useFakeTimers();
  });
  afterEach(() => {
    jest.useRealTimers();
  });

  it("debounces a note edit into a save carrying the baseVersion", async () => {
    mockSave.mockResolvedValue({ ...space(), version: 3 });
    render(<EditableSpace space={space()} />);

    fireEvent.change(screen.getByLabelText("Edit note Note"), {
      target: { value: "edited" },
    });
    expect(mockSave).not.toHaveBeenCalled(); // still within the debounce window

    await act(async () => {
      await jest.advanceTimersByTimeAsync(700);
    });

    const [id, patch, base] = mockSave.mock.calls[0];
    expect(id).toBe("ws_1");
    expect(base).toBe(2);
    expect(patch.notes[0].content).toBe("edited");
    expect(screen.getByRole("status")).toHaveTextContent("Saved");
  });

  it("saves a task completion toggle", async () => {
    mockSave.mockResolvedValue({ ...space(), version: 3 });
    render(<EditableSpace space={space()} />);

    fireEvent.click(screen.getByLabelText("Task"));
    await act(async () => {
      await jest.advanceTimersByTimeAsync(700);
    });

    expect(mockSave.mock.calls[0][1].tasks[0].completed).toBe(true);
  });

  it("locks (no clobber) and prompts reload on a 409 conflict", async () => {
    mockSave.mockRejectedValue(new ApiError(409, "conflict"));
    render(<EditableSpace space={space()} />);

    fireEvent.change(screen.getByLabelText("Edit note Note"), {
      target: { value: "x" },
    });
    await act(async () => {
      await jest.advanceTimersByTimeAsync(700);
    });

    expect(screen.getByRole("status")).toHaveTextContent("Updated elsewhere");
    // Inputs disabled — further edits cannot clobber the other writer.
    expect(screen.getByLabelText("Edit note Note")).toBeDisabled();
  });

  it("surfaces view-only on a 403 and disables editing", async () => {
    mockSave.mockRejectedValue(new ApiError(403, "forbidden"));
    render(<EditableSpace space={space()} />);

    fireEvent.click(screen.getByLabelText("Task"));
    await act(async () => {
      await jest.advanceTimersByTimeAsync(700);
    });

    expect(screen.getByRole("status")).toHaveTextContent("view-only");
    expect(screen.getByLabelText("Task")).toBeDisabled();
  });
});
