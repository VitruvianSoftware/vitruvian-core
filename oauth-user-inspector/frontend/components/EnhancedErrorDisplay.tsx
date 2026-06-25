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
import { EnhancedOAuthError } from "../types";

interface EnhancedErrorDisplayProps {
  error: string | EnhancedOAuthError;
  onDiagnose: () => void;
  onDismiss: () => void;
  diagnostics?: string | null;
}

const EnhancedErrorDisplay: React.FC<EnhancedErrorDisplayProps> = ({
  error,
  onDiagnose,
  onDismiss,
  diagnostics,
}) => {
  // Handle both string errors and enhanced OAuth errors
  const isEnhanced = typeof error === "object" && error.guide;
  const errorMessage = typeof error === "string" ? error : error.error;
  const enhancedError = isEnhanced ? (error as EnhancedOAuthError) : null;

  return (
    <div
      className="w-full p-4 mb-6 bg-red-900/40 border border-red-500/40 text-red-300 rounded-lg space-y-4"
      role="alert"
    >
      <div className="flex items-start justify-between gap-4">
        <div className="flex-1">
          <p className="font-bold">{enhancedError?.guide?.title || "Error"}</p>
          <p>{errorMessage}</p>
        </div>
        <div className="flex gap-2 shrink-0">
          <button
            onClick={onDiagnose}
            className="px-3 py-1.5 text-xs rounded-md border border-red-400/40 bg-red-800/40 hover:bg-red-800/60 text-red-200"
          >
            Diagnose
          </button>
          <button
            onClick={onDismiss}
            className="px-3 py-1.5 text-xs rounded-md border border-red-400/40 bg-red-800/40 hover:bg-red-800/60 text-red-200"
          >
            Dismiss
          </button>
        </div>
      </div>

      {/* Enhanced OAuth error guidance */}
      {enhancedError?.guide && (
        <div className="space-y-3 pt-2 border-t border-red-500/20">
          <div>
            <h4 className="font-semibold text-red-200 mb-1">
              What this means:
            </h4>
            <p className="text-sm text-red-300/90">
              {enhancedError.guide.description}
            </p>
          </div>

          <div>
            <h4 className="font-semibold text-red-200 mb-2">How to fix it:</h4>
            <ul className="space-y-1 text-sm text-red-300/90">
              {enhancedError.guide.troubleshooting.map((tip, index) => (
                <li key={index} className="flex items-start gap-2">
                  <span className="text-red-400 mt-1">•</span>
                  <span>{tip}</span>
                </li>
              ))}
            </ul>
          </div>

          <div>
            <h4 className="font-semibold text-red-200 mb-2">Common causes:</h4>
            <ul className="space-y-1 text-sm text-red-300/80">
              {enhancedError.guide.commonCauses.map((cause, index) => (
                <li key={index} className="flex items-start gap-2">
                  <span className="text-red-400/70 mt-1">•</span>
                  <span>{cause}</span>
                </li>
              ))}
            </ul>
          </div>

          {enhancedError.errorCode && (
            <div className="pt-2">
              <span className="inline-block px-2 py-1 text-xs bg-red-800/60 border border-red-600/40 rounded font-mono">
                Error Code: {enhancedError.errorCode}
              </span>
            </div>
          )}
        </div>
      )}

      {diagnostics && (
        <div className="pt-2 border-t border-red-500/20">
          <h4 className="font-semibold text-red-200 mb-1">
            Diagnostic Information:
          </h4>
          <p className="text-xs text-red-200/80 font-mono bg-red-950/40 p-2 rounded border border-red-600/30">
            {diagnostics}
          </p>
        </div>
      )}
    </div>
  );
};

export default EnhancedErrorDisplay;
