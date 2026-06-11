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

import React, { useState } from "react";
import { AuthService } from "../services/auth";

interface LoginProps {
  onSuccess: () => void;
}

export const Login: React.FC<LoginProps> = ({ onSuccess }) => {
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const handleLogin = async () => {
    setError(null);
    setLoading(true);

    try {
      // WorkOS handles both Login and Signup
      await AuthService.login();
      onSuccess();
    } catch (err: unknown) {
      setError((err as Error).message || "Login failed");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div
      className="card"
      style={{ maxWidth: "320px", margin: "0 auto", textAlign: "center" }}
    >
      <h2
        style={{ marginBottom: "16px", fontSize: "18px", fontWeight: "bold" }}
      >
        Welcome to Tabula
      </h2>
      <p
        style={{
          marginBottom: "24px",
          color: "var(--color-text-secondary)",
          fontSize: "14px",
        }}
      >
        Please log in to sync your workspaces.
      </p>

      {error && (
        <div
          style={{
            padding: "8px",
            marginBottom: "12px",
            backgroundColor: "#FEE2E2",
            color: "#991B1B",
            borderRadius: "4px",
            fontSize: "12px",
            textAlign: "left",
          }}
        >
          {error}
        </div>
      )}

      <button
        type="button"
        className="btn btn-primary"
        style={{ width: "100%", marginBottom: "12px" }}
        disabled={loading}
        onClick={handleLogin}
      >
        {loading ? "Connecting..." : "Continue with SSO"}
      </button>

      <p style={{ fontSize: "12px", color: "var(--color-text-secondary)" }}>
        Secure authentication via WorkOS
      </p>
    </div>
  );
};
