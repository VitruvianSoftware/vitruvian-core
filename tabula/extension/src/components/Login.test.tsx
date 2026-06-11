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
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import "@testing-library/jest-dom";
import { Login } from "./Login";
import { AuthService } from "../services/auth";

jest.mock("../services/auth", () => ({
  AuthService: {
    login: jest.fn(),
  },
}));

describe("Login", () => {
  const mockOnSuccess = jest.fn();

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("should render login form", () => {
    render(<Login onSuccess={mockOnSuccess} />);

    expect(screen.getByText("Welcome to Tabula")).toBeInTheDocument();
    expect(screen.getByText("Continue with SSO")).toBeInTheDocument();
    expect(
      screen.getByText("Secure authentication via WorkOS"),
    ).toBeInTheDocument();
  });

  it("should call AuthService.login on button click", async () => {
    (AuthService.login as jest.Mock).mockResolvedValue(undefined);

    render(<Login onSuccess={mockOnSuccess} />);

    fireEvent.click(screen.getByText("Continue with SSO"));

    await waitFor(() => {
      expect(AuthService.login).toHaveBeenCalled();
    });
  });

  it("should call onSuccess after successful login", async () => {
    (AuthService.login as jest.Mock).mockResolvedValue(undefined);

    render(<Login onSuccess={mockOnSuccess} />);

    fireEvent.click(screen.getByText("Continue with SSO"));

    await waitFor(() => {
      expect(mockOnSuccess).toHaveBeenCalled();
    });
  });

  it("should show loading state during login", async () => {
    (AuthService.login as jest.Mock).mockImplementation(
      () =>
        new Promise<void>((resolve) => {
          setTimeout(resolve, 100);
        }),
    );

    render(<Login onSuccess={mockOnSuccess} />);

    fireEvent.click(screen.getByText("Continue with SSO"));

    expect(screen.getByText("Connecting...")).toBeInTheDocument();

    await waitFor(() => {
      expect(screen.getByText("Continue with SSO")).toBeInTheDocument();
    });
  });

  it("should show error message on login failure", async () => {
    (AuthService.login as jest.Mock).mockRejectedValue(
      new Error("Authentication failed"),
    );

    render(<Login onSuccess={mockOnSuccess} />);

    fireEvent.click(screen.getByText("Continue with SSO"));

    await waitFor(() => {
      expect(screen.getByText("Authentication failed")).toBeInTheDocument();
    });

    expect(mockOnSuccess).not.toHaveBeenCalled();
  });

  it("should disable button during loading", async () => {
    (AuthService.login as jest.Mock).mockImplementation(
      () =>
        new Promise<void>((resolve) => {
          setTimeout(resolve, 100);
        }),
    );

    render(<Login onSuccess={mockOnSuccess} />);

    fireEvent.click(screen.getByText("Continue with SSO"));

    expect(screen.getByText("Connecting...")).toBeDisabled();

    await waitFor(() => {
      expect(screen.getByText("Continue with SSO")).toBeEnabled();
    });
  });

  it("should show fallback error when error has no message", async () => {
    (AuthService.login as jest.Mock).mockRejectedValue({ noMessage: true });

    render(<Login onSuccess={mockOnSuccess} />);

    fireEvent.click(screen.getByText("Continue with SSO"));

    await waitFor(() => {
      expect(screen.getByText("Login failed")).toBeInTheDocument();
    });
  });
});
