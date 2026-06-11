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
 * Tests for NotesPanel component
 *
 * Tests the notes tab UI including add note form, notes list, and callbacks.
 */

import { render, screen, fireEvent } from "@testing-library/react";
import "@testing-library/jest-dom";
import { NotesPanel } from "./NotesPanel";
import type { Note } from "../types";

describe("NotesPanel", () => {
  const mockNotes: Note[] = [
    {
      id: "1",
      title: "First Note",
      content: "Content 1",
      updatedAt: Date.now(),
    },
    {
      id: "2",
      title: "Second Note",
      content: "Content 2",
      updatedAt: Date.now(),
    },
  ];

  const defaultProps = {
    notes: mockNotes,
    showAddNote: false,
    newNoteTitle: "",
    newNoteContent: "",
    onShowAddNote: jest.fn(),
    onCancelAddNote: jest.fn(),
    onAddNote: jest.fn(),
    onUpdateNote: jest.fn(),
    onDeleteNote: jest.fn(),
    onNewNoteTitleChange: jest.fn(),
    onNewNoteContentChange: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("rendering", () => {
    it("should render the New Note button", () => {
      render(<NotesPanel {...defaultProps} />);
      expect(screen.getByText("+ New Note")).toBeInTheDocument();
    });

    it("should render all notes", () => {
      render(<NotesPanel {...defaultProps} />);
      expect(screen.getByDisplayValue("First Note")).toBeInTheDocument();
      expect(screen.getByDisplayValue("Second Note")).toBeInTheDocument();
    });

    it("should show empty state when no notes", () => {
      render(<NotesPanel {...defaultProps} notes={[]} />);
      expect(
        screen.getByText("No notes yet. Create one to keep track of ideas."),
      ).toBeInTheDocument();
    });

    it("should not show empty state when showAddNote is true", () => {
      render(<NotesPanel {...defaultProps} notes={[]} showAddNote={true} />);
      expect(
        screen.queryByText("No notes yet. Create one to keep track of ideas."),
      ).not.toBeInTheDocument();
    });
  });

  describe("add note form", () => {
    it("should show add note form when showAddNote is true", () => {
      render(<NotesPanel {...defaultProps} showAddNote={true} />);
      expect(screen.getByPlaceholderText("Note Title")).toBeInTheDocument();
      const editors = screen.getAllByPlaceholderText("Type something...");
      expect(editors.length).toBeGreaterThan(0);
      expect(editors[0]).toBeInTheDocument();
    });

    it("should call onShowAddNote when New Note button clicked", () => {
      render(<NotesPanel {...defaultProps} />);
      fireEvent.click(screen.getByText("+ New Note"));
      expect(defaultProps.onShowAddNote).toHaveBeenCalled();
    });

    it("should call onNewNoteTitleChange when title input changes", () => {
      render(<NotesPanel {...defaultProps} showAddNote={true} />);
      fireEvent.change(screen.getByPlaceholderText("Note Title"), {
        target: { value: "New Title" },
      });
      expect(defaultProps.onNewNoteTitleChange).toHaveBeenCalledWith(
        "New Title",
      );
    });

    it("should call onNewNoteContentChange when content input changes", () => {
      render(<NotesPanel {...defaultProps} showAddNote={true} />);
      // There may be multiple editors (one for new note, one for each existing mock note)
      // The new note form is rendered first.
      const inputs = screen.getAllByPlaceholderText("Type something...");
      fireEvent.change(inputs[0], {
        target: { value: "New Content" },
      });
      expect(defaultProps.onNewNoteContentChange).toHaveBeenCalledWith(
        "New Content",
      );
    });

    it("should disable Save button when title is empty", () => {
      render(
        <NotesPanel {...defaultProps} showAddNote={true} newNoteTitle="" />,
      );
      expect(screen.getByText("Save")).toBeDisabled();
    });

    it("should enable Save button when title is provided", () => {
      render(
        <NotesPanel
          {...defaultProps}
          showAddNote={true}
          newNoteTitle="My Note"
        />,
      );
      expect(screen.getByText("Save")).not.toBeDisabled();
    });

    it("should call onAddNote when Save button clicked", () => {
      render(
        <NotesPanel
          {...defaultProps}
          showAddNote={true}
          newNoteTitle="My Note"
        />,
      );
      fireEvent.click(screen.getByText("Save"));
      expect(defaultProps.onAddNote).toHaveBeenCalled();
    });

    it("should call onCancelAddNote when Cancel clicked", () => {
      render(<NotesPanel {...defaultProps} showAddNote={true} />);
      fireEvent.click(screen.getByText("Cancel"));
      expect(defaultProps.onCancelAddNote).toHaveBeenCalled();
    });
  });

  describe("note editing", () => {
    it("should call onUpdateNote when note title changed", () => {
      render(<NotesPanel {...defaultProps} />);
      fireEvent.change(screen.getByDisplayValue("First Note"), {
        target: { value: "Updated Title" },
      });
      expect(defaultProps.onUpdateNote).toHaveBeenCalledWith(
        "1",
        "Updated Title",
        "Content 1",
      );
    });

    it("should call onUpdateNote when note content changed", () => {
      render(<NotesPanel {...defaultProps} />);
      fireEvent.change(screen.getByDisplayValue("Content 1"), {
        target: { value: "Updated Content" },
      });
      expect(defaultProps.onUpdateNote).toHaveBeenCalledWith(
        "1",
        "First Note",
        "Updated Content",
      );
    });

    it("should call onDeleteNote when delete button clicked", () => {
      render(<NotesPanel {...defaultProps} />);
      const deleteButtons = screen.getAllByText("×");
      fireEvent.click(deleteButtons[0]);
      expect(defaultProps.onDeleteNote).toHaveBeenCalledWith("1");
    });
  });
});
