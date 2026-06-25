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
import { AuthProvider } from "../types";
import {
  GithubIcon,
  GoogleIcon,
  GitLabIcon,
  Auth0Icon,
  LinkedInIcon,
  ClipboardIcon,
  ClipboardCheckIcon,
} from "./icons";
import Tabs, { Tab } from "./Tabs";
import ScopeSelector from "./ScopeSelector";

interface LoginScreenProps {
  onOAuthLogin: (
    provider: AuthProvider,
    clientId: string,
    clientSecret: string,
    auth0Domain?: string,
    scopes?: string,
  ) => void;
  onPatLogin: (pat: string) => void;
  onGcloudTokenLogin: (token: string) => void;
  onHostedOAuthLogin: (provider: AuthProvider, scopes?: string) => void;
  isLoading: boolean;
  hostedAvailability?: Partial<Record<AuthProvider, boolean>>;
  customRedirectUri?: string;
  onCustomRedirectUriChange?: (uri: string) => void;
}

const getRedirectUri = () => window.location.origin + window.location.pathname;

const getEffectiveRedirectUri = (customUri?: string) => {
  return customUri?.trim() || getRedirectUri();
};

const LoginScreen: React.FC<LoginScreenProps> = ({
  onOAuthLogin,
  onPatLogin,
  onGcloudTokenLogin,
  onHostedOAuthLogin,
  isLoading,
  hostedAvailability,
  customRedirectUri = "",
  onCustomRedirectUriChange,
}) => {
  const [githubClientId, setGithubClientId] = useState("");
  const [githubClientSecret, setGithubClientSecret] = useState("");
  const [githubScopes, setGithubScopes] = useState("");
  const [googleClientId, setGoogleClientId] = useState("");
  const [googleClientSecret, setGoogleClientSecret] = useState("");
  const [googleScopes, setGoogleScopes] = useState("");
  const [gitlabClientId, setGitlabClientId] = useState("");
  const [gitlabClientSecret, setGitlabClientSecret] = useState("");
  const [gitlabScopes, setGitlabScopes] = useState("");
  const [auth0ClientId, setAuth0ClientId] = useState("");
  const [auth0ClientSecret, setAuth0ClientSecret] = useState("");
  const [auth0Domain, setAuth0Domain] = useState("");
  const [auth0Scopes, setAuth0Scopes] = useState("");
  const [linkedinClientId, setLinkedinClientId] = useState("");
  const [linkedinClientSecret, setLinkedinClientSecret] = useState("");
  const [linkedinScopes, setLinkedinScopes] = useState("");
  const [pat, setPat] = useState("");
  const [gcloudToken, setGcloudToken] = useState("");
  const [copiedProvider, setCopiedProvider] = useState<AuthProvider | null>(
    null,
  );
  const [showGithubSecret, setShowGithubSecret] = useState(false);
  const [showGoogleSecret, setShowGoogleSecret] = useState(false);
  const [showGitlabSecret, setShowGitlabSecret] = useState(false);
  const [showAuth0Secret, setShowAuth0Secret] = useState(false);
  const [showLinkedinSecret, setShowLinkedinSecret] = useState(false);
  const [showPat, setShowPat] = useState(false);
  const [toast, setToast] = useState<string | null>(null);

  const handleCopy = (provider: AuthProvider) => {
    navigator.clipboard
      .writeText(getEffectiveRedirectUri(customRedirectUri))
      .then(
        () => {
          setCopiedProvider(provider);
          setTimeout(() => setCopiedProvider(null), 2000); // Reset after 2 seconds
        },
        (err) => {
          console.error("Could not copy text: ", err);
        },
      );
  };

  const isHostedAvailable = (provider: AuthProvider): boolean => {
    if (!hostedAvailability) return true; // default to enabled until known
    const v = hostedAvailability[provider];
    return v === undefined ? true : Boolean(v);
  };

  const handleCardPaste: React.ClipboardEventHandler<HTMLDivElement> = (e) => {
    try {
      const text = e.clipboardData.getData("text");
      if (!text) return;
      // Try JSON with client_id/client_secret
      if (text.trim().startsWith("{")) {
        const obj = JSON.parse(text);
        if (obj.client_id || obj.clientId) {
          setGithubClientId(obj.client_id || obj.clientId);
          setGitlabClientId(obj.client_id || obj.clientId);
          setAuth0ClientId(obj.client_id || obj.clientId);
          setLinkedinClientId(obj.client_id || obj.clientId);
        }
        if (obj.client_secret || obj.clientSecret) {
          setGithubClientSecret(obj.client_secret || obj.clientSecret);
          setGitlabClientSecret(obj.client_secret || obj.clientSecret);
          setAuth0ClientSecret(obj.client_secret || obj.clientSecret);
          setLinkedinClientSecret(obj.client_secret || obj.clientSecret);
        }
        if (obj.google_client_id) setGoogleClientId(obj.google_client_id);
        if (obj.google_client_secret)
          setGoogleClientSecret(obj.google_client_secret);
        if (obj.gitlab_client_id) setGitlabClientId(obj.gitlab_client_id);
        if (obj.gitlab_client_secret)
          setGitlabClientSecret(obj.gitlab_client_secret);
        if (obj.auth0_client_id) setAuth0ClientId(obj.auth0_client_id);
        if (obj.auth0_client_secret)
          setAuth0ClientSecret(obj.auth0_client_secret);
        if (obj.auth0_domain) setAuth0Domain(obj.auth0_domain);
        if (obj.linkedin_client_id) setLinkedinClientId(obj.linkedin_client_id);
        if (obj.linkedin_client_secret)
          setLinkedinClientSecret(obj.linkedin_client_secret);
        if (obj.pat) setPat(obj.pat);
        if (obj.gcloud_token) setGcloudToken(obj.gcloud_token);
        setToast("Pasted credentials parsed into fields");
        setTimeout(() => setToast(null), 2000);
      }
    } catch {}
  };

  return (
    <div
      className="bg-slate-800 p-8 rounded-xl shadow-2xl ring-1 ring-white/10 w-full max-w-2xl mx-auto transition-all duration-300"
      onPaste={handleCardPaste}
    >
      {toast && (
        <div className="mb-3 text-xs px-3 py-2 rounded-md border border-emerald-600 text-emerald-300 bg-emerald-900/20">
          {toast}
        </div>
      )}
      <div className="text-center mb-8">
        <h1 className="text-3xl font-bold text-white tracking-tight">
          OAuth User Inspector
        </h1>
        <p className="text-slate-400 mt-2">
          Select a provider to inspect your user data.
        </p>
      </div>

      {/* Redirect URI Configuration */}
      <div className="bg-slate-900/30 p-4 rounded-lg border border-slate-700 mb-6">
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-sm font-semibold text-white">
            Redirect URI Configuration
          </h3>
        </div>
        <div className="space-y-2">
          <label className="block text-xs text-slate-400">
            Custom Redirect URI (optional)
          </label>
          <div className="flex gap-2">
            <input
              type="text"
              value={customRedirectUri}
              onChange={(e) => onCustomRedirectUriChange?.(e.target.value)}
              placeholder={getRedirectUri()}
              className="flex-1 px-3 py-2 bg-slate-800 border border-slate-600 rounded-md text-slate-200 text-sm placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            />
            <button
              type="button"
              onClick={() => onCustomRedirectUriChange?.("")}
              className="px-3 py-2 text-xs text-slate-400 hover:text-white bg-slate-700 hover:bg-slate-600 rounded-md transition-colors"
            >
              Reset
            </button>
          </div>
          <p className="text-xs text-slate-500">
            Current:{" "}
            <span className="text-slate-300 font-mono text-xs">
              {getEffectiveRedirectUri(customRedirectUri)}
            </span>
          </p>
        </div>
      </div>

      <Tabs>
        <Tab label="GitHub" icon={<GithubIcon />}>
          <div className="space-y-8">
            {/* GitHub OAuth */}
            <div className="bg-slate-900/50 p-6 rounded-lg border border-slate-700 space-y-4">
              <div className="flex items-center mb-4">
                <GithubIcon className="h-8 w-8 text-white" />
                <h2 className="ml-3 text-xl font-semibold text-white">
                  Sign in with GitHub OAuth
                </h2>
              </div>
              <p className="text-sm text-slate-400 mb-2">
                Create a{" "}
                <a
                  href="https://github.com/settings/developers"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-blue-400 hover:underline"
                >
                  New OAuth App
                </a>{" "}
                and set the "Authorization callback URL" to:
              </p>
              <div className="flex gap-2 mb-3">
                <a
                  href="https://github.com/settings/developers"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-2 px-3 py-1.5 text-xs rounded-md border border-slate-600 text-slate-300 bg-slate-800/70 hover:bg-slate-700"
                >
                  <GithubIcon className="w-4 h-4" /> Open GitHub OAuth settings
                </a>
              </div>
              <div className="flex items-center justify-between text-sm bg-slate-700 p-2 rounded-md mb-4">
                <code className="text-xs text-slate-300 truncate">
                  {getEffectiveRedirectUri(customRedirectUri)}
                </code>
                <button
                  onClick={() => handleCopy("github")}
                  className="p-1 text-slate-400 hover:text-white focus:outline-none focus:ring-2 focus:ring-slate-500 rounded transition-colors"
                  aria-label="Copy redirect URL"
                >
                  {copiedProvider === "github" ? (
                    <ClipboardCheckIcon className="h-5 w-5 text-green-400" />
                  ) : (
                    <ClipboardIcon className="h-5 w-5" />
                  )}
                </button>
              </div>
              <div className="space-y-3">
                <div>
                  <label
                    htmlFor="github-client-id"
                    className="block text-sm font-medium text-slate-300"
                  >
                    GitHub OAuth App Client ID
                  </label>
                  <input
                    id="github-client-id"
                    type="text"
                    value={githubClientId}
                    onChange={(e) => setGithubClientId(e.target.value)}
                    placeholder="Enter your GitHub Client ID"
                    className="w-full mt-1 px-4 py-2 bg-slate-900 border border-slate-700 rounded-md text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-500 transition-colors"
                  />
                </div>
                <div>
                  <label
                    htmlFor="github-client-secret"
                    className="block text-sm font-medium text-slate-300"
                  >
                    GitHub OAuth App Client Secret
                  </label>
                  <div className="relative">
                    <input
                      id="github-client-secret"
                      type={showGithubSecret ? "text" : "password"}
                      value={githubClientSecret}
                      onChange={(e) => setGithubClientSecret(e.target.value)}
                      placeholder="Enter your GitHub Client Secret"
                      className="w-full mt-1 pr-12 px-4 py-2 bg-slate-900 border border-slate-700 rounded-md text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-500 transition-colors"
                    />
                    <button
                      type="button"
                      onClick={() => setShowGithubSecret((v) => !v)}
                      className="absolute right-2 top-1.5 text-xs px-2 py-0.5 rounded border border-slate-600 text-slate-400 hover:text-slate-200 hover:bg-slate-700"
                    >
                      {showGithubSecret ? "Hide" : "Show"}
                    </button>
                  </div>
                </div>
                <ScopeSelector
                  provider="github"
                  onScopeChange={setGithubScopes}
                />
              </div>
              <div className="mt-6">
                <button
                  onClick={() =>
                    onOAuthLogin(
                      "github",
                      githubClientId,
                      githubClientSecret,
                      undefined,
                      githubScopes,
                    )
                  }
                  disabled={!githubClientId || !githubClientSecret || isLoading}
                  className="w-full inline-flex items-center justify-center px-6 py-3 border border-transparent text-base font-medium rounded-md shadow-sm text-white bg-slate-600 hover:bg-slate-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-slate-500 disabled:bg-slate-600/50 disabled:cursor-not-allowed transition-all"
                >
                  <GithubIcon className="h-5 w-5 mr-2" />
                  Continue with GitHub
                </button>
              </div>
            </div>

            {/* GitHub PAT */}
            <div className="mt-10 pt-8 border-t border-slate-700 space-y-4">
              <h3 className="text-center text-lg font-medium text-slate-300 mb-4">
                Or use a GitHub Token
              </h3>
              <div className="text-slate-400 space-y-2 text-sm bg-slate-900/50 p-4 rounded-lg border border-slate-700">
                <p>
                  You can use a classic or fine-grained PAT. The token needs the{" "}
                  <code className="text-xs bg-slate-700 p-1 rounded">
                    read:user
                  </code>{" "}
                  and{" "}
                  <code className="text-xs bg-slate-700 p-1 rounded">
                    user:email
                  </code>{" "}
                  scopes.
                  <button
                    type="button"
                    className="ml-2 text-[11px] px-2 py-0.5 rounded border border-slate-600 text-slate-300 hover:bg-slate-700"
                    onClick={() =>
                      navigator.clipboard.writeText("read:user,user:email")
                    }
                  >
                    Copy scopes
                  </button>
                </p>
                <a
                  href="https://github.com/settings/tokens"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-blue-400 hover:underline"
                >
                  Generate a new token here.
                </a>
                <p>
                  Or you can use a short-lived token generated by the gh CLI.
                  Note: these tokens typically expire in one hour.
                </p>
                <p>
                  Run the following command:{" "}
                  <code className="text-xs bg-slate-700 p-1 rounded">
                    gh auth token
                  </code>
                  <button
                    type="button"
                    className="ml-2 text-[11px] px-2 py-0.5 rounded border border-slate-600 text-slate-300 hover:bg-slate-700"
                    onClick={() =>
                      navigator.clipboard.writeText("gh auth token")
                    }
                  >
                    Copy
                  </button>
                </p>
              </div>
              <div className="space-y-3 mt-4">
                <label
                  htmlFor="pat-input"
                  className="block text-sm font-medium text-slate-300"
                >
                  Personal Access Token (PAT)
                </label>
                <div className="relative">
                  <input
                    id="pat-input"
                    type={showPat ? "text" : "password"}
                    value={pat}
                    onChange={(e) => setPat(e.target.value)}
                    placeholder="ghp_..."
                    className="w-full pr-12 px-4 py-2 bg-slate-900 border border-slate-700 rounded-md text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-green-500 transition-colors"
                  />
                  <button
                    type="button"
                    onClick={() => setShowPat((v) => !v)}
                    className="absolute right-2 top-1.5 text-xs px-2 py-0.5 rounded border border-slate-600 text-slate-400 hover:text-slate-200 hover:bg-slate-700"
                  >
                    {showPat ? "Hide" : "Show"}
                  </button>
                </div>
              </div>
              <div className="mt-6">
                <button
                  onClick={() => onPatLogin(pat)}
                  disabled={!pat || isLoading}
                  className="w-full inline-flex items-center justify-center px-6 py-3 border border-transparent text-base font-medium rounded-md shadow-sm text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500 disabled:bg-slate-600/50 disabled:cursor-not-allowed transition-all"
                >
                  <GithubIcon className="h-5 w-5 mr-2" />
                  Fetch with GitHub Token
                </button>
              </div>
            </div>

            {/* Hosted GitHub OAuth */}
            <div className="mt-10 pt-8 border-t border-slate-700 space-y-4">
              <h3 className="text-center text-lg font-medium text-slate-300 mb-4">
                Or use our GitHub App
              </h3>
              <div className="text-slate-400 space-y-2 text-sm bg-slate-900/50 p-4 rounded-lg border border-slate-700">
                <p>
                  Use our hosted GitHub OAuth app - no setup required! Just
                  click the button below to authenticate with GitHub.
                </p>
                <p className="text-slate-500">
                  This option uses our pre-configured OAuth application for your
                  convenience.
                </p>
              </div>
              <div className="mt-6">
                <button
                  onClick={() => onHostedOAuthLogin("github", githubScopes)}
                  disabled={isLoading || !isHostedAvailable("github")}
                  className="w-full inline-flex items-center justify-center px-6 py-3 border border-transparent text-base font-medium rounded-md shadow-sm text-white bg-purple-600 hover:bg-purple-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-purple-500 transition-all"
                >
                  <GithubIcon className="h-5 w-5 mr-2" />
                  Sign in with Hosted GitHub App
                </button>
                {!isHostedAvailable("github") && (
                  <p className="mt-2 text-xs text-slate-400 text-center">
                    Hosted app coming later.
                  </p>
                )}
              </div>
            </div>
          </div>
        </Tab>

        <Tab label="Google" icon={<GoogleIcon />}>
          <div className="space-y-8">
            {/* Google OAuth */}
            <div className="bg-slate-900/50 p-6 rounded-lg border border-slate-700 space-y-4">
              <div className="flex items-center mb-4">
                <GoogleIcon className="h-8 w-8" />
                <h2 className="ml-3 text-xl font-semibold text-white">
                  Sign in with Google OAuth
                </h2>
              </div>
              <p className="text-sm text-slate-400 mb-2">
                Create OAuth credentials in the{" "}
                <a
                  href="https://console.developers.google.com/apis/credentials"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-blue-400 hover:underline"
                >
                  Google API Console
                </a>
                . Under "Authorized redirect URIs", add:
              </p>
              <div className="flex gap-2 mb-3">
                <a
                  href="https://console.developers.google.com/apis/credentials"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-2 px-3 py-1.5 text-xs rounded-md border border-slate-600 text-slate-300 bg-slate-800/70 hover:bg-slate-700"
                >
                  <GoogleIcon className="w-4 h-4" /> Open Google Credentials
                </a>
              </div>
              <div className="flex items-center justify-between text-sm bg-slate-700 p-2 rounded-md mb-4">
                <code className="text-xs text-slate-300 truncate">
                  {getEffectiveRedirectUri(customRedirectUri)}
                </code>
                <button
                  onClick={() => handleCopy("google")}
                  className="p-1 text-slate-400 hover:text-white focus:outline-none focus:ring-2 focus:ring-slate-500 rounded transition-colors"
                  aria-label="Copy redirect URL"
                >
                  {copiedProvider === "google" ? (
                    <ClipboardCheckIcon className="h-5 w-5 text-green-400" />
                  ) : (
                    <ClipboardIcon className="h-5 w-5" />
                  )}
                </button>
              </div>
              <div className="space-y-3">
                <div>
                  <label
                    htmlFor="google-client-id"
                    className="block text-sm font-medium text-slate-300"
                  >
                    Google OAuth App Client ID
                  </label>
                  <input
                    id="google-client-id"
                    type="text"
                    value={googleClientId}
                    onChange={(e) => setGoogleClientId(e.target.value)}
                    placeholder="Enter your Google Client ID"
                    className="w-full mt-1 px-4 py-2 bg-slate-900 border border-slate-700 rounded-md text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-500 transition-colors"
                  />
                </div>
                <div>
                  <label
                    htmlFor="google-client-secret"
                    className="block text-sm font-medium text-slate-300"
                  >
                    Google OAuth App Client Secret
                  </label>
                  <div className="relative">
                    <input
                      id="google-client-secret"
                      type={showGoogleSecret ? "text" : "password"}
                      value={googleClientSecret}
                      onChange={(e) => setGoogleClientSecret(e.target.value)}
                      placeholder="Enter your Google Client Secret"
                      className="w-full mt-1 pr-12 px-4 py-2 bg-slate-900 border border-slate-700 rounded-md text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-500 transition-colors"
                    />
                    <button
                      type="button"
                      onClick={() => setShowGoogleSecret((v) => !v)}
                      className="absolute right-2 top-1.5 text-xs px-2 py-0.5 rounded border border-slate-600 text-slate-400 hover:text-slate-200 hover:bg-slate-700"
                    >
                      {showGoogleSecret ? "Hide" : "Show"}
                    </button>
                  </div>
                </div>
                <ScopeSelector
                  provider="google"
                  onScopeChange={setGoogleScopes}
                />
              </div>
              <div className="mt-6">
                <button
                  onClick={() =>
                    onOAuthLogin(
                      "google",
                      googleClientId,
                      googleClientSecret,
                      undefined,
                      googleScopes,
                    )
                  }
                  disabled={!googleClientId || !googleClientSecret || isLoading}
                  className="w-full inline-flex items-center justify-center px-6 py-3 border border-transparent text-base font-medium rounded-md shadow-sm text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:bg-slate-600/50 disabled:cursor-not-allowed transition-all"
                >
                  <GoogleIcon className="h-5 w-5 mr-2" />
                  Continue with Google
                </button>
              </div>
            </div>

            {/* Google gcloud Token */}
            <div className="mt-10 pt-8 border-t border-slate-700 space-y-4">
              <h3 className="text-center text-lg font-medium text-slate-300 mb-4">
                Or use a Google CLI Token
              </h3>
              <div className="text-slate-400 space-y-2 text-sm bg-slate-900/50 p-4 rounded-lg border border-slate-700">
                <p>
                  You can use a short-lived token generated by the gcloud CLI.
                  Note: these tokens typically expire in one hour.
                </p>
                <p>
                  Run the following command:{" "}
                  <code className="text-xs bg-slate-700 p-1 rounded">
                    gcloud auth print-access-token
                  </code>
                  <button
                    type="button"
                    className="ml-2 text-[11px] px-2 py-0.5 rounded border border-slate-600 text-slate-300 hover:bg-slate-700"
                    onClick={() =>
                      navigator.clipboard.writeText(
                        "gcloud auth print-access-token",
                      )
                    }
                  >
                    Copy
                  </button>
                </p>
              </div>
              <div className="space-y-3 mt-4">
                <label
                  htmlFor="gcloud-token-input"
                  className="block text-sm font-medium text-slate-300"
                >
                  Google CLI Access Token
                </label>
                <textarea
                  id="gcloud-token-input"
                  rows={3}
                  value={gcloudToken}
                  onChange={(e) => setGcloudToken(e.target.value)}
                  placeholder="ya29..."
                  className="w-full px-4 py-2 bg-slate-900 border border-slate-700 rounded-md text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-500 transition-colors font-mono text-sm"
                />
              </div>
              <div className="mt-6">
                <button
                  onClick={() => onGcloudTokenLogin(gcloudToken)}
                  disabled={!gcloudToken || isLoading}
                  className="w-full inline-flex items-center justify-center px-6 py-3 border border-transparent text-base font-medium rounded-md shadow-sm text-white bg-slate-600 hover:bg-slate-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-slate-500 disabled:bg-slate-600/50 disabled:cursor-not-allowed transition-all"
                >
                  <GoogleIcon className="h-5 w-5 mr-2" />
                  Fetch with Google Token
                </button>
              </div>
            </div>

            {/* Hosted Google OAuth */}
            <div className="mt-10 pt-8 border-t border-slate-700 space-y-4">
              <h3 className="text-center text-lg font-medium text-slate-300 mb-4">
                Or use our Google App
              </h3>
              <div className="text-slate-400 space-y-2 text-sm bg-slate-900/50 p-4 rounded-lg border border-slate-700">
                <p>
                  Use our hosted Google OAuth app - no setup required! Just
                  click the button below to authenticate with Google.
                </p>
                <p className="text-slate-500">
                  This option uses our pre-configured OAuth application for your
                  convenience.
                </p>
              </div>
              <div className="mt-6">
                <button
                  onClick={() => onHostedOAuthLogin("google", googleScopes)}
                  disabled={isLoading || !isHostedAvailable("google")}
                  className="w-full inline-flex items-center justify-center px-6 py-3 border border-transparent text-base font-medium rounded-md shadow-sm text-white bg-purple-600 hover:bg-purple-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-purple-500 transition-all"
                >
                  <GoogleIcon className="h-5 w-5 mr-2" />
                  Sign in with Hosted Google App
                </button>
                {!isHostedAvailable("google") && (
                  <p className="mt-2 text-xs text-slate-400 text-center">
                    Hosted app coming later.
                  </p>
                )}
              </div>
            </div>
          </div>
        </Tab>

        <Tab label="GitLab" icon={<GitLabIcon />}>
          <div className="space-y-8">
            {/* GitLab OAuth */}
            <div className="bg-slate-900/50 p-6 rounded-lg border border-slate-700 space-y-4">
              <div className="flex items-center mb-4">
                <GitLabIcon className="h-8 w-8" />
                <h2 className="ml-3 text-xl font-semibold text-white">
                  Sign in with GitLab OAuth
                </h2>
              </div>
              <p className="text-sm text-slate-400 mb-2">
                Create an{" "}
                <a
                  href="https://gitlab.com/-/profile/applications"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-blue-400 hover:underline"
                >
                  Application
                </a>{" "}
                and set the "Redirect URI" to:
              </p>
              <div className="flex gap-2 mb-3">
                <a
                  href="https://gitlab.com/-/profile/applications"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-2 px-3 py-1.5 text-xs rounded-md border border-slate-600 text-slate-300 bg-slate-800/70 hover:bg-slate-700"
                >
                  <GitLabIcon className="w-4 h-4" /> Open GitLab Applications
                </a>
              </div>
              <div className="flex items-center justify-between text-sm bg-slate-700 p-2 rounded-md mb-4">
                <code className="text-xs text-slate-300 truncate">
                  {getEffectiveRedirectUri(customRedirectUri)}
                </code>
                <button
                  onClick={() => handleCopy("gitlab")}
                  className="p-1 text-slate-400 hover:text-white focus:outline-none focus:ring-2 focus:ring-slate-500 rounded transition-colors"
                  aria-label="Copy redirect URL"
                >
                  {copiedProvider === "gitlab" ? (
                    <ClipboardCheckIcon className="h-5 w-5 text-green-400" />
                  ) : (
                    <ClipboardIcon className="h-5 w-5" />
                  )}
                </button>
              </div>
              <div className="space-y-3">
                <div>
                  <label
                    htmlFor="gitlab-client-id"
                    className="block text-sm font-medium text-slate-300"
                  >
                    GitLab Application ID
                  </label>
                  <input
                    id="gitlab-client-id"
                    type="text"
                    value={gitlabClientId}
                    onChange={(e) => setGitlabClientId(e.target.value)}
                    placeholder="Enter your GitLab Application ID"
                    className="w-full mt-1 px-4 py-2 bg-slate-900 border border-slate-700 rounded-md text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-500 transition-colors"
                  />
                </div>
                <div>
                  <label
                    htmlFor="gitlab-client-secret"
                    className="block text-sm font-medium text-slate-300"
                  >
                    GitLab Secret
                  </label>
                  <div className="relative">
                    <input
                      id="gitlab-client-secret"
                      type={showGitlabSecret ? "text" : "password"}
                      value={gitlabClientSecret}
                      onChange={(e) => setGitlabClientSecret(e.target.value)}
                      placeholder="Enter your GitLab Secret"
                      className="w-full mt-1 pr-12 px-4 py-2 bg-slate-900 border border-slate-700 rounded-md text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-500 transition-colors"
                    />
                    <button
                      type="button"
                      onClick={() => setShowGitlabSecret((v) => !v)}
                      className="absolute right-2 top-1.5 text-xs px-2 py-0.5 rounded border border-slate-600 text-slate-400 hover:text-slate-200 hover:bg-slate-700"
                    >
                      {showGitlabSecret ? "Hide" : "Show"}
                    </button>
                  </div>
                </div>
                <ScopeSelector
                  provider="gitlab"
                  onScopeChange={setGitlabScopes}
                />
              </div>
              <div className="mt-6">
                <button
                  onClick={() =>
                    onOAuthLogin(
                      "gitlab",
                      gitlabClientId,
                      gitlabClientSecret,
                      undefined,
                      gitlabScopes,
                    )
                  }
                  disabled={!gitlabClientId || !gitlabClientSecret || isLoading}
                  className="w-full inline-flex items-center justify-center px-6 py-3 border border-transparent text-base font-medium rounded-md shadow-sm text-white bg-orange-600 hover:bg-orange-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-orange-500 disabled:bg-slate-600/50 disabled:cursor-not-allowed transition-all"
                >
                  <GitLabIcon className="h-5 w-5 mr-2" />
                  Continue with GitLab
                </button>
              </div>
            </div>

            {/* Hosted GitLab OAuth */}
            <div className="mt-10 pt-8 border-t border-slate-700 space-y-4">
              <h3 className="text-center text-lg font-medium text-slate-300 mb-4">
                Or use our GitLab App
              </h3>
              <div className="text-slate-400 space-y-2 text-sm bg-slate-900/50 p-4 rounded-lg border border-slate-700">
                <p>
                  Use our hosted GitLab OAuth app - no setup required! Just
                  click the button below to authenticate with GitLab.
                </p>
                <p className="text-slate-500">
                  This option uses our pre-configured OAuth application for your
                  convenience.
                </p>
              </div>
              <div className="mt-6">
                <button
                  onClick={() => onHostedOAuthLogin("gitlab", gitlabScopes)}
                  disabled={isLoading || !isHostedAvailable("gitlab")}
                  className="w-full inline-flex items-center justify-center px-6 py-3 border border-transparent text-base font-medium rounded-md shadow-sm text-white bg-purple-600 hover:bg-purple-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-purple-500 transition-all"
                >
                  <GitLabIcon className="h-5 w-5 mr-2" />
                  Sign in with Hosted GitLab App
                </button>
                {!isHostedAvailable("gitlab") && (
                  <p className="mt-2 text-xs text-slate-400 text-center">
                    Hosted app coming later.
                  </p>
                )}
              </div>
            </div>
          </div>
        </Tab>

        <Tab label="Auth0" icon={<Auth0Icon />}>
          <div className="space-y-8">
            {/* Auth0 OAuth */}
            <div className="bg-slate-900/50 p-6 rounded-lg border border-slate-700 space-y-4">
              <div className="flex items-center mb-4">
                <Auth0Icon className="h-8 w-8" />
                <h2 className="ml-3 text-xl font-semibold text-white">
                  Sign in with Auth0 OAuth
                </h2>
              </div>
              <p className="text-sm text-slate-400 mb-2">
                Create an{" "}
                <a
                  href="https://manage.auth0.com/"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-blue-400 hover:underline"
                >
                  Application
                </a>{" "}
                in your Auth0 dashboard and set the "Allowed Callback URLs" to:
              </p>
              <div className="flex gap-2 mb-3">
                <a
                  href="https://manage.auth0.com/"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-2 px-3 py-1.5 text-xs rounded-md border border-slate-600 text-slate-300 bg-slate-800/70 hover:bg-slate-700"
                >
                  <Auth0Icon className="w-4 h-4" /> Open Auth0 Dashboard
                </a>
              </div>
              <div className="flex items-center justify-between text-sm bg-slate-700 p-2 rounded-md mb-4">
                <code className="text-xs text-slate-300 truncate">
                  {getEffectiveRedirectUri(customRedirectUri)}
                </code>
                <button
                  onClick={() => handleCopy("auth0")}
                  className="p-1 text-slate-400 hover:text-white focus:outline-none focus:ring-2 focus:ring-slate-500 rounded transition-colors"
                  aria-label="Copy redirect URL"
                >
                  {copiedProvider === "auth0" ? (
                    <ClipboardCheckIcon className="h-5 w-5 text-green-400" />
                  ) : (
                    <ClipboardIcon className="h-5 w-5" />
                  )}
                </button>
              </div>
              <div className="space-y-3">
                <div>
                  <label
                    htmlFor="auth0-domain"
                    className="block text-sm font-medium text-slate-300"
                  >
                    Auth0 Domain
                  </label>
                  <input
                    id="auth0-domain"
                    type="text"
                    value={auth0Domain}
                    onChange={(e) => setAuth0Domain(e.target.value)}
                    placeholder="your-tenant.us.auth0.com"
                    className="w-full mt-1 px-4 py-2 bg-slate-900 border border-slate-700 rounded-md text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-500 transition-colors"
                  />
                </div>
                <div>
                  <label
                    htmlFor="auth0-client-id"
                    className="block text-sm font-medium text-slate-300"
                  >
                    Auth0 Client ID
                  </label>
                  <input
                    id="auth0-client-id"
                    type="text"
                    value={auth0ClientId}
                    onChange={(e) => setAuth0ClientId(e.target.value)}
                    placeholder="Enter your Auth0 Client ID"
                    className="w-full mt-1 px-4 py-2 bg-slate-900 border border-slate-700 rounded-md text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-500 transition-colors"
                  />
                </div>
                <div>
                  <label
                    htmlFor="auth0-client-secret"
                    className="block text-sm font-medium text-slate-300"
                  >
                    Auth0 Client Secret
                  </label>
                  <div className="relative">
                    <input
                      id="auth0-client-secret"
                      type={showAuth0Secret ? "text" : "password"}
                      value={auth0ClientSecret}
                      onChange={(e) => setAuth0ClientSecret(e.target.value)}
                      placeholder="Enter your Auth0 Client Secret"
                      className="w-full mt-1 pr-12 px-4 py-2 bg-slate-900 border border-slate-700 rounded-md text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-500 transition-colors"
                    />
                    <button
                      type="button"
                      onClick={() => setShowAuth0Secret((v) => !v)}
                      className="absolute right-2 top-1.5 text-xs px-2 py-0.5 rounded border border-slate-600 text-slate-400 hover:text-slate-200 hover:bg-slate-700"
                    >
                      {showAuth0Secret ? "Hide" : "Show"}
                    </button>
                  </div>
                </div>
                <ScopeSelector
                  provider="auth0"
                  onScopeChange={setAuth0Scopes}
                />
              </div>
              <div className="mt-6">
                <button
                  onClick={() =>
                    onOAuthLogin(
                      "auth0",
                      auth0ClientId,
                      auth0ClientSecret,
                      auth0Domain,
                      auth0Scopes,
                    )
                  }
                  disabled={
                    !auth0ClientId ||
                    !auth0ClientSecret ||
                    !auth0Domain ||
                    isLoading
                  }
                  className="w-full inline-flex items-center justify-center px-6 py-3 border border-transparent text-base font-medium rounded-md shadow-sm text-white bg-red-600 hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500 disabled:bg-slate-600/50 disabled:cursor-not-allowed transition-all"
                >
                  <Auth0Icon className="h-5 w-5 mr-2" />
                  Continue with Auth0
                </button>
              </div>
            </div>

            {/* Hosted Auth0 OAuth */}
            <div className="mt-10 pt-8 border-t border-slate-700 space-y-4">
              <h3 className="text-center text-lg font-medium text-slate-300 mb-4">
                Or use our Auth0 App
              </h3>
              <div className="text-slate-400 space-y-2 text-sm bg-slate-900/50 p-4 rounded-lg border border-slate-700">
                <p>
                  Use our hosted Auth0 OAuth app - no setup required! Just click
                  the button below to authenticate with Auth0.
                </p>
                <p className="text-slate-500">
                  This option uses our pre-configured OAuth application for your
                  convenience.
                </p>
              </div>
              <div className="mt-6">
                <button
                  onClick={() => onHostedOAuthLogin("auth0", auth0Scopes)}
                  disabled={isLoading || !isHostedAvailable("auth0")}
                  className="w-full inline-flex items-center justify-center px-6 py-3 border border-transparent text-base font-medium rounded-md shadow-sm text-white bg-purple-600 hover:bg-purple-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-purple-500 transition-all"
                >
                  <Auth0Icon className="h-5 w-5 mr-2" />
                  Sign in with Hosted Auth0 App
                </button>
                {!isHostedAvailable("auth0") && (
                  <p className="mt-2 text-xs text-slate-400 text-center">
                    Hosted app coming later.
                  </p>
                )}
              </div>
            </div>
          </div>
        </Tab>

        <Tab label="LinkedIn" icon={<LinkedInIcon />}>
          <div className="space-y-8">
            {/* LinkedIn OAuth */}
            <div className="bg-slate-900/50 p-6 rounded-lg border border-slate-700 space-y-4">
              <div className="flex items-center mb-4">
                <LinkedInIcon className="h-8 w-8" />
                <h2 className="ml-3 text-xl font-semibold text-white">
                  Sign in with LinkedIn OAuth
                </h2>
              </div>
              <p className="text-sm text-slate-400 mb-2">
                Create an{" "}
                <a
                  href="https://www.linkedin.com/developers/apps"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-blue-400 hover:underline"
                >
                  App
                </a>{" "}
                and set the "Authorized redirect URLs" to:
              </p>
              <div className="flex gap-2 mb-3">
                <a
                  href="https://www.linkedin.com/developers/apps"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-2 px-3 py-1.5 text-xs rounded-md border border-slate-600 text-slate-300 bg-slate-800/70 hover:bg-slate-700"
                >
                  <LinkedInIcon className="w-4 h-4" /> Open LinkedIn Apps
                </a>
              </div>
              <div className="flex items-center justify-between text-sm bg-slate-700 p-2 rounded-md mb-4">
                <code className="text-xs text-slate-300 truncate">
                  {getEffectiveRedirectUri(customRedirectUri)}
                </code>
                <button
                  onClick={() => handleCopy("linkedin")}
                  className="p-1 text-slate-400 hover:text-white focus:outline-none focus:ring-2 focus:ring-slate-500 rounded transition-colors"
                  aria-label="Copy redirect URL"
                >
                  {copiedProvider === "linkedin" ? (
                    <ClipboardCheckIcon className="h-5 w-5 text-green-400" />
                  ) : (
                    <ClipboardIcon className="h-5 w-5" />
                  )}
                </button>
              </div>
              <div className="space-y-3">
                <div>
                  <label
                    htmlFor="linkedin-client-id"
                    className="block text-sm font-medium text-slate-300"
                  >
                    LinkedIn Client ID
                  </label>
                  <input
                    id="linkedin-client-id"
                    type="text"
                    value={linkedinClientId}
                    onChange={(e) => setLinkedinClientId(e.target.value)}
                    placeholder="Enter your LinkedIn Client ID"
                    className="w-full mt-1 px-4 py-2 bg-slate-900 border border-slate-700 rounded-md text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-500 transition-colors"
                  />
                </div>
                <div>
                  <label
                    htmlFor="linkedin-client-secret"
                    className="block text-sm font-medium text-slate-300"
                  >
                    LinkedIn Client Secret
                  </label>
                  <div className="relative">
                    <input
                      id="linkedin-client-secret"
                      type={showLinkedinSecret ? "text" : "password"}
                      value={linkedinClientSecret}
                      onChange={(e) => setLinkedinClientSecret(e.target.value)}
                      placeholder="Enter your LinkedIn Client Secret"
                      className="w-full mt-1 pr-12 px-4 py-2 bg-slate-900 border border-slate-700 rounded-md text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-500 transition-colors"
                    />
                    <button
                      type="button"
                      onClick={() => setShowLinkedinSecret((v) => !v)}
                      className="absolute right-2 top-1.5 text-xs px-2 py-0.5 rounded border border-slate-600 text-slate-400 hover:text-slate-200 hover:bg-slate-700"
                    >
                      {showLinkedinSecret ? "Hide" : "Show"}
                    </button>
                  </div>
                </div>
                <ScopeSelector
                  provider="linkedin"
                  onScopeChange={setLinkedinScopes}
                />
              </div>
              <div className="mt-6">
                <button
                  onClick={() =>
                    onOAuthLogin(
                      "linkedin",
                      linkedinClientId,
                      linkedinClientSecret,
                      undefined,
                      linkedinScopes,
                    )
                  }
                  disabled={
                    !linkedinClientId || !linkedinClientSecret || isLoading
                  }
                  className="w-full inline-flex items-center justify-center px-6 py-3 border border-transparent text-base font-medium rounded-md shadow-sm text-white bg-blue-700 hover:bg-blue-800 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:bg-slate-600/50 disabled:cursor-not-allowed transition-all"
                >
                  <LinkedInIcon className="h-5 w-5 mr-2" />
                  Continue with LinkedIn
                </button>
              </div>
            </div>

            {/* Hosted LinkedIn OAuth */}
            <div className="mt-10 pt-8 border-t border-slate-700 space-y-4">
              <h3 className="text-center text-lg font-medium text-slate-300 mb-4">
                Or use our LinkedIn App
              </h3>
              <div className="text-slate-400 space-y-2 text-sm bg-slate-900/50 p-4 rounded-lg border border-slate-700">
                <p>
                  Use our hosted LinkedIn OAuth app - no setup required! Just
                  click the button below to authenticate with LinkedIn.
                </p>
                <p className="text-slate-500">
                  This option uses our pre-configured OAuth application for your
                  convenience.
                </p>
              </div>
              <div className="mt-6">
                <button
                  onClick={() => onHostedOAuthLogin("linkedin", linkedinScopes)}
                  disabled={isLoading || !isHostedAvailable("linkedin")}
                  className="w-full inline-flex items-center justify-center px-6 py-3 border border-transparent text-base font-medium rounded-md shadow-sm text-white bg-purple-600 hover:bg-purple-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-purple-500 transition-all"
                >
                  <LinkedInIcon className="h-5 w-5 mr-2" />
                  Sign in with Hosted LinkedIn App
                </button>
                {!isHostedAvailable("linkedin") && (
                  <p className="mt-2 text-xs text-slate-400 text-center">
                    Hosted app coming later.
                  </p>
                )}
              </div>
            </div>
          </div>
        </Tab>
      </Tabs>
    </div>
  );
};

export default LoginScreen;
