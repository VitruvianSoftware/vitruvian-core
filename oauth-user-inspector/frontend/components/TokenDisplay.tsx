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
import { jwtDecode } from "jwt-decode";
import { Button, Code, Label } from "../design-system";
import { ClipboardIcon, ClipboardCheckIcon } from "./icons";

interface TokenDisplayProps {
  accessToken?: string;
  idToken?: string;
  refreshToken?: string;
  safeMode?: boolean;
}

interface JWTDetails {
  header: Record<string, any>;
  payload: Record<string, any>;
  isValid: boolean;
}

// Helper function to decode JWT and extract header/payload
const decodeJWT = (token: string): JWTDetails | null => {
  try {
    // Manually split and decode to get both header and payload
    const parts = token.split(".");
    if (parts.length !== 3) {
      return null;
    }

    // Decode header
    const header = JSON.parse(
      atob(parts[0].replace(/-/g, "+").replace(/_/g, "/")),
    );

    // Decode payload using jwt-decode for validation
    const payload = jwtDecode(token);

    return {
      header,
      payload: payload as Record<string, any>,
      isValid: true,
    };
  } catch (error) {
    return null;
  }
};

// Helper function to check if a token is a JWT
const isJWT = (token: string): boolean => {
  return token.split(".").length === 3;
};

// Component for displaying a single token
const TokenItem: React.FC<{
  title: string;
  token: string;
  tokenType: "access" | "id" | "refresh";
  safeMode?: boolean;
}> = ({ title, token, tokenType, safeMode }) => {
  const [visible, setVisible] = useState(false);
  const [copied, setCopied] = useState(false);
  const [decodedVisible, setDecodedVisible] = useState(false);

  const handleCopy = () => {
    navigator.clipboard.writeText(token).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  };

  const jwtDetails = isJWT(token) ? decodeJWT(token) : null;

  return (
    <div className="space-y-2 w-full overflow-hidden">
      <div className="flex items-center justify-between">
        <Label>{title}</Label>
        <div className="flex gap-2 flex-shrink-0">
          {jwtDetails && (
            <Button
              variant="secondary"
              size="sm"
              onClick={() => setDecodedVisible(!decodedVisible)}
              title="Show decoded JWT header and payload"
            >
              {decodedVisible ? "Hide JWT" : "Decode JWT"}
            </Button>
          )}
          <Button
            variant="ghost"
            size="sm"
            onClick={() => setVisible(!visible)}
          >
            {visible ? "Hide" : "Show"}
          </Button>
          <Button
            variant={copied ? "primary" : "secondary"}
            size="sm"
            done={copied}
            onClick={handleCopy}
            className="flex items-center gap-1"
          >
            {copied ? (
              <>
                <ClipboardCheckIcon className="w-3 h-3 mr-1" />
                Copied!
              </>
            ) : (
              <>
                <ClipboardIcon className="w-3 h-3 mr-1" />
                Copy
              </>
            )}
          </Button>
        </div>
      </div>

      {/* Raw Token Display */}
      <Code className="block w-full overflow-hidden">
        {visible
          ? token
          : safeMode
            ? "••••••••••••••••••••••••••••••••••••••••••••••••••••"
            : token.replace(/.(?=.{4})/g, "•")}
      </Code>

      {/* JWT Decoded Display */}
      {jwtDetails && decodedVisible && (
        <div className="space-y-3 bg-slate-900/70 p-3 rounded border border-slate-600 w-full overflow-hidden">
          <div className="w-full overflow-hidden">
            <Label className="mb-2">JWT Header</Label>
            <Code className="w-full overflow-x-auto overflow-y-hidden whitespace-pre">
              {JSON.stringify(jwtDetails.header, null, 2)}
            </Code>
          </div>

          <div className="w-full overflow-hidden">
            <Label className="mb-2">JWT Payload</Label>
            <Code className="w-full overflow-x-auto overflow-y-hidden whitespace-pre">
              {JSON.stringify(jwtDetails.payload, null, 2)}
            </Code>
          </div>

          {/* Key JWT Claims Summary */}
          <div className="w-full overflow-hidden">
            <Label className="mb-2">Key Claims</Label>
            <div className="text-[10px] space-y-1 text-slate-300 w-full overflow-hidden">
              {jwtDetails.payload.iss && (
                <div className="w-full overflow-hidden">
                  <span className="text-slate-500">Issuer:</span>{" "}
                  <span className="break-words">{jwtDetails.payload.iss}</span>
                </div>
              )}
              {jwtDetails.payload.aud && (
                <div className="w-full overflow-hidden">
                  <span className="text-slate-500">Audience:</span>{" "}
                  <span className="break-words">
                    {Array.isArray(jwtDetails.payload.aud)
                      ? jwtDetails.payload.aud.join(", ")
                      : jwtDetails.payload.aud}
                  </span>
                </div>
              )}
              {jwtDetails.payload.sub && (
                <div className="w-full overflow-hidden">
                  <span className="text-slate-500">Subject:</span>{" "}
                  <span className="break-words">{jwtDetails.payload.sub}</span>
                </div>
              )}
              {jwtDetails.payload.exp && (
                <div className="w-full overflow-hidden">
                  <span className="text-slate-500">Expires:</span>{" "}
                  <span className="break-words">
                    {new Date(jwtDetails.payload.exp * 1000).toLocaleString()}
                  </span>
                  <span className="text-slate-400 ml-1">
                    (
                    {Math.max(
                      0,
                      Math.round(
                        (jwtDetails.payload.exp * 1000 - Date.now()) / 1000,
                      ),
                    )}
                    s)
                  </span>
                </div>
              )}
              {jwtDetails.payload.iat && (
                <div className="w-full overflow-hidden">
                  <span className="text-slate-500">Issued At:</span>{" "}
                  <span className="break-words">
                    {new Date(jwtDetails.payload.iat * 1000).toLocaleString()}
                  </span>
                </div>
              )}
              {jwtDetails.payload.nbf && (
                <div className="w-full overflow-hidden">
                  <span className="text-slate-500">Not Before:</span>{" "}
                  <span className="break-words">
                    {new Date(jwtDetails.payload.nbf * 1000).toLocaleString()}
                  </span>
                </div>
              )}
              {jwtDetails.payload.scope && (
                <div className="w-full overflow-hidden">
                  <span className="text-slate-500">Scope:</span>{" "}
                  <span className="break-words">
                    {jwtDetails.payload.scope}
                  </span>
                </div>
              )}
              {jwtDetails.payload.email && (
                <div className="w-full overflow-hidden">
                  <span className="text-slate-500">Email:</span>{" "}
                  <span className="break-words">
                    {jwtDetails.payload.email}
                  </span>
                </div>
              )}
              {jwtDetails.payload.name && (
                <div className="w-full overflow-hidden">
                  <span className="text-slate-500">Name:</span>{" "}
                  <span className="break-words">{jwtDetails.payload.name}</span>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

const TokenDisplay: React.FC<TokenDisplayProps> = ({
  accessToken,
  idToken,
  refreshToken,
  safeMode = false,
}) => {
  if (!accessToken && !idToken && !refreshToken) {
    return null;
  }

  return (
    <div className="mt-4 bg-slate-900/60 border border-slate-700 rounded-md p-3 space-y-4 w-full overflow-hidden">
      <div className="flex items-center justify-between">
        <Label accent>Raw Token Inspection</Label>
        <div className="text-[10px] text-slate-500">
          JWT tokens show decoded header & payload
        </div>
      </div>

      {accessToken && (
        <TokenItem
          title="Access Token"
          token={accessToken}
          tokenType="access"
          safeMode={safeMode}
        />
      )}

      {idToken && (
        <TokenItem
          title="ID Token"
          token={idToken}
          tokenType="id"
          safeMode={safeMode}
        />
      )}

      {refreshToken && (
        <TokenItem
          title="Refresh Token"
          token={refreshToken}
          tokenType="refresh"
          safeMode={safeMode}
        />
      )}
    </div>
  );
};

export default TokenDisplay;
