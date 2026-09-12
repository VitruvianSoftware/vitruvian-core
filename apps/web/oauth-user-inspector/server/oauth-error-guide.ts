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
 * OAuth Error Code Detection and Troubleshooting Guide
 *
 * This module provides enhanced error handling for common OAuth error codes
 * by detecting error patterns and providing context-sensitive troubleshooting guidance.
 */

export interface OAuthErrorGuide {
  errorCode: string;
  title: string;
  description: string;
  troubleshooting: string[];
  commonCauses: string[];
}

export interface EnhancedOAuthError {
  error: string;
  errorCode?: string;
  guide?: OAuthErrorGuide;
}

/**
 * Common OAuth error codes and their troubleshooting guides
 */
const OAUTH_ERROR_GUIDES: Record<string, OAuthErrorGuide> = {
  invalid_scope: {
    errorCode: "invalid_scope",
    title: "Invalid Scope",
    description: "The requested scope is invalid, unknown, or malformed.",
    troubleshooting: [
      "Check that all requested scopes are supported by the OAuth provider",
      "Verify scope names are spelled correctly (case-sensitive)",
      "Remove any unsupported or deprecated scopes from your request",
      "Consult the provider's documentation for valid scope values",
    ],
    commonCauses: [
      "Typo in scope name",
      "Using deprecated or removed scopes",
      "Requesting scopes not available to your application type",
      "Mixing scopes from different OAuth versions",
    ],
  },

  unauthorized_client: {
    errorCode: "unauthorized_client",
    title: "Unauthorized Client",
    description:
      "The client is not authorized to request an access token using this method.",
    troubleshooting: [
      "Verify your Client ID and Client Secret are correct",
      "Check that your application is properly registered with the OAuth provider",
      "Ensure your redirect URI matches exactly what's registered",
      "Confirm your application type supports the requested grant type",
      "Check if your application needs approval from the OAuth provider",
    ],
    commonCauses: [
      "Incorrect Client ID or Client Secret",
      "Application not approved or verified",
      "Redirect URI mismatch",
      "Using wrong grant type for application",
      "Application suspended or disabled",
    ],
  },

  access_denied: {
    errorCode: "access_denied",
    title: "Access Denied",
    description:
      "The resource owner or authorization server denied the request.",
    troubleshooting: [
      "User may have clicked 'Cancel' or 'Deny' during authorization",
      "Try the authorization flow again",
      "Ensure you're requesting appropriate permissions for your use case",
      "Check if the user account has sufficient privileges",
      "Verify the application is approved for the requested scopes",
    ],
    commonCauses: [
      "User denied authorization",
      "Requesting excessive permissions",
      "User account restrictions",
      "Application not trusted by user",
      "Organizational policies blocking access",
    ],
  },

  invalid_client: {
    errorCode: "invalid_client",
    title: "Invalid Client",
    description:
      "Client authentication failed or client credentials are invalid.",
    troubleshooting: [
      "Double-check your Client ID and Client Secret",
      "Ensure credentials are not expired or revoked",
      "Verify you're using the correct authentication method",
      "Check if your application needs to be re-registered",
      "Confirm your application is active and not suspended",
    ],
    commonCauses: [
      "Wrong Client ID or Client Secret",
      "Expired client credentials",
      "Application deleted or suspended",
      "Incorrect authentication method",
      "Client credentials leaked and revoked",
    ],
  },

  invalid_grant: {
    errorCode: "invalid_grant",
    title: "Invalid Grant",
    description:
      "The provided authorization grant is invalid, expired, or revoked.",
    troubleshooting: [
      "Authorization code may have expired (typically valid for 10 minutes)",
      "Code may have already been used (codes are single-use)",
      "Verify the redirect URI matches the one used in authorization",
      "Check that the authorization code wasn't tampered with",
      "Ensure system clocks are synchronized",
    ],
    commonCauses: [
      "Authorization code expired",
      "Code already exchanged for token",
      "Redirect URI mismatch",
      "Clock skew between systems",
      "Code parameter modified or corrupted",
    ],
  },

  invalid_request: {
    errorCode: "invalid_request",
    title: "Invalid Request",
    description:
      "The request is missing a required parameter, includes invalid values, or is malformed.",
    troubleshooting: [
      "Check that all required parameters are included",
      "Verify parameter names and values are correct",
      "Ensure proper encoding of special characters",
      "Review the OAuth provider's API documentation",
      "Check request content-type and format",
    ],
    commonCauses: [
      "Missing required parameters",
      "Malformed parameter values",
      "Incorrect content-type header",
      "URL encoding issues",
      "Using wrong parameter names",
    ],
  },

  server_error: {
    errorCode: "server_error",
    title: "Server Error",
    description:
      "The authorization server encountered an unexpected condition.",
    troubleshooting: [
      "Wait a few minutes and retry the request",
      "Check the OAuth provider's status page for outages",
      "Verify your request is not malformed",
      "Contact the OAuth provider if issue persists",
      "Implement exponential backoff for retries",
    ],
    commonCauses: [
      "Temporary server overload",
      "OAuth provider infrastructure issues",
      "Database connectivity problems",
      "Rate limiting on provider side",
      "Maintenance windows",
    ],
  },

  temporarily_unavailable: {
    errorCode: "temporarily_unavailable",
    title: "Temporarily Unavailable",
    description:
      "The authorization server is currently unable to handle the request due to temporary overloading.",
    troubleshooting: [
      "Wait and retry after a brief delay",
      "Implement exponential backoff strategy",
      "Check if you're hitting rate limits",
      "Monitor OAuth provider status pages",
      "Consider caching tokens to reduce requests",
    ],
    commonCauses: [
      "Rate limiting exceeded",
      "Server overload",
      "Temporary maintenance",
      "Traffic spikes",
      "Resource exhaustion",
    ],
  },
};

/**
 * Detects OAuth error codes from error responses and provides troubleshooting guidance
 */
export function enhanceOAuthError(
  errorText: string,
  responseStatus?: number,
  provider?: string,
): EnhancedOAuthError {
  // Try to parse as JSON first
  let errorData: any = {};
  try {
    errorData = JSON.parse(errorText);
  } catch {
    // Try to parse as URL parameters
    const params = new URLSearchParams(errorText);
    errorData = {
      error:
        params.get("error") || params.get("error_description") || errorText,
      error_description: params.get("error_description"),
      error_code: params.get("error"),
    };
  }

  // Extract error code from various possible fields
  const errorCode =
    errorData.error ||
    errorData.error_code ||
    errorData.code ||
    (typeof errorData === "string" ? errorData : "");

  // Get the error description
  const errorDescription =
    errorData.error_description ||
    errorData.message ||
    errorData.description ||
    errorText;

  // Look up error guide
  const guide = OAUTH_ERROR_GUIDES[errorCode?.toLowerCase()];

  // Build enhanced error response
  const enhancedError: EnhancedOAuthError = {
    error:
      errorDescription ||
      `OAuth error: ${errorCode}` ||
      "Authentication failed",
  };

  if (errorCode) {
    enhancedError.errorCode = errorCode;
  }

  if (guide) {
    enhancedError.guide = guide;
  }

  return enhancedError;
}

/**
 * Checks if an error response indicates a known OAuth error pattern
 */
export function isKnownOAuthError(errorCode: string): boolean {
  return Object.keys(OAUTH_ERROR_GUIDES).includes(errorCode?.toLowerCase());
}

/**
 * Gets all available error guides (useful for documentation or testing)
 */
export function getAllErrorGuides(): Record<string, OAuthErrorGuide> {
  return { ...OAUTH_ERROR_GUIDES };
}
