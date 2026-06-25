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

// This is the raw user object returned by the GitHub API
export interface ProviderGitHubUser {
  login: string;
  id: number;
  node_id: string;
  avatar_url: string;
  gravatar_id: string;
  url: string;
  html_url: string;
  followers_url: string;
  following_url: string;
  gists_url: string;
  starred_url: string;
  subscriptions_url: string;
  organizations_url: string;
  repos_url: string;
  events_url: string;
  received_events_url: string;
  type: string;
  site_admin: boolean;
  name: string | null;
  company: string | null;
  blog: string | null;
  location: string | null;
  email: string | null;
  hireable: boolean | null;
  bio: string | null;
  twitter_username: string | null;
  public_repos: number;
  public_gists: number;
  followers: number;
  following: number;
  created_at: string;
  updated_at: string;
  private_gists?: number;
  total_private_repos?: number;
  owned_private_repos?: number;
  disk_usage?: number;
  collaborators?: number;
  two_factor_authentication?: boolean;
  plan?: {
    name: string;
    space: number;
    collaborators: number;
    private_repos: number;
  };
}

// This is the raw user object returned by the Google API
export interface ProviderGoogleUser {
  id: string;
  email: string;
  verified_email: boolean;
  name: string;
  given_name: string;
  family_name: string;
  picture: string;
  locale: string;
}

// This is the raw user object returned by the GitLab API
export interface ProviderGitLabUser {
  id: number;
  username: string;
  name: string;
  email: string;
  avatar_url: string;
  web_url: string;
  state: string;
  bio: string | null;
  location: string | null;
  public_email: string | null;
  skype: string | null;
  linkedin: string | null;
  twitter: string | null;
  website_url: string | null;
  organization: string | null;
  created_at: string;
  last_sign_in_at: string | null;
  confirmed_at: string | null;
  last_activity_on: string | null;
  two_factor_enabled: boolean;
  external: boolean;
  private_profile: boolean;
}

// This is the raw user object returned by the Auth0 API
export interface ProviderAuth0User {
  sub: string;
  name: string;
  given_name?: string;
  family_name?: string;
  middle_name?: string;
  nickname?: string;
  preferred_username?: string;
  profile?: string;
  picture?: string;
  website?: string;
  email?: string;
  email_verified?: boolean;
  gender?: string;
  birthdate?: string;
  zoneinfo?: string;
  locale?: string;
  phone_number?: string;
  phone_number_verified?: boolean;
  address?: object;
  updated_at?: string;
  [key: string]: any; // Auth0 can have custom claims
}

// This is the raw user object returned by the LinkedIn API
export interface ProviderLinkedInUser {
  id: string;
  firstName: {
    localized: { [key: string]: string };
    preferredLocale: { country: string; language: string };
  };
  lastName: {
    localized: { [key: string]: string };
    preferredLocale: { country: string; language: string };
  };
  profilePicture?: {
    displayImage: string;
  };
  emailAddress?: string; // This comes from a separate API call
}

export type AuthProvider =
  | "github"
  | "google"
  | "gitlab"
  | "auth0"
  | "linkedin";

// This is the unified user object used throughout the application
export interface AppUser {
  provider: AuthProvider;
  avatarUrl: string;
  name: string | null;
  email: string | null;
  profileUrl: string;
  username: string;
  rawData: object;
  accessToken?: string; // Add access token
  idToken?: string; // Add ID token
  refreshToken?: string; // Add refresh token
  scopes?: string[]; // OAuth scopes (if available)
  tokenType?: string; // e.g., bearer
  tokenExpiresAt?: number; // epoch ms if known
  jwtPayload?: Record<string, any>; // decoded JWT if token is JWT
}

// Token refresh request/response interfaces
export interface TokenRefreshRequest {
  provider: AuthProvider;
  refreshToken: string;
  clientId?: string;
  clientSecret?: string;
  isHosted?: boolean;
  auth0Domain?: string;
}

export interface TokenRefreshResponse {
  access_token: string;
  refresh_token?: string;
  expires_in?: number;
  token_type?: string;
  scope?: string;
  id_token?: string;
}

// Token revocation request/response interfaces
export interface TokenRevocationRequest {
  provider: AuthProvider;
  token: string;
  tokenTypeHint?: "access_token" | "refresh_token";
  clientId?: string;
  clientSecret?: string;
  isHosted?: boolean;
  auth0Domain?: string;
}

export interface TokenRevocationResponse {
  success: boolean;
  message?: string;
}

// API Explorer interfaces
export interface ApiEndpoint {
  id: string;
  name: string;
  description: string;
  url: string;
  method: "GET" | "POST" | "PUT" | "DELETE" | "PATCH";
  requiredScopes?: string[];
}

export interface ApiExploreRequest {
  provider: AuthProvider;
  accessToken: string;
  endpoint: ApiEndpoint;
}

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

export interface ApiExploreResponse {
  success: boolean;
  data?: any;
  error?: string;
  status?: number;
  headers?: Record<string, string>;
}
