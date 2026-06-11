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
import { render, screen } from "@testing-library/react";
import "@testing-library/jest-dom";
import { Icon, Icons } from "./icons";

describe("Icon", () => {
  it("should render icon with name", () => {
    render(<Icon name="add" />);
    expect(screen.getByText("add")).toBeInTheDocument();
  });

  it("should apply size class for sm", () => {
    render(<Icon name="search" size="sm" />);
    const icon = screen.getByText("search");
    expect(icon).toHaveClass("icon-sm");
  });

  it("should apply size class for lg", () => {
    render(<Icon name="delete" size="lg" />);
    const icon = screen.getByText("delete");
    expect(icon).toHaveClass("icon-lg");
  });

  it("should not apply size class for md (default)", () => {
    render(<Icon name="edit" size="md" />);
    const icon = screen.getByText("edit");
    expect(icon).not.toHaveClass("icon-md");
    expect(icon).toHaveClass("material-icons");
  });

  it("should use outlined class when outlined prop is true", () => {
    render(<Icon name="info" outlined />);
    const icon = screen.getByText("info");
    expect(icon).toHaveClass("material-icons-outlined");
  });

  it("should accept custom className", () => {
    render(<Icon name="star" className="custom-class" />);
    const icon = screen.getByText("star");
    expect(icon).toHaveClass("custom-class");
  });

  it("should accept custom style", () => {
    render(<Icon name="home" style={{ color: "red" }} />);
    const icon = screen.getByText("home");
    expect(icon).toHaveStyle({ color: "red" });
  });
});

describe("Icons presets", () => {
  it("should render ChevronDown", () => {
    render(<>{Icons.ChevronDown()}</>);
    expect(screen.getByText("keyboard_arrow_down")).toBeInTheDocument();
  });

  it("should render ChevronRight", () => {
    render(<>{Icons.ChevronRight()}</>);
    expect(screen.getByText("keyboard_arrow_right")).toBeInTheDocument();
  });

  it("should render ChevronUp", () => {
    render(<>{Icons.ChevronUp()}</>);
    expect(screen.getByText("keyboard_arrow_up")).toBeInTheDocument();
  });

  it("should render Add", () => {
    render(<>{Icons.Add()}</>);
    expect(screen.getByText("add")).toBeInTheDocument();
  });

  it("should render Edit with outlined", () => {
    render(<>{Icons.Edit()}</>);
    const icon = screen.getByText("edit");
    expect(icon).toHaveClass("material-icons-outlined");
  });

  it("should render Delete", () => {
    render(<>{Icons.Delete()}</>);
    expect(screen.getByText("delete")).toBeInTheDocument();
  });

  it("should render Close", () => {
    render(<>{Icons.Close()}</>);
    expect(screen.getByText("close")).toBeInTheDocument();
  });

  it("should render MoreVert", () => {
    render(<>{Icons.MoreVert()}</>);
    expect(screen.getByText("more_vert")).toBeInTheDocument();
  });

  it("should render MoreHoriz", () => {
    render(<>{Icons.MoreHoriz()}</>);
    expect(screen.getByText("more_horiz")).toBeInTheDocument();
  });

  it("should render Search", () => {
    render(<>{Icons.Search()}</>);
    expect(screen.getByText("search")).toBeInTheDocument();
  });

  it("should render Link", () => {
    render(<>{Icons.Link()}</>);
    expect(screen.getByText("link")).toBeInTheDocument();
  });

  it("should render OpenInNew", () => {
    render(<>{Icons.OpenInNew()}</>);
    expect(screen.getByText("open_in_new")).toBeInTheDocument();
  });

  it("should render ContentCopy", () => {
    render(<>{Icons.ContentCopy()}</>);
    expect(screen.getByText("content_copy")).toBeInTheDocument();
  });

  it("should render Check", () => {
    render(<>{Icons.Check()}</>);
    expect(screen.getByText("check")).toBeInTheDocument();
  });

  it("should render CheckCircle", () => {
    render(<>{Icons.CheckCircle()}</>);
    expect(screen.getByText("check_circle")).toBeInTheDocument();
  });

  it("should render Folder", () => {
    render(<>{Icons.Folder()}</>);
    expect(screen.getByText("folder")).toBeInTheDocument();
  });

  it("should render Dashboard", () => {
    render(<>{Icons.Dashboard()}</>);
    expect(screen.getByText("dashboard")).toBeInTheDocument();
  });

  it("should render Tab", () => {
    render(<>{Icons.Tab()}</>);
    expect(screen.getByText("tab")).toBeInTheDocument();
  });

  it("should render Note", () => {
    render(<>{Icons.Note()}</>);
    expect(screen.getByText("description")).toBeInTheDocument();
  });

  it("should render Task", () => {
    render(<>{Icons.Task()}</>);
    expect(screen.getByText("check_box")).toBeInTheDocument();
  });

  it("should pass props to preset icons", () => {
    render(<>{Icons.Delete({ className: "delete-custom" })}</>);
    const icon = screen.getByText("delete");
    expect(icon).toHaveClass("delete-custom");
  });
});
