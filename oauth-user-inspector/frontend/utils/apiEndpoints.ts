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

import type { AppUser, ApiEndpoint } from "../types";

// Define common API endpoints for each provider
export const getProviderEndpoints = (
  provider: AppUser["provider"],
): ApiEndpoint[] => {
  switch (provider) {
    case "github":
      return [
        {
          id: "user",
          name: "Current User",
          description: "Get the authenticated user's profile",
          url: "https://api.github.com/user",
          method: "GET",
          requiredScopes: ["read:user"],
        },
        {
          id: "user_emails",
          name: "User Emails",
          description: "List email addresses for the authenticated user",
          url: "https://api.github.com/user/emails",
          method: "GET",
          requiredScopes: ["user:email"],
        },
        {
          id: "user_repos",
          name: "User Repositories",
          description: "List repositories for the authenticated user",
          url: "https://api.github.com/user/repos",
          method: "GET",
          requiredScopes: ["repo", "public_repo"],
        },
        {
          id: "user_orgs",
          name: "User Organizations",
          description: "List organizations for the authenticated user",
          url: "https://api.github.com/user/orgs",
          method: "GET",
          requiredScopes: ["read:org"],
        },
        {
          id: "user_followers",
          name: "User Followers",
          description: "List followers of the authenticated user",
          url: "https://api.github.com/user/followers",
          method: "GET",
          requiredScopes: ["user:follow"],
        },
        {
          id: "user_following",
          name: "User Following",
          description: "List users followed by the authenticated user",
          url: "https://api.github.com/user/following",
          method: "GET",
          requiredScopes: ["user:follow"],
        },
      ];

    case "google":
      return [
        {
          id: "userinfo",
          name: "User Info",
          description: "Get the authenticated user's profile information",
          url: "https://www.googleapis.com/oauth2/v1/userinfo",
          method: "GET",
          requiredScopes: ["openid", "profile"],
        },
        {
          id: "userinfo_v2",
          name: "User Info (v2)",
          description: "Get detailed user profile information",
          url: "https://www.googleapis.com/oauth2/v2/userinfo",
          method: "GET",
          requiredScopes: ["openid", "profile"],
        },
        {
          id: "people_me",
          name: "People API - Me",
          description: "Get the authenticated user's profile via People API",
          url: "https://people.googleapis.com/v1/people/me?personFields=names,emailAddresses,photos,urls,organizations",
          method: "GET",
          requiredScopes: ["profile"],
        },
        {
          id: "gmail_profile",
          name: "Gmail Profile",
          description: "Get the user's Gmail profile",
          url: "https://gmail.googleapis.com/gmail/v1/users/me/profile",
          method: "GET",
          requiredScopes: ["gmail.readonly"],
        },
      ];

    case "gitlab":
      return [
        {
          id: "user",
          name: "Current User",
          description: "Get the authenticated user's profile",
          url: "https://gitlab.com/api/v4/user",
          method: "GET",
          requiredScopes: ["read_user"],
        },
        {
          id: "user_projects",
          name: "User Projects",
          description: "List projects for the authenticated user",
          url: "https://gitlab.com/api/v4/projects?membership=true",
          method: "GET",
          requiredScopes: ["read_user"],
        },
        {
          id: "user_groups",
          name: "User Groups",
          description: "List groups for the authenticated user",
          url: "https://gitlab.com/api/v4/groups?min_access_level=10",
          method: "GET",
          requiredScopes: ["read_user"],
        },
        {
          id: "user_keys",
          name: "SSH Keys",
          description: "List SSH keys for the authenticated user",
          url: "https://gitlab.com/api/v4/user/keys",
          method: "GET",
          requiredScopes: ["read_user"],
        },
      ];

    case "auth0":
      return [
        {
          id: "userinfo",
          name: "User Info",
          description: "Get the authenticated user's profile information",
          url: "/userinfo", // This will be constructed with the domain
          method: "GET",
          requiredScopes: ["openid", "profile"],
        },
      ];

    case "zitadel":
      return [
        {
          id: "userinfo",
          name: "User Info",
          description: "Get the authenticated user's profile information",
          // Relative URL so the server prefixes the resolved Zitadel domain
          // (request-supplied / secret / default), matching the auth0 case.
          url: "/oidc/v1/userinfo",
          method: "GET",
          requiredScopes: ["openid", "profile", "email"],
        },
      ];

    case "linkedin":
      return [
        {
          id: "userinfo",
          name: "User Info",
          description: "OpenID Connect userinfo (profile + email)",
          url: "https://api.linkedin.com/v2/userinfo",
          method: "GET",
          requiredScopes: ["openid", "profile", "email"],
        },
      ];

    default:
      return [];
  }
};
