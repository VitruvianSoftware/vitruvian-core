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
import {
  Button,
  Field,
  Input,
  Tag,
  Banner,
  Code,
  Rule,
  Textarea,
  Plate,
} from "../design-system";
import { AuthProvider } from "../types";
import {
  GithubIcon,
  GoogleIcon,
  GitLabIcon,
  Auth0Icon,
  ZitadelIcon,
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
    domain?: string,
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
  const [zitadelClientId, setZitadelClientId] = useState("");
  const [zitadelClientSecret, setZitadelClientSecret] = useState("");
  const [zitadelDomain, setZitadelDomain] = useState("auth.ipv1337.dev");
  const [zitadelScopes, setZitadelScopes] = useState("");
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
  const [showZitadelSecret, setShowZitadelSecret] = useState(false);
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
          setZitadelClientId(obj.client_id || obj.clientId);
          setLinkedinClientId(obj.client_id || obj.clientId);
        }
        if (obj.client_secret || obj.clientSecret) {
          setGithubClientSecret(obj.client_secret || obj.clientSecret);
          setGitlabClientSecret(obj.client_secret || obj.clientSecret);
          setAuth0ClientSecret(obj.client_secret || obj.clientSecret);
          setZitadelClientSecret(obj.client_secret || obj.clientSecret);
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
        if (obj.zitadel_client_id) setZitadelClientId(obj.zitadel_client_id);
        if (obj.zitadel_client_secret)
          setZitadelClientSecret(obj.zitadel_client_secret);
        if (obj.zitadel_domain) setZitadelDomain(obj.zitadel_domain);
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
    <Plate
      className="bg-slate-800 p-8 rounded-xl shadow-2xl ring-1 ring-white/10 w-full max-w-2xl mx-auto transition-all duration-300"
      onPaste={handleCardPaste}
    >
      {toast && (
        <Banner tone="info" className="mb-3">
          {toast}
        </Banner>
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
            <Input
              className="flex-1"
              type="text"
              value={customRedirectUri}
              onChange={(e) => onCustomRedirectUriChange?.(e.target.value)}
              placeholder={getRedirectUri()}
            />
            <Button
              variant="ghost"
              size="sm"
              onClick={() => onCustomRedirectUriChange?.("")}
            >
              Reset
            </Button>
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
                  className="inline-flex items-center gap-2 px-3 py-1.5 text-xs rounded-md border border-slate-600 text-slate-300 bg-ink-2/70 hover:bg-slate-700"
                >
                  <GithubIcon className="w-4 h-4" /> Open GitHub OAuth settings
                </a>
              </div>
              <div className="flex items-center justify-between text-sm bg-slate-700 p-2 rounded-md mb-4">
                <Code>{getEffectiveRedirectUri(customRedirectUri)}</Code>
                <Button
                  variant="ghost"
                  size="sm"
                  icon
                  onClick={() => handleCopy("github")}
                  aria-label="Copy redirect URL"
                >
                  {copiedProvider === "github" ? (
                    <ClipboardCheckIcon className="h-5 w-5 text-green-400" />
                  ) : (
                    <ClipboardIcon className="h-5 w-5" />
                  )}
                </Button>
              </div>
              <div className="space-y-3">
                <Field label="GitHub OAuth App Client ID">
                  <Input
                    id="github-client-id"
                    type="text"
                    value={githubClientId}
                    onChange={(e) => setGithubClientId(e.target.value)}
                    placeholder="Enter your GitHub Client ID"
                  />
                </Field>
                <Field label="GitHub OAuth App Client Secret">
                  <div className="relative">
                    <Input
                      id="github-client-secret"
                      type={showGithubSecret ? "text" : "password"}
                      value={githubClientSecret}
                      onChange={(e) => setGithubClientSecret(e.target.value)}
                      placeholder="Enter your GitHub Client Secret"
                    />
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => setShowGithubSecret((v) => !v)}
                      className="absolute right-2 top-1/2 -translate-y-1/2"
                    >
                      {showGithubSecret ? "Hide" : "Show"}
                    </Button>
                  </div>
                </Field>
                <ScopeSelector
                  provider="github"
                  onScopeChange={setGithubScopes}
                />
              </div>
              <div className="mt-6">
                <Button
                  variant="primary"
                  block
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
                  className="inline-flex items-center justify-center"
                >
                  <GithubIcon className="h-5 w-5 mr-2" />
                  Continue with GitHub
                </Button>
              </div>
            </div>

            {/* GitHub PAT */}
            <div className="mt-10 pt-8 space-y-4">
              <Rule className="mb-8" />
              <h3 className="text-center text-lg font-medium text-slate-300 mb-4">
                Or use a GitHub Token
              </h3>
              <div className="text-slate-400 space-y-2 text-sm bg-slate-900/50 p-4 rounded-lg border border-slate-700">
                <p>
                  You can use a classic or fine-grained PAT. The token needs the{" "}
                  <Code>read:user</Code> and <Code>user:email</Code> scopes.
                  <Button
                    variant="ghost"
                    size="sm"
                    className="ml-2"
                    onClick={() =>
                      navigator.clipboard.writeText("read:user,user:email")
                    }
                  >
                    Copy scopes
                  </Button>
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
                  Run the following command: <Code>gh auth token</Code>
                  <Button
                    variant="ghost"
                    size="sm"
                    className="ml-2"
                    onClick={() =>
                      navigator.clipboard.writeText("gh auth token")
                    }
                  >
                    Copy
                  </Button>
                </p>
              </div>
              <Field label="Personal Access Token (PAT)">
                <div className="relative">
                  <Input
                    id="pat-input"
                    type={showPat ? "text" : "password"}
                    value={pat}
                    onChange={(e) => setPat(e.target.value)}
                    placeholder="ghp_..."
                  />
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => setShowPat((v) => !v)}
                    className="absolute right-2 top-1/2 -translate-y-1/2"
                  >
                    {showPat ? "Hide" : "Show"}
                  </Button>
                </div>
              </Field>
              <div className="mt-6">
                <Button
                  variant="primary"
                  block
                  onClick={() => onPatLogin(pat)}
                  disabled={!pat || isLoading}
                  className="inline-flex items-center justify-center"
                >
                  <GithubIcon className="h-5 w-5 mr-2" />
                  Fetch with GitHub Token
                </Button>
              </div>
            </div>

            {/* Hosted GitHub OAuth */}
            <div className="mt-10 pt-8 space-y-4">
              <Rule className="mb-8" />
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
                <Button
                  variant="primary"
                  block
                  onClick={() => onHostedOAuthLogin("github", githubScopes)}
                  disabled={isLoading || !isHostedAvailable("github")}
                  className="inline-flex items-center justify-center"
                >
                  <GithubIcon className="h-5 w-5 mr-2" />
                  Sign in with Hosted GitHub App
                </Button>
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
                  className="inline-flex items-center gap-2 px-3 py-1.5 text-xs rounded-md border border-slate-600 text-slate-300 bg-ink-2/70 hover:bg-slate-700"
                >
                  <GoogleIcon className="w-4 h-4" /> Open Google Credentials
                </a>
              </div>
              <div className="flex items-center justify-between text-sm bg-slate-700 p-2 rounded-md mb-4">
                <Code>{getEffectiveRedirectUri(customRedirectUri)}</Code>
                <Button
                  variant="ghost"
                  size="sm"
                  icon
                  onClick={() => handleCopy("google")}
                  aria-label="Copy redirect URL"
                >
                  {copiedProvider === "google" ? (
                    <ClipboardCheckIcon className="h-5 w-5 text-green-400" />
                  ) : (
                    <ClipboardIcon className="h-5 w-5" />
                  )}
                </Button>
              </div>
              <div className="space-y-3">
                <Field label="Google OAuth App Client ID">
                  <Input
                    id="google-client-id"
                    type="text"
                    value={googleClientId}
                    onChange={(e) => setGoogleClientId(e.target.value)}
                    placeholder="Enter your Google Client ID"
                  />
                </Field>
                <Field label="Google OAuth App Client Secret">
                  <div className="relative">
                    <Input
                      id="google-client-secret"
                      type={showGoogleSecret ? "text" : "password"}
                      value={googleClientSecret}
                      onChange={(e) => setGoogleClientSecret(e.target.value)}
                      placeholder="Enter your Google Client Secret"
                    />
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => setShowGoogleSecret((v) => !v)}
                      className="absolute right-2 top-1/2 -translate-y-1/2"
                    >
                      {showGoogleSecret ? "Hide" : "Show"}
                    </Button>
                  </div>
                </Field>
                <ScopeSelector
                  provider="google"
                  onScopeChange={setGoogleScopes}
                />
              </div>
              <div className="mt-6">
                <Button
                  variant="primary"
                  block
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
                  className="inline-flex items-center justify-center"
                >
                  <GoogleIcon className="h-5 w-5 mr-2" />
                  Continue with Google
                </Button>
              </div>
            </div>

            {/* Google gcloud Token */}
            <div className="mt-10 pt-8 space-y-4">
              <Rule className="mb-8" />
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
                  <Code>gcloud auth print-access-token</Code>
                  <Button
                    variant="ghost"
                    size="sm"
                    className="ml-2"
                    onClick={() =>
                      navigator.clipboard.writeText(
                        "gcloud auth print-access-token",
                      )
                    }
                  >
                    Copy
                  </Button>
                </p>
              </div>
              <Field label="Google CLI Access Token">
                <Textarea
                  id="gcloud-token-input"
                  rows={3}
                  value={gcloudToken}
                  onChange={(e) => setGcloudToken(e.target.value)}
                  placeholder="ya29..."
                />
              </Field>
              <div className="mt-6">
                <Button
                  variant="primary"
                  block
                  onClick={() => onGcloudTokenLogin(gcloudToken)}
                  disabled={!gcloudToken || isLoading}
                  className="inline-flex items-center justify-center"
                >
                  <GoogleIcon className="h-5 w-5 mr-2" />
                  Fetch with Google Token
                </Button>
              </div>
            </div>

            {/* Hosted Google OAuth */}
            <div className="mt-10 pt-8 space-y-4">
              <Rule className="mb-8" />
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
                <Button
                  variant="primary"
                  block
                  onClick={() => onHostedOAuthLogin("google", googleScopes)}
                  disabled={isLoading || !isHostedAvailable("google")}
                  className="inline-flex items-center justify-center"
                >
                  <GoogleIcon className="h-5 w-5 mr-2" />
                  Sign in with Hosted Google App
                </Button>
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
                  className="inline-flex items-center gap-2 px-3 py-1.5 text-xs rounded-md border border-slate-600 text-slate-300 bg-ink-2/70 hover:bg-slate-700"
                >
                  <GitLabIcon className="w-4 h-4" /> Open GitLab Applications
                </a>
              </div>
              <div className="flex items-center justify-between text-sm bg-slate-700 p-2 rounded-md mb-4">
                <Code>{getEffectiveRedirectUri(customRedirectUri)}</Code>
                <Button
                  variant="ghost"
                  size="sm"
                  icon
                  onClick={() => handleCopy("gitlab")}
                  aria-label="Copy redirect URL"
                >
                  {copiedProvider === "gitlab" ? (
                    <ClipboardCheckIcon className="h-5 w-5 text-green-400" />
                  ) : (
                    <ClipboardIcon className="h-5 w-5" />
                  )}
                </Button>
              </div>
              <div className="space-y-3">
                <Field label="GitLab Application ID">
                  <Input
                    id="gitlab-client-id"
                    type="text"
                    value={gitlabClientId}
                    onChange={(e) => setGitlabClientId(e.target.value)}
                    placeholder="Enter your GitLab Application ID"
                  />
                </Field>
                <Field label="GitLab Secret">
                  <div className="relative">
                    <Input
                      id="gitlab-client-secret"
                      type={showGitlabSecret ? "text" : "password"}
                      value={gitlabClientSecret}
                      onChange={(e) => setGitlabClientSecret(e.target.value)}
                      placeholder="Enter your GitLab Secret"
                    />
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => setShowGitlabSecret((v) => !v)}
                      className="absolute right-2 top-1/2 -translate-y-1/2"
                    >
                      {showGitlabSecret ? "Hide" : "Show"}
                    </Button>
                  </div>
                </Field>
                <ScopeSelector
                  provider="gitlab"
                  onScopeChange={setGitlabScopes}
                />
              </div>
              <div className="mt-6">
                <Button
                  variant="primary"
                  block
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
                  className="inline-flex items-center justify-center"
                >
                  <GitLabIcon className="h-5 w-5 mr-2" />
                  Continue with GitLab
                </Button>
              </div>
            </div>

            {/* Hosted GitLab OAuth */}
            <div className="mt-10 pt-8 space-y-4">
              <Rule className="mb-8" />
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
                <Button
                  variant="primary"
                  block
                  onClick={() => onHostedOAuthLogin("gitlab", gitlabScopes)}
                  disabled={isLoading || !isHostedAvailable("gitlab")}
                  className="inline-flex items-center justify-center"
                >
                  <GitLabIcon className="h-5 w-5 mr-2" />
                  Sign in with Hosted GitLab App
                </Button>
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
                  className="inline-flex items-center gap-2 px-3 py-1.5 text-xs rounded-md border border-slate-600 text-slate-300 bg-ink-2/70 hover:bg-slate-700"
                >
                  <Auth0Icon className="w-4 h-4" /> Open Auth0 Dashboard
                </a>
              </div>
              <div className="flex items-center justify-between text-sm bg-slate-700 p-2 rounded-md mb-4">
                <Code>{getEffectiveRedirectUri(customRedirectUri)}</Code>
                <Button
                  variant="ghost"
                  size="sm"
                  icon
                  onClick={() => handleCopy("auth0")}
                  aria-label="Copy redirect URL"
                >
                  {copiedProvider === "auth0" ? (
                    <ClipboardCheckIcon className="h-5 w-5 text-green-400" />
                  ) : (
                    <ClipboardIcon className="h-5 w-5" />
                  )}
                </Button>
              </div>
              <div className="space-y-3">
                <Field label="Auth0 Domain">
                  <Input
                    id="auth0-domain"
                    type="text"
                    value={auth0Domain}
                    onChange={(e) => setAuth0Domain(e.target.value)}
                    placeholder="your-tenant.us.auth0.com"
                  />
                </Field>
                <Field label="Auth0 Client ID">
                  <Input
                    id="auth0-client-id"
                    type="text"
                    value={auth0ClientId}
                    onChange={(e) => setAuth0ClientId(e.target.value)}
                    placeholder="Enter your Auth0 Client ID"
                  />
                </Field>
                <Field label="Auth0 Client Secret">
                  <div className="relative">
                    <Input
                      id="auth0-client-secret"
                      type={showAuth0Secret ? "text" : "password"}
                      value={auth0ClientSecret}
                      onChange={(e) => setAuth0ClientSecret(e.target.value)}
                      placeholder="Enter your Auth0 Client Secret"
                    />
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => setShowAuth0Secret((v) => !v)}
                      className="absolute right-2 top-1/2 -translate-y-1/2"
                    >
                      {showAuth0Secret ? "Hide" : "Show"}
                    </Button>
                  </div>
                </Field>
                <ScopeSelector
                  provider="auth0"
                  onScopeChange={setAuth0Scopes}
                />
              </div>
              <div className="mt-6">
                <Button
                  variant="primary"
                  block
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
                  className="inline-flex items-center justify-center"
                >
                  <Auth0Icon className="h-5 w-5 mr-2" />
                  Continue with Auth0
                </Button>
              </div>
            </div>

            {/* Hosted Auth0 OAuth */}
            <div className="mt-10 pt-8 space-y-4">
              <Rule className="mb-8" />
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
                <Button
                  variant="primary"
                  block
                  onClick={() => onHostedOAuthLogin("auth0", auth0Scopes)}
                  disabled={isLoading || !isHostedAvailable("auth0")}
                  className="inline-flex items-center justify-center"
                >
                  <Auth0Icon className="h-5 w-5 mr-2" />
                  Sign in with Hosted Auth0 App
                </Button>
                {!isHostedAvailable("auth0") && (
                  <p className="mt-2 text-xs text-slate-400 text-center">
                    Hosted app coming later.
                  </p>
                )}
              </div>
            </div>
          </div>
        </Tab>

        <Tab label="Zitadel" icon={<ZitadelIcon />}>
          <div className="space-y-8">
            {/* Zitadel OAuth */}
            <div className="bg-slate-900/50 p-6 rounded-lg border border-slate-700 space-y-4">
              <div className="flex items-center mb-4">
                <ZitadelIcon className="h-8 w-8" />
                <h2 className="ml-3 text-xl font-semibold text-white">
                  Sign in with Zitadel OAuth
                </h2>
              </div>
              <p className="text-sm text-slate-400 mb-2">
                Create an{" "}
                <a
                  href="https://auth.ipv1337.dev/ui/console"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-blue-400 hover:underline"
                >
                  Application
                </a>{" "}
                in your Zitadel project and add this as a "Redirect URI":
              </p>
              <div className="flex gap-2 mb-3">
                <a
                  href="https://auth.ipv1337.dev/ui/console"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-2 px-3 py-1.5 text-xs rounded-md border border-slate-600 text-slate-300 bg-ink-2/70 hover:bg-slate-700"
                >
                  <ZitadelIcon className="w-4 h-4" /> Open Zitadel Console
                </a>
              </div>
              <div className="flex items-center justify-between text-sm bg-slate-700 p-2 rounded-md mb-4">
                <Code>{getEffectiveRedirectUri(customRedirectUri)}</Code>
                <Button
                  variant="ghost"
                  size="sm"
                  icon
                  onClick={() => handleCopy("zitadel")}
                  aria-label="Copy redirect URL"
                >
                  {copiedProvider === "zitadel" ? (
                    <ClipboardCheckIcon className="h-5 w-5 text-green-400" />
                  ) : (
                    <ClipboardIcon className="h-5 w-5" />
                  )}
                </Button>
              </div>
              <div className="space-y-3">
                <Field label="Zitadel Domain">
                  <Input
                    id="zitadel-domain"
                    type="text"
                    value={zitadelDomain}
                    onChange={(e) => setZitadelDomain(e.target.value)}
                    placeholder="auth.ipv1337.dev"
                  />
                </Field>
                <Field label="Zitadel Client ID">
                  <Input
                    id="zitadel-client-id"
                    type="text"
                    value={zitadelClientId}
                    onChange={(e) => setZitadelClientId(e.target.value)}
                    placeholder="Enter your Zitadel Client ID"
                  />
                </Field>
                <Field label="Zitadel Client Secret">
                  <div className="relative">
                    <Input
                      id="zitadel-client-secret"
                      type={showZitadelSecret ? "text" : "password"}
                      value={zitadelClientSecret}
                      onChange={(e) => setZitadelClientSecret(e.target.value)}
                      placeholder="Enter your Zitadel Client Secret"
                    />
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => setShowZitadelSecret((v) => !v)}
                      className="absolute right-2 top-1/2 -translate-y-1/2"
                    >
                      {showZitadelSecret ? "Hide" : "Show"}
                    </Button>
                  </div>
                </Field>
                <ScopeSelector
                  provider="zitadel"
                  onScopeChange={setZitadelScopes}
                />
              </div>
              <div className="mt-6">
                <Button
                  variant="primary"
                  block
                  onClick={() =>
                    onOAuthLogin(
                      "zitadel",
                      zitadelClientId,
                      zitadelClientSecret,
                      zitadelDomain,
                      zitadelScopes,
                    )
                  }
                  disabled={
                    !zitadelClientId || !zitadelClientSecret || isLoading
                  }
                  className="inline-flex items-center justify-center"
                >
                  <ZitadelIcon className="h-5 w-5 mr-2" />
                  Continue with Zitadel
                </Button>
              </div>
            </div>

            {/* Hosted Zitadel OAuth */}
            <div className="mt-10 pt-8 space-y-4">
              <Rule className="mb-8" />
              <h3 className="text-center text-lg font-medium text-slate-300 mb-4">
                Or use our Zitadel App
              </h3>
              <div className="text-slate-400 space-y-2 text-sm bg-slate-900/50 p-4 rounded-lg border border-slate-700">
                <p>
                  Use our hosted Zitadel OAuth app - no setup required! Just
                  click the button below to authenticate with Zitadel.
                </p>
                <p className="text-slate-500">
                  This option uses our pre-configured OAuth application for your
                  convenience.
                </p>
              </div>
              <div className="mt-6">
                <Button
                  variant="primary"
                  block
                  onClick={() => onHostedOAuthLogin("zitadel", zitadelScopes)}
                  disabled={isLoading || !isHostedAvailable("zitadel")}
                  className="inline-flex items-center justify-center"
                >
                  <ZitadelIcon className="h-5 w-5 mr-2" />
                  Sign in with Hosted Zitadel App
                </Button>
                {!isHostedAvailable("zitadel") && (
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
                  className="inline-flex items-center gap-2 px-3 py-1.5 text-xs rounded-md border border-slate-600 text-slate-300 bg-ink-2/70 hover:bg-slate-700"
                >
                  <LinkedInIcon className="w-4 h-4" /> Open LinkedIn Apps
                </a>
              </div>
              <div className="flex items-center justify-between text-sm bg-slate-700 p-2 rounded-md mb-4">
                <Code>{getEffectiveRedirectUri(customRedirectUri)}</Code>
                <Button
                  variant="ghost"
                  size="sm"
                  icon
                  onClick={() => handleCopy("linkedin")}
                  aria-label="Copy redirect URL"
                >
                  {copiedProvider === "linkedin" ? (
                    <ClipboardCheckIcon className="h-5 w-5 text-green-400" />
                  ) : (
                    <ClipboardIcon className="h-5 w-5" />
                  )}
                </Button>
              </div>
              <div className="space-y-3">
                <Field label="LinkedIn Client ID">
                  <Input
                    id="linkedin-client-id"
                    type="text"
                    value={linkedinClientId}
                    onChange={(e) => setLinkedinClientId(e.target.value)}
                    placeholder="Enter your LinkedIn Client ID"
                  />
                </Field>
                <Field label="LinkedIn Client Secret">
                  <div className="relative">
                    <Input
                      id="linkedin-client-secret"
                      type={showLinkedinSecret ? "text" : "password"}
                      value={linkedinClientSecret}
                      onChange={(e) => setLinkedinClientSecret(e.target.value)}
                      placeholder="Enter your LinkedIn Client Secret"
                    />
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => setShowLinkedinSecret((v) => !v)}
                      className="absolute right-2 top-1/2 -translate-y-1/2"
                    >
                      {showLinkedinSecret ? "Hide" : "Show"}
                    </Button>
                  </div>
                </Field>
                <ScopeSelector
                  provider="linkedin"
                  onScopeChange={setLinkedinScopes}
                />
              </div>
              <div className="mt-6">
                <Button
                  variant="primary"
                  block
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
                  className="inline-flex items-center justify-center"
                >
                  <LinkedInIcon className="h-5 w-5 mr-2" />
                  Continue with LinkedIn
                </Button>
              </div>
            </div>

            {/* Hosted LinkedIn OAuth */}
            <div className="mt-10 pt-8 space-y-4">
              <Rule className="mb-8" />
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
                <Button
                  variant="primary"
                  block
                  onClick={() => onHostedOAuthLogin("linkedin", linkedinScopes)}
                  disabled={isLoading || !isHostedAvailable("linkedin")}
                  className="inline-flex items-center justify-center"
                >
                  <LinkedInIcon className="h-5 w-5 mr-2" />
                  Sign in with Hosted LinkedIn App
                </Button>
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
    </Plate>
  );
};

export default LoginScreen;
