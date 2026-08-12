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
import { Button, Dialog, Kbd } from "../design-system";

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
  return (
    <Dialog
      open={open}
      title="Help & Shortcuts"
      onDismiss={onClose}
      actions={
        <Button onClick={onClose} variant="ghost" size="sm">
          Close
        </Button>
      }
    >
      <div className="space-y-4">
        <div>
          <h3 className="text-sm uppercase tracking-wide text-paper-dim mb-2">
            Keyboard Shortcuts
          </h3>
          <ul className="space-y-1 text-sm">
            {shortcuts.map(([combo, desc]) => (
              <li key={combo} className="flex justify-between gap-4">
                <Kbd>{combo}</Kbd>
                <span className="text-paper-dim">{desc}</span>
              </li>
            ))}
          </ul>
        </div>

        <div>
          <h3 className="text-sm uppercase tracking-wide text-paper-dim mb-2">
            Token Lifecycle Management
          </h3>
          <div className="space-y-3 text-sm text-paper-dim">
            <div>
              <h4 className="font-semibold text-paper mb-1">
                🔄 Token Refresh
              </h4>
              <p className="text-xs text-paper-dim leading-relaxed">
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
              <h4 className="font-semibold text-paper mb-1">
                🚫 Token Revocation
              </h4>
              <p className="text-xs text-paper-dim leading-relaxed">
                Revoke access tokens to immediately invalidate them for
                security. This is important when tokens are compromised or users
                want to revoke app access.
                <br />
                <strong>Best practice:</strong> Always provide token revocation
                in production apps.
              </p>
            </div>
            <div>
              <h4 className="font-semibold text-paper mb-1">
                🔐 Security Guidelines
              </h4>
              <ul className="text-xs text-paper-dim space-y-1 ml-3 list-disc">
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
        <div className="text-xs text-paper-dim leading-relaxed">
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
      </div>
    </Dialog>
  );
};

export default HelpModal;
