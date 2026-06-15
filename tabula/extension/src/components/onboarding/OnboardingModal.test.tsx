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

/// <reference types="@testing-library/jest-dom" />
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { OnboardingModal } from "./OnboardingModal";

const setup = (overrides: Record<string, unknown> = {}) => {
  const props = {
    isOpen: true,
    onSkip: jest.fn(),
    onComplete: jest.fn(),
    onCreateSpace: jest.fn().mockResolvedValue(undefined),
    onAddResource: jest.fn().mockResolvedValue(undefined),
    onSaveTabs: jest.fn().mockResolvedValue(undefined),
    ...overrides,
  };
  render(<OnboardingModal {...(props as never)} />);
  return props;
};

const createSpace = async (name = "Work") => {
  fireEvent.change(screen.getByPlaceholderText("Space name"), {
    target: { value: name },
  });
  fireEvent.click(screen.getByRole("button", { name: "Create space" }));
  expect(await screen.findByText("Add a resource")).toBeInTheDocument();
};

const addResource = async (title = "Docs", url = "https://example.com") => {
  fireEvent.change(screen.getByPlaceholderText("Title"), {
    target: { value: title },
  });
  fireEvent.change(screen.getByPlaceholderText("https://..."), {
    target: { value: url },
  });
  fireEvent.click(screen.getByRole("button", { name: "Add resource" }));
  expect(await screen.findByText("Save your tabs")).toBeInTheDocument();
};

describe("OnboardingModal (#138)", () => {
  beforeEach(() => jest.clearAllMocks());

  it("renders nothing when closed", () => {
    setup({ isOpen: false });
    expect(screen.queryByText("Create a space")).not.toBeInTheDocument();
  });

  it("opens on the create-a-space step", () => {
    setup();
    expect(screen.getByText("Create a space")).toBeInTheDocument();
    expect(screen.getByPlaceholderText("Space name")).toBeInTheDocument();
  });

  it("Skip dismisses the flow", () => {
    const props = setup();
    fireEvent.click(screen.getByRole("button", { name: "Skip" }));
    expect(props.onSkip).toHaveBeenCalledTimes(1);
  });

  it("creating a space calls onCreateSpace and advances to the resource step", async () => {
    const props = setup();
    await createSpace("Work");
    await waitFor(() =>
      expect(props.onCreateSpace).toHaveBeenCalledWith("Work"),
    );
  });

  it("Back returns to the previous step", async () => {
    setup();
    await createSpace();
    fireEvent.click(screen.getByRole("button", { name: "Back" }));
    expect(screen.getByText("Create a space")).toBeInTheDocument();
  });

  it("adding a resource calls onAddResource and advances to the save-tabs step", async () => {
    const props = setup();
    await createSpace();
    await addResource("Docs", "https://example.com");
    await waitFor(() =>
      expect(props.onAddResource).toHaveBeenCalledWith({
        title: "Docs",
        url: "https://example.com",
      }),
    );
  });

  it("saving tabs calls onSaveTabs", async () => {
    const props = setup();
    await createSpace();
    await addResource();
    fireEvent.click(
      screen.getByRole("button", { name: "Save my current tabs" }),
    );
    await waitFor(() => expect(props.onSaveTabs).toHaveBeenCalledTimes(1));
  });

  it("Finish completes the flow", async () => {
    const props = setup();
    await createSpace();
    await addResource();
    fireEvent.click(screen.getByRole("button", { name: "Finish" }));
    expect(props.onComplete).toHaveBeenCalledTimes(1);
  });
});
