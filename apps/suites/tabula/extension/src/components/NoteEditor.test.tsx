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
/* eslint-disable @typescript-eslint/no-explicit-any */
import { render, screen, fireEvent } from "@testing-library/react";
import "@testing-library/jest-dom";
import { NoteEditor } from "./NoteEditor";

describe("NoteEditor", () => {
  const defaultProps = {
    value: "Initial Content",
    onChange: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("should render textarea with initial content", () => {
    render(<NoteEditor {...defaultProps} />);
    expect(screen.getByDisplayValue("Initial Content")).toBeInTheDocument();
  });

  it("should call onChange when editing", () => {
    render(<NoteEditor {...defaultProps} />);
    fireEvent.change(screen.getByDisplayValue("Initial Content"), {
      target: { value: "New Content" },
    });
    expect(defaultProps.onChange).toHaveBeenCalledWith("New Content");
  });

  it("should toggle preview mode", () => {
    const { container } = render(<NoteEditor {...defaultProps} />);

    // Switch to Preview
    fireEvent.click(screen.getByTitle("Preview"));
    // Query by class since data-testid is not present
    expect(container.querySelector(".markdown-preview")).toBeInTheDocument();
    // Real markdown parser just returns text if no formatting
    expect(screen.getByText("Initial Content")).toBeInTheDocument();

    // Switch back to Edit
    fireEvent.click(screen.getByTitle("Edit"));
    expect(screen.getByDisplayValue("Initial Content")).toBeInTheDocument();
  });

  // Test toolbar interactions to cover insertSyntax
  it("should insert syntax for Bold", () => {
    render(<NoteEditor {...defaultProps} />);
    const textarea = screen.getByDisplayValue(
      "Initial Content",
    ) as HTMLTextAreaElement;

    // Select "Initial"
    textarea.setSelectionRange(0, 7);

    fireEvent.click(screen.getByTitle("Bold"));

    expect(defaultProps.onChange).toHaveBeenCalledWith("**Initial** Content");
  });

  it("should insert syntax for Italic", () => {
    render(<NoteEditor {...defaultProps} />);
    const textarea = screen.getByDisplayValue(
      "Initial Content",
    ) as HTMLTextAreaElement;
    textarea.setSelectionRange(0, 7);
    fireEvent.click(screen.getByTitle("Italic"));
    expect(defaultProps.onChange).toHaveBeenCalledWith("*Initial* Content");
  });

  it("should insert syntax for List", () => {
    render(<NoteEditor {...defaultProps} />);
    const textarea = screen.getByDisplayValue(
      "Initial Content",
    ) as HTMLTextAreaElement;
    textarea.setSelectionRange(0, 0); // Insert at cursor
    fireEvent.click(screen.getByTitle("List"));
    expect(defaultProps.onChange).toHaveBeenCalledWith("- Initial Content");
  });

  it("should toggle fullscreen", () => {
    render(<NoteEditor {...defaultProps} />);
    const container = screen
      .getByDisplayValue("Initial Content")
      .closest(".note-editor");

    // Enter Fullscreen
    fireEvent.click(screen.getByTitle("Fullscreen"));
    expect(container).toHaveClass("fullscreen");

    // Exit Fullscreen
    // The button title changes to "Exit Fullscreen" or similar?
    // Wait, implementation uses same button title or different?
    // Let's check implementation behavior. Code shows: title={isFullscreen ? 'Exit Fullscreen' : 'Fullscreen'}
    fireEvent.click(screen.getByTitle("Exit Fullscreen"));
    expect(container).not.toHaveClass("fullscreen");
  });

  it("should call onPopout when clicked", () => {
    const onPopout = jest.fn();
    render(<NoteEditor {...defaultProps} onPopout={onPopout} />);
    fireEvent.click(screen.getByTitle("Open in new window"));
    expect(onPopout).toHaveBeenCalled();
  });
});
