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

export interface User {
  id: string;
  email: string;
  name: string;
  picture?: string;
  tier: string;
}

export interface AuthResponse {
  token: string;
  user: User;
}

export class AuthService {
  private static readonly API_URL = `${process.env.NEXT_PUBLIC_API_URL || "http://localhost:8080/api/v1"}/auth`;

  /**
   * Open login popup and wait for token
   */
  static login(): Promise<AuthResponse> {
    return new Promise((resolve, reject) => {
      const width = 500;
      const height = 600;
      const left = window.screen.width / 2 - width / 2;
      const top = window.screen.height / 2 - height / 2;

      const originParam =
        typeof window !== "undefined"
          ? `?origin=${encodeURIComponent(window.location.origin)}`
          : "";
      const popup = window.open(
        `${this.API_URL}/login${originParam}`,
        "Tabula Login",
        `width=${width},height=${height},left=${left},top=${top}`,
      );

      if (!popup) {
        reject(new Error("Popup blocked"));
        return;
      }

      // Only the auth popup's own origin may deliver a token. Without this,
      // any page that can postMessage to this window could inject an attacker's
      // JWT (login CSRF / token fixation) — a risk widened by the relay funnel
      // that drives strangers through this login popup.
      const expectedOrigin = new URL(AuthService.API_URL).origin;
      const messageHandler = (event: MessageEvent) => {
        if (event.origin !== expectedOrigin) return;
        if (event.data?.type === "TABULA_AUTH_SUCCESS") {
          const { token, user } = event.data.payload;

          // Save to local storage
          localStorage.setItem("tabula_token", token);
          localStorage.setItem("tabula_user", JSON.stringify(user));

          window.removeEventListener("message", messageHandler);
          resolve({ token, user });
        }
      };

      window.addEventListener("message", messageHandler);

      // Check if popup closed by user
      const timer = setInterval(() => {
        if (popup.closed) {
          clearInterval(timer);
          window.removeEventListener("message", messageHandler);
          reject(new Error("Login cancelled"));
        }
      }, 1000);
    });
  }

  /**
   * Logout user
   */
  static logout(): void {
    localStorage.removeItem("tabula_token");
    localStorage.removeItem("tabula_user");
  }

  /**
   * Get current auth token
   */
  static getToken(): string | null {
    if (typeof window === "undefined") return null;
    return localStorage.getItem("tabula_token");
  }

  /**
   * Get current user
   */
  static getUser(): User | null {
    if (typeof window === "undefined") return null;
    const userStr = localStorage.getItem("tabula_user");
    return userStr ? JSON.parse(userStr) : null;
  }
}
