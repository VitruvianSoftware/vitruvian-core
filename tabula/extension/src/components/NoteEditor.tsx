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
import { parseMarkdown } from "../utils/markdown";
import { Icon } from "./icons";
import { Plate, Button, Textarea } from "@vitruviansoftware/design-system";
import { useFeatureFlag } from "../lib/flags/use-feature-flag";
import { FEATURE_FLAGS } from "../constants/features";

export interface NoteEditorProps {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  autoFocus?: boolean;
  minRows?: number;
  onPopout?: () => void; // Optional popout handler
}

export const NoteEditor: React.FC<NoteEditorProps> = ({
  value,
  onChange,
  placeholder = "Type something...",
  autoFocus,
  minRows = 3,
  onPopout,
}) => {
  const [mode, setMode] = useState<"write" | "preview">("write");
  const [isFullscreen, setIsFullscreen] = useState(false);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const useDesignSystem = useFeatureFlag(
    FEATURE_FLAGS.USE_DESIGN_SYSTEM,
    false,
  );

  // Auto-resize textarea
  useEffect(() => {
    if (textareaRef.current && mode === "write") {
      textareaRef.current.style.height = "auto";
      textareaRef.current.style.height = `${textareaRef.current.scrollHeight}px`;
    }
  }, [value, mode, isFullscreen]);

  const insertSyntax = (prefix: string, suffix: string) => {
    if (!textareaRef.current) return;
    const start = textareaRef.current.selectionStart;
    const end = textareaRef.current.selectionEnd;
    const text = textareaRef.current.value;
    const before = text.substring(0, start);
    const selection = text.substring(start, end);
    const after = text.substring(end);

    const newValue = `${before}${prefix}${selection}${suffix}${after}`;
    onChange(newValue);

    // Defer focus restore to next tick
    setTimeout(() => {
      if (textareaRef.current) {
        textareaRef.current.focus();
        textareaRef.current.setSelectionRange(
          start + prefix.length,
          end + prefix.length,
        );
      }
    }, 0);
  };

  const toggleFullscreen = () => {
    setIsFullscreen(!isFullscreen);
  };

  const Container = useDesignSystem ? Plate : "div";

  return (
    <Container className={`note-editor ${isFullscreen ? "fullscreen" : ""}`}>
      {/* Toolbar */}
      <div className="note-toolbar">
        <div className="toolbar-group">
          {useDesignSystem ? (
            <>
              <Button
                variant={mode === "write" ? "secondary" : "ghost"}
                size="small"
                onClick={() => setMode("write")}
                title="Edit"
              >
                <Icon name="edit" size="sm" />
              </Button>
              <Button
                variant={mode === "preview" ? "secondary" : "ghost"}
                size="small"
                onClick={() => setMode("preview")}
                title="Preview"
              >
                <Icon name="visibility" size="sm" />
              </Button>
            </>
          ) : (
            <>
              <button
                className={`btn-icon btn-xs ${mode === "write" ? "active" : ""}`}
                onClick={() => setMode("write")}
                title="Edit"
              >
                <Icon name="edit" size="sm" />
              </button>
              <button
                className={`btn-icon btn-xs ${mode === "preview" ? "active" : ""}`}
                onClick={() => setMode("preview")}
                title="Preview"
              >
                <Icon name="visibility" size="sm" />
              </button>
            </>
          )}
        </div>

        {mode === "write" && (
          <div className="toolbar-group">
            {useDesignSystem ? (
              <>
                <Button
                  variant="ghost"
                  size="small"
                  onClick={() => insertSyntax("**", "**")}
                  title="Bold"
                >
                  <span style={{ fontWeight: "bold" }}>B</span>
                </Button>
                <Button
                  variant="ghost"
                  size="small"
                  onClick={() => insertSyntax("*", "*")}
                  title="Italic"
                >
                  <span style={{ fontStyle: "italic" }}>I</span>
                </Button>
                <Button
                  variant="ghost"
                  size="small"
                  onClick={() => insertSyntax("- ", "")}
                  title="List"
                >
                  <Icon name="format_list_bulleted" size="sm" />
                </Button>
              </>
            ) : (
              <>
                <button
                  className="btn-icon btn-xs"
                  onClick={() => insertSyntax("**", "**")}
                  title="Bold"
                >
                  <span style={{ fontWeight: "bold" }}>B</span>
                </button>
                <button
                  className="btn-icon btn-xs"
                  onClick={() => insertSyntax("*", "*")}
                  title="Italic"
                >
                  <span style={{ fontStyle: "italic" }}>I</span>
                </button>
                <button
                  className="btn-icon btn-xs"
                  onClick={() => insertSyntax("- ", "")}
                  title="List"
                >
                  <Icon name="format_list_bulleted" size="sm" />
                </button>
              </>
            )}
          </div>
        )}

        <div className="toolbar-group ml-auto">
          {useDesignSystem ? (
            <>
              {onPopout && (
                <Button
                  variant="ghost"
                  size="small"
                  onClick={onPopout}
                  title="Open in new window"
                >
                  <Icon name="open_in_new" size="sm" />
                </Button>
              )}
              <Button
                variant={isFullscreen ? "secondary" : "ghost"}
                size="small"
                onClick={toggleFullscreen}
                title={isFullscreen ? "Exit Fullscreen" : "Fullscreen"}
              >
                <Icon
                  name={isFullscreen ? "fullscreen_exit" : "fullscreen"}
                  size="sm"
                />
              </Button>
            </>
          ) : (
            <>
              {onPopout && (
                <button
                  className="btn-icon btn-xs"
                  onClick={onPopout}
                  title="Open in new window"
                >
                  <Icon name="open_in_new" size="sm" />
                </button>
              )}
              <button
                className={`btn-icon btn-xs ${isFullscreen ? "active" : ""}`}
                onClick={toggleFullscreen}
                title={isFullscreen ? "Exit Fullscreen" : "Fullscreen"}
              >
                <Icon
                  name={isFullscreen ? "fullscreen_exit" : "fullscreen"}
                  size="sm"
                />
              </button>
            </>
          )}
        </div>
      </div>

      {/* Editor / Preview Area */}
      <div className="note-editor-content">
        {mode === "write" ? (
          useDesignSystem ? (
            <Textarea
              ref={textareaRef}
              className="input note-content-input"
              value={value}
              onChange={(e: React.ChangeEvent<HTMLTextAreaElement>) =>
                onChange(e.target.value)
              }
              placeholder={placeholder}
              autoFocus={autoFocus}
              rows={minRows}
              style={{
                minHeight: isFullscreen ? "calc(100vh - 100px)" : "auto",
                resize: "none",
              }}
            />
          ) : (
            <textarea
              ref={textareaRef}
              className="input note-content-input"
              value={value}
              onChange={(e) => onChange(e.target.value)}
              placeholder={placeholder}
              autoFocus={autoFocus}
              rows={minRows}
              style={{
                minHeight: isFullscreen ? "calc(100vh - 100px)" : "auto",
              }}
            />
          )
        ) : (
          <div
            className="markdown-preview"
            dangerouslySetInnerHTML={{
              __html:
                parseMarkdown(value) ||
                '<span class="text-muted">Empty note</span>',
            }}
          />
        )}
      </div>
    </Container>
  );
};
