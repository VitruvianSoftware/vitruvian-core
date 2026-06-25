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

import React, { useState, useRef, useEffect } from "react";
import { MenuIcon, HelpIcon, UploadIcon, LogoutIcon } from "./icons";

interface TopMenuProps {
  userLoggedIn: boolean;
  importedSnapshot: any | null;
  onImportSnapshot: (file: File) => void;
  onClearSnapshot: () => void;
  onToggleSafeMode: () => void;
  safeMode: boolean;
  onLogout: () => void;
  onShowHelp: () => void;
  runDiagnostics: () => void;
  hasError: boolean;
}

/*
 * Collapsible hamburger menu to reduce button clutter.
 * Mobile: shows only hamburger; expanded panel slides down.
 * Desktop: inline buttons, with hamburger to optionally collapse/expand if desired.
 */
const TopMenu: React.FC<TopMenuProps> = ({
  userLoggedIn,
  importedSnapshot,
  onImportSnapshot,
  onClearSnapshot,
  onToggleSafeMode,
  safeMode,
  onLogout,
  onShowHelp,
  runDiagnostics,
  hasError,
}) => {
  const [open, setOpen] = useState<boolean>(false);
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);

  // Close on outside click
  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (
        open &&
        containerRef.current &&
        !containerRef.current.contains(e.target as Node)
      ) {
        setOpen(false);
      }
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [open]);

  // Keyboard accessibility for Esc to close
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpen(false);
    };
    document.addEventListener("keydown", handler);
    return () => document.removeEventListener("keydown", handler);
  }, []);

  const triggerFileDialog = () => fileInputRef.current?.click();

  const panelId = "topmenu-panel";
  const firstFocusable = useRef<HTMLButtonElement | null>(null);
  const lastFocusable = useRef<HTMLButtonElement | null>(null);

  // Focus management when opening
  useEffect(() => {
    if (open && firstFocusable.current) {
      firstFocusable.current.focus();
    }
  }, [open]);

  // Simple focus trap
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (!open) return;
      if (e.key === "Tab") {
        const focusables = Array.from(
          containerRef.current?.querySelectorAll<HTMLElement>(
            "[data-focusable='true']",
          ),
        ).filter((el) => !el.hasAttribute("disabled"));
        if (focusables.length === 0) return;
        const first = focusables[0];
        const last = focusables[focusables.length - 1];
        if (e.shiftKey && document.activeElement === first) {
          e.preventDefault();
          (last as HTMLElement).focus();
        } else if (!e.shiftKey && document.activeElement === last) {
          e.preventDefault();
          (first as HTMLElement).focus();
        }
      }
    };
    document.addEventListener("keydown", handler);
    return () => document.removeEventListener("keydown", handler);
  }, [open]);

  return (
    <div ref={containerRef} className="relative">
      <button
        onClick={() => setOpen((o) => !o)}
        aria-label={open ? "Close menu" : "Open menu"}
        aria-expanded={open}
        aria-controls={panelId}
        className="p-2 rounded-md border border-slate-600 text-slate-300 hover:bg-slate-700 inline-flex items-center gap-2 bg-slate-800/70 shadow-sm focus:outline-none focus:ring-2 focus:ring-slate-500"
      >
        <div className="relative">
          <MenuIcon className="w-5 h-5" />
          {importedSnapshot && (
            <span
              className="absolute -top-1 -right-1 inline-block w-2 h-2 rounded-full bg-amber-400 shadow ring-1 ring-slate-900/70"
              aria-label="Snapshot loaded"
            />
          )}
        </div>
        <span className="hidden sm:inline text-sm">Menu</span>
      </button>
      {open && (
        <div
          id={panelId}
          role="menu"
          aria-label="Application actions"
          className="absolute right-0 mt-2 w-64 sm:w-72 origin-top-right animate-fadeIn border border-slate-700 rounded-lg bg-slate-900 p-4 shadow-xl flex flex-col gap-4 ring-1 ring-slate-800/60"
        >
          {/**
           * Shared class tokens for consistent button styling
           */}
          {(() => {
            // No runtime effect; used to co-locate classnames for readability.
            // itemBtn: unified neutral pill button style
            // dangerBtn: red-accented diagnostic button
          })()}

          <div
            className="flex flex-col gap-2"
            role="group"
            aria-label="Snapshot actions"
          >
            <button
              ref={firstFocusable}
              data-focusable="true"
              onClick={triggerFileDialog}
              className="w-full px-3 py-1.5 text-xs rounded-md border border-slate-600 text-slate-300 bg-slate-900/20 hover:bg-slate-800/40 text-center inline-flex items-center justify-center gap-2 focus:outline-none focus-visible:ring-2 focus-visible:ring-slate-500"
            >
              <UploadIcon className="w-4 h-4" /> Import Snapshot
            </button>
            <input
              ref={fileInputRef}
              type="file"
              accept="application/json"
              className="hidden"
              onChange={(e) =>
                e.target.files &&
                e.target.files[0] &&
                onImportSnapshot(e.target.files[0])
              }
            />
            {importedSnapshot && (
              <button
                data-focusable="true"
                onClick={onClearSnapshot}
                className="w-full px-3 py-1.5 text-xs rounded-md border border-slate-600 text-slate-300 bg-slate-900/20 hover:bg-slate-800/40 text-center inline-flex items-center justify-center gap-2 focus:outline-none focus-visible:ring-2 focus-visible:ring-slate-500"
              >
                <UploadIcon className="w-4 h-4 rotate-180" /> Clear Snapshot
              </button>
            )}
          </div>
          {userLoggedIn && (
            <div
              className="flex flex-col gap-2"
              role="group"
              aria-label="Session actions"
            >
              <button
                data-focusable="true"
                onClick={onToggleSafeMode}
                className={`w-full px-3 py-1.5 text-xs rounded-md border font-medium text-center transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-slate-500 ${safeMode ? "bg-amber-500/20 border-amber-500/60 text-amber-300 hover:bg-amber-500/30" : "border-slate-600 text-slate-300 bg-slate-900/20 hover:bg-slate-800/40"}`}
              >
                {safeMode ? "Safe Mode On" : "Safe Mode Off"}
              </button>
              <button
                data-focusable="true"
                onClick={onLogout}
                className="w-full px-3 py-1.5 text-xs rounded-md border border-slate-600 text-slate-300 bg-slate-900/20 hover:bg-slate-800/40 text-center inline-flex items-center justify-center gap-2 focus:outline-none focus-visible:ring-2 focus-visible:ring-slate-500"
              >
                <LogoutIcon className="w-4 h-4" /> Logout
              </button>
            </div>
          )}
          <div
            className="flex flex-col gap-2"
            role="group"
            aria-label="Help & diagnostics"
          >
            <button
              data-focusable="true"
              onClick={onShowHelp}
              className="w-full px-3 py-1.5 text-xs rounded-md border border-slate-600 text-slate-300 bg-slate-900/20 hover:bg-slate-800/40 text-center inline-flex items-center justify-center gap-2 focus:outline-none focus-visible:ring-2 focus-visible:ring-slate-500"
            >
              <HelpIcon className="w-4 h-4" /> Help & Shortcuts
            </button>
            {hasError && (
              <button
                data-focusable="true"
                ref={lastFocusable}
                onClick={runDiagnostics}
                className="w-full px-3 py-1.5 text-xs rounded-md border border-red-400/50 text-red-300 bg-red-900/20 hover:bg-red-900/30 text-center focus:outline-none focus-visible:ring-2 focus-visible:ring-red-400"
              >
                Diagnose
              </button>
            )}
            {!hasError && <span ref={lastFocusable} tabIndex={-1} />}
          </div>
        </div>
      )}
    </div>
  );
};

export default TopMenu;
