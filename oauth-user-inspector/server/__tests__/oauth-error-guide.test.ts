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

import {
  enhanceOAuthError,
  isKnownOAuthError,
  getAllErrorGuides,
} from "../oauth-error-guide";

describe("OAuth Error Guide", () => {
  describe("enhanceOAuthError", () => {
    it("should detect invalid_scope error and provide guidance", () => {
      const errorResponse = JSON.stringify({
        error: "invalid_scope",
        error_description: "The requested scope is invalid",
      });

      const enhanced = enhanceOAuthError(errorResponse, 400, "github");

      expect(enhanced.errorCode).toBe("invalid_scope");
      expect(enhanced.guide).toBeDefined();
      expect(enhanced.guide?.title).toBe("Invalid Scope");
      expect(enhanced.guide?.troubleshooting).toContain(
        "Check that all requested scopes are supported by the OAuth provider",
      );
    });

    it("should detect unauthorized_client error and provide guidance", () => {
      const errorResponse = JSON.stringify({
        error: "unauthorized_client",
        error_description: "Client authentication failed",
      });

      const enhanced = enhanceOAuthError(errorResponse, 401, "google");

      expect(enhanced.errorCode).toBe("unauthorized_client");
      expect(enhanced.guide).toBeDefined();
      expect(enhanced.guide?.title).toBe("Unauthorized Client");
      expect(enhanced.guide?.troubleshooting).toContain(
        "Verify your Client ID and Client Secret are correct",
      );
    });

    it("should detect access_denied error and provide guidance", () => {
      const errorResponse = JSON.stringify({
        error: "access_denied",
        error_description: "User denied the request",
      });

      const enhanced = enhanceOAuthError(errorResponse, 403, "google");

      expect(enhanced.errorCode).toBe("access_denied");
      expect(enhanced.guide).toBeDefined();
      expect(enhanced.guide?.title).toBe("Access Denied");
      expect(enhanced.guide?.troubleshooting).toContain(
        "User may have clicked 'Cancel' or 'Deny' during authorization",
      );
    });

    it("should handle URL-encoded error responses", () => {
      const errorResponse =
        "error=invalid_grant&error_description=The%20authorization%20code%20has%20expired";

      const enhanced = enhanceOAuthError(errorResponse, 400, "github");

      expect(enhanced.errorCode).toBe("invalid_grant");
      expect(enhanced.guide).toBeDefined();
      expect(enhanced.guide?.title).toBe("Invalid Grant");
    });

    it("should handle plain text error responses", () => {
      const errorResponse = "server_error";

      const enhanced = enhanceOAuthError(errorResponse, 500, "auth0");

      expect(enhanced.errorCode).toBe("server_error");
      expect(enhanced.guide).toBeDefined();
      expect(enhanced.guide?.title).toBe("Server Error");
    });

    it("should handle unknown error codes gracefully", () => {
      const errorResponse = JSON.stringify({
        error: "unknown_error",
        error_description: "This is an unknown error",
      });

      const enhanced = enhanceOAuthError(errorResponse, 400, "github");

      expect(enhanced.errorCode).toBe("unknown_error");
      expect(enhanced.guide).toBeUndefined();
      expect(enhanced.error).toBe("This is an unknown error");
    });

    it("should handle malformed JSON gracefully", () => {
      const errorResponse = "invalid json {";

      const enhanced = enhanceOAuthError(errorResponse, 400, "github");

      expect(enhanced.error).toBe("invalid json {");
      expect(enhanced.guide).toBeUndefined();
    });

    it("should prioritize error_description over error for message", () => {
      const errorResponse = JSON.stringify({
        error: "invalid_scope",
        error_description: "Detailed error description",
      });

      const enhanced = enhanceOAuthError(errorResponse, 400, "github");

      expect(enhanced.error).toBe("Detailed error description");
      expect(enhanced.errorCode).toBe("invalid_scope");
    });
  });

  describe("isKnownOAuthError", () => {
    it("should return true for known error codes", () => {
      expect(isKnownOAuthError("invalid_scope")).toBe(true);
      expect(isKnownOAuthError("unauthorized_client")).toBe(true);
      expect(isKnownOAuthError("access_denied")).toBe(true);
      expect(isKnownOAuthError("invalid_grant")).toBe(true);
    });

    it("should return false for unknown error codes", () => {
      expect(isKnownOAuthError("unknown_error")).toBe(false);
      expect(isKnownOAuthError("custom_error")).toBe(false);
      expect(isKnownOAuthError("")).toBe(false);
    });

    it("should be case insensitive", () => {
      expect(isKnownOAuthError("INVALID_SCOPE")).toBe(true);
      expect(isKnownOAuthError("Invalid_Scope")).toBe(true);
    });
  });

  describe("getAllErrorGuides", () => {
    it("should return all available error guides", () => {
      const guides = getAllErrorGuides();

      expect(guides).toHaveProperty("invalid_scope");
      expect(guides).toHaveProperty("unauthorized_client");
      expect(guides).toHaveProperty("access_denied");
      expect(guides).toHaveProperty("invalid_grant");
      expect(guides).toHaveProperty("invalid_client");
      expect(guides).toHaveProperty("invalid_request");
      expect(guides).toHaveProperty("server_error");
      expect(guides).toHaveProperty("temporarily_unavailable");
    });

    it("should return guides with required properties", () => {
      const guides = getAllErrorGuides();

      Object.values(guides).forEach((guide) => {
        expect(guide).toHaveProperty("errorCode");
        expect(guide).toHaveProperty("title");
        expect(guide).toHaveProperty("description");
        expect(guide).toHaveProperty("troubleshooting");
        expect(guide).toHaveProperty("commonCauses");
        expect(Array.isArray(guide.troubleshooting)).toBe(true);
        expect(Array.isArray(guide.commonCauses)).toBe(true);
      });
    });
  });
});
