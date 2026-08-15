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
import { Button } from "@vitruviansoftware/design-system";
import { useFeatureFlag } from "../lib/flags/use-feature-flag";
import { FEATURE_FLAGS } from "../constants/features";

interface LoginProps {
  onSuccess: () => void;
}

export const Login: React.FC<LoginProps> = ({ onSuccess }) => {
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const useDesignSystem = useFeatureFlag(
    FEATURE_FLAGS.USE_DESIGN_SYSTEM,
    false,
  );

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
      className={useDesignSystem ? undefined : "card"}
      style={
        useDesignSystem
          ? {
              maxWidth: "320px",
              margin: "0 auto",
              textAlign: "center",
              backgroundColor: "var(--paper, #fbf7ee)",
              border: "2px solid var(--ink, #1f1d1a)",
              boxShadow: "4px 4px 0 0 var(--ink, #1f1d1a)",
              padding: "24px",
              color: "var(--ink, #1f1d1a)",
            }
          : { maxWidth: "320px", margin: "0 auto", textAlign: "center" }
      }
    >
      <h2
        style={
          useDesignSystem
            ? {
                marginBottom: "12px",
                fontSize: "18px",
                fontWeight: 700,
                fontFamily: "var(--font-mono, monospace)",
                letterSpacing: "-0.02em",
                color: "var(--ink, #1f1d1a)",
              }
            : {
                marginBottom: "16px",
                fontSize: "18px",
                fontWeight: "bold",
              }
        }
      >
        Welcome to Tabula
      </h2>
      <p
        style={
          useDesignSystem
            ? {
                marginBottom: "20px",
                color: "var(--paper-dim, #736d64)",
                fontSize: "13px",
                lineHeight: "1.4",
              }
            : {
                marginBottom: "24px",
                color: "var(--color-text-secondary)",
                fontSize: "14px",
              }
        }
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
            borderRadius: useDesignSystem ? "0" : "4px",
            border: useDesignSystem ? "1px solid #991B1B" : undefined,
            fontSize: "12px",
            textAlign: "left",
            fontFamily: useDesignSystem
              ? "var(--font-mono, monospace)"
              : undefined,
          }}
        >
          {error}
        </div>
      )}

      {useDesignSystem ? (
        <Button
          onClick={handleLogin}
          variant="primary"
          disabled={loading}
          style={{ width: "100%", marginBottom: "12px" }}
        >
          {loading ? "Connecting..." : "Continue with SSO"}
        </Button>
      ) : (
        <button
          type="button"
          className="btn btn-primary"
          style={{ width: "100%", marginBottom: "12px" }}
          disabled={loading}
          onClick={handleLogin}
        >
          {loading ? "Connecting..." : "Continue with SSO"}
        </button>
      )}

      <p
        style={
          useDesignSystem
            ? {
                fontSize: "11px",
                fontFamily: "var(--font-mono, monospace)",
                color: "var(--paper-dim, #736d64)",
                margin: 0,
              }
            : { fontSize: "12px", color: "var(--color-text-secondary)" }
        }
      >
        Secure authentication via WorkOS
      </p>
    </div>
  );
};
