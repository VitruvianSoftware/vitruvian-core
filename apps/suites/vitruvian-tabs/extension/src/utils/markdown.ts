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

export interface MarkdownValidationResult {
  isValid: boolean;
  html: string;
}

/**
 * Simple Regex-based Markdown Parser
 * Supports:
 * - Headers (#, ##, ###)
 * - Bold (**text**)
 * - Italic (*text*)
 * - Lists (- item)
 * - Links ([text](url))
 * - Code blocks (```code```)
 * - Inline code (`code`)
 */
export const parseMarkdown = (text: string): string => {
  if (!text) return "";

  const html = text
    // Escape HTML (basic XSS prevention)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")

    // Headers
    .replace(/^### (.*$)/gim, "<h3>$1</h3>")
    .replace(/^## (.*$)/gim, "<h2>$1</h2>")
    .replace(/^# (.*$)/gim, "<h1>$1</h1>")

    // Bold
    .replace(/\*\*(.*?)\*\*/gim, "<strong>$1</strong>")

    // Italic
    .replace(/\*(.*?)\*/gim, "<em>$1</em>")

    // Code Blocks
    .replace(/```([\s\S]*?)```/gim, "<pre><code>$1</code></pre>")

    // Inline Code
    .replace(/`([^`]+)`/gim, "<code>$1</code>")

    // Links
    .replace(
      /\[([^\]]+)\]\(([^)]+)\)/gim,
      '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>',
    )

    // Unordered Lists
    .replace(/^\s*-\s+(.*$)/gim, "<ul><li>$1</li></ul>")
    // Fix consecutive lists (simple approach: remove </ul><ul>)
    .replace(/<\/ul>\s*<ul>/gim, "")

    // Line breaks (convert newlines to <br> if not in a tag)
    .replace(/\n/gim, "<br />");

  // Wrap generic text in paragraphs if needed?
  // For now, let's keep it simple as it's replacing a textarea.

  return html;
};
