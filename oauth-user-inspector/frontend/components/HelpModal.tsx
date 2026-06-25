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

import React from "react";

interface HelpModalProps {
  open: boolean;
  onClose: () => void;
}

const shortcuts = [
  ["Cmd/Ctrl + K", "Focus provider data filter"],
  ["Cmd/Ctrl + E", "Export snapshot JSON"],
  ["Cmd/Ctrl + Shift + C", "Copy full raw JSON"],
  ["Safe Mode Toggle", "Masks PII (name, username, email, token)"],
];

const HelpModal: React.FC<HelpModalProps> = ({ open, onClose }) => {
  if (!open) return null;
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div
        className="absolute inset-0 bg-slate-900/70 backdrop-blur-sm"
        onClick={onClose}
      />
      <div className="relative w-full max-w-lg bg-slate-800 border border-slate-600 rounded-lg shadow-xl p-6 space-y-4 animate-fade-in">
        <div className="flex justify-between items-center mb-2">
          <h2 className="text-xl font-semibold text-slate-100">
            Help & Shortcuts
          </h2>
          <button
            onClick={onClose}
            className="text-slate-400 hover:text-slate-200"
          >
            ✕
          </button>
        </div>
        <div>
          <h3 className="text-sm uppercase tracking-wide text-slate-400 mb-2">
            Keyboard Shortcuts
          </h3>
          <ul className="space-y-1 text-sm">
            {shortcuts.map(([combo, desc]) => (
              <li key={combo} className="flex justify-between gap-4">
                <span className="font-mono text-slate-200">{combo}</span>
                <span className="text-slate-400">{desc}</span>
              </li>
            ))}
          </ul>
        </div>

        <div>
          <h3 className="text-sm uppercase tracking-wide text-slate-400 mb-2">
            Token Lifecycle Management
          </h3>
          <div className="space-y-3 text-sm text-slate-300">
            <div>
              <h4 className="font-semibold text-slate-200 mb-1">
                🔄 Token Refresh
              </h4>
              <p className="text-xs text-slate-400 leading-relaxed">
                Use refresh tokens to obtain new access tokens without
                re-authenticating. Refresh tokens typically have longer
                lifespans and help maintain user sessions securely.
                <br />
                <strong>Supported:</strong> Google, GitLab, Auth0, LinkedIn
                <br />
                <strong>Not supported:</strong> GitHub OAuth Apps (only GitHub
                Apps support refresh tokens)
              </p>
            </div>
            <div>
              <h4 className="font-semibold text-slate-200 mb-1">
                🚫 Token Revocation
              </h4>
              <p className="text-xs text-slate-400 leading-relaxed">
                Revoke access tokens to immediately invalidate them for
                security. This is important when tokens are compromised or users
                want to revoke app access.
                <br />
                <strong>Best practice:</strong> Always provide token revocation
                in production apps.
              </p>
            </div>
            <div>
              <h4 className="font-semibold text-slate-200 mb-1">
                🔐 Security Guidelines
              </h4>
              <ul className="text-xs text-slate-400 space-y-1 ml-3 list-disc">
                <li>
                  Store refresh tokens securely (encrypted, httpOnly cookies)
                </li>
                <li>Implement automatic token refresh before expiration</li>
                <li>Always provide a way for users to revoke access</li>
                <li>Use shortest practical token lifespans</li>
                <li>Log and monitor token usage patterns</li>
              </ul>
            </div>
          </div>
        </div>
        <div className="text-xs text-slate-400 leading-relaxed">
          <p>
            <strong>Snapshot Export</strong> downloads a masked JSON
            representation of the current provider response and view settings
            (token digits are redacted).
          </p>
          <p className="mt-2">
            <strong>Safe Mode</strong> is intended for demos/screenshares;
            exported snapshots are always masked regardless of Safe Mode.
          </p>
        </div>
        <div className="flex justify-end">
          <button
            onClick={onClose}
            className="px-4 py-2 bg-slate-700 hover:bg-slate-600 text-sm rounded-md border border-slate-500 text-slate-200"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
};

export default HelpModal;
