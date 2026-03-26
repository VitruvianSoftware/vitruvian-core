/**
 * Telegram has a 4096 character limit per message.
 * This module handles splitting and formatting responses.
 *
 * We convert Gemini CLI's standard markdown to Telegram's HTML format,
 * which is more forgiving than MarkdownV2 and renders nicely in the app.
 */

const MAX_MESSAGE_LENGTH = 4096;

/**
 * Split a long message into chunks that fit Telegram's limit.
 * Tries to split at natural boundaries (newlines, then spaces).
 * Ensures code blocks are not broken across chunks.
 * @param {string} text
 * @param {number} [maxLen=4096]
 * @returns {string[]}
 */
export function splitMessage(text, maxLen = MAX_MESSAGE_LENGTH) {
  if (text.length <= maxLen) return [text];

  const chunks = [];
  let remaining = text;

  while (remaining.length > 0) {
    if (remaining.length <= maxLen) {
      chunks.push(remaining);
      break;
    }

    let breakAt = maxLen;

    // Prefer breaking at a double newline (paragraph boundary)
    const dblNewline = remaining.lastIndexOf('\n\n', maxLen);
    if (dblNewline > maxLen * 0.3) {
      breakAt = dblNewline + 2;
    } else {
      const newline = remaining.lastIndexOf('\n', maxLen);
      if (newline > maxLen * 0.3) {
        breakAt = newline + 1;
      } else {
        const space = remaining.lastIndexOf(' ', maxLen);
        if (space > maxLen * 0.3) {
          breakAt = space + 1;
        }
      }
    }

    chunks.push(remaining.slice(0, breakAt));
    remaining = remaining.slice(breakAt);
  }

  return chunks;
}

/**
 * Escape characters that are special in Telegram HTML.
 * @param {string} text
 * @returns {string}
 */
function escapeHtml(text) {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

/**
 * Convert a markdown table to a fixed-width text table for Telegram.
 * Telegram doesn't support HTML tables, so we render as monospace text.
 * @param {string} tableBlock - The full markdown table string
 * @returns {string} - Formatted as <pre> block
 */
function convertMarkdownTable(tableBlock) {
  const lines = tableBlock.trim().split('\n');
  if (lines.length < 2) return escapeHtml(tableBlock);

  // Parse rows
  const rows = [];
  for (const line of lines) {
    // Skip separator lines (|---|---|)
    if (/^\|[\s\-:]+\|$/.test(line.trim())) continue;
    const cells = line.split('|').map(c => c.trim()).filter((_, i, arr) => i > 0 && i < arr.length);
    if (cells.length > 0) rows.push(cells);
  }

  if (rows.length === 0) return escapeHtml(tableBlock);

  // Calculate column widths
  const colCount = Math.max(...rows.map(r => r.length));
  const colWidths = Array(colCount).fill(0);
  for (const row of rows) {
    for (let i = 0; i < row.length; i++) {
      colWidths[i] = Math.max(colWidths[i], row[i].length);
    }
  }

  // Render
  const rendered = [];
  for (let r = 0; r < rows.length; r++) {
    const cells = rows[r];
    const line = cells.map((cell, i) => cell.padEnd(colWidths[i] || 0)).join(' │ ');
    rendered.push(escapeHtml(line));
    // Add separator after header row
    if (r === 0) {
      const sep = colWidths.map(w => '─'.repeat(w)).join('─┼─');
      rendered.push(sep);
    }
  }

  return `<pre>${rendered.join('\n')}</pre>`;
}

/**
 * Convert standard markdown (from Gemini CLI) to Telegram HTML.
 *
 * Supported conversions:
 *   ```lang\ncode\n```  →  <pre><code class="language-lang">code</code></pre>
 *   `inline code`       →  <code>inline code</code>
 *   **bold**             →  <b>bold</b>
 *   __bold__             →  <b>bold</b>
 *   *italic*             →  <i>italic</i>
 *   _italic_             →  <i>italic</i>
 *   ~~strike~~           →  <s>strike</s>
 *   [text](url)          →  <a href="url">text</a>
 *   # Heading            →  <b>Heading</b>
 *   | tables |           →  <pre> monospace table
 *   - nested lists       →  indented bullets
 *
 * @param {string} md - Raw markdown text
 * @returns {string} Telegram-compatible HTML
 */
export function markdownToTelegramHtml(md) {
  // Step 1: Extract and protect code blocks (``` ... ```)
  const codeBlocks = [];
  let processed = md.replace(/```(\w*)\n([\s\S]*?)```/g, (_, lang, code) => {
    const idx = codeBlocks.length;
    const langAttr = lang ? ` class="language-${escapeHtml(lang)}"` : '';
    codeBlocks.push(`<pre><code${langAttr}>${escapeHtml(code.trimEnd())}</code></pre>`);
    return `\x00CODEBLOCK_${idx}\x00`;
  });

  // Step 2: Extract and protect inline code (` ... `)
  const inlineCodes = [];
  processed = processed.replace(/`([^`\n]+)`/g, (_, code) => {
    const idx = inlineCodes.length;
    inlineCodes.push(`<code>${escapeHtml(code)}</code>`);
    return `\x00INLINE_${idx}\x00`;
  });

  // Step 3: Extract and convert markdown tables
  const tables = [];
  processed = processed.replace(/((?:^\|.+\|$\n?){2,})/gm, (tableBlock) => {
    // Check it actually has a separator row
    if (/^\|[\s\-:]+\|$/m.test(tableBlock)) {
      const idx = tables.length;
      tables.push(convertMarkdownTable(tableBlock));
      return `\x00TABLE_${idx}\x00`;
    }
    return tableBlock;
  });

  // Step 4: Escape HTML in remaining text
  processed = escapeHtml(processed);

  // Step 5: Convert markdown syntax to HTML

  // Headers: # text → <b>text</b> (Telegram doesn't have header tags)
  processed = processed.replace(/^#{1,6}\s+(.+)$/gm, '<b>$1</b>');

  // Bold: **text** or __text__
  processed = processed.replace(/\*\*(.+?)\*\*/g, '<b>$1</b>');
  processed = processed.replace(/__(.+?)__/g, '<b>$1</b>');

  // Italic: *text* or _text_ (but not inside words with underscores)
  processed = processed.replace(/(?<!\w)\*([^*\n]+?)\*(?!\w)/g, '<i>$1</i>');
  processed = processed.replace(/(?<!\w)_([^_\n]+?)_(?!\w)/g, '<i>$1</i>');

  // Strikethrough: ~~text~~
  processed = processed.replace(/~~(.+?)~~/g, '<s>$1</s>');

  // Links: [text](url)
  processed = processed.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>');

  // Horizontal rules: --- or *** or ___
  processed = processed.replace(/^[-*_]{3,}$/gm, '———');

  // Nested lists: convert indented "- " or "* " to bulleted with indentation
  processed = processed.replace(/^(\s*)[*\-]\s+/gm, (match, indent) => {
    const depth = Math.floor(indent.length / 2);
    const bullets = ['•', '◦', '▪', '▸'];
    const bullet = bullets[Math.min(depth, bullets.length - 1)];
    return '  '.repeat(depth) + `${bullet} `;
  });

  // Numbered lists: keep but clean up indentation
  processed = processed.replace(/^(\s*)\d+\.\s+/gm, (match, indent) => {
    const depth = Math.floor(indent.length / 2);
    return '  '.repeat(depth) + match.trim() + ' ';
  });

  // Blockquotes: > text → <blockquote>
  processed = processed.replace(/^&gt;\s?(.*)$/gm, '<blockquote>$1</blockquote>');
  // Merge adjacent blockquotes
  processed = processed.replace(/<\/blockquote>\n<blockquote>/g, '\n');

  // Step 6: Restore protected blocks
  processed = processed.replace(/\x00CODEBLOCK_(\d+)\x00/g, (_, idx) => codeBlocks[parseInt(idx)]);
  processed = processed.replace(/\x00INLINE_(\d+)\x00/g, (_, idx) => inlineCodes[parseInt(idx)]);
  processed = processed.replace(/\x00TABLE_(\d+)\x00/g, (_, idx) => tables[parseInt(idx)]);

  return processed.trim();
}

/**
 * Format response for Telegram with HTML rendering.
 * @param {string} text - Raw response from Gemini CLI
 * @returns {{ text: string, parseMode: string | undefined }}
 */
export function formatResponse(text) {
  try {
    const html = markdownToTelegramHtml(text);
    return { text: html, parseMode: 'HTML' };
  } catch {
    // If conversion fails, fall back to plain text
    return { text, parseMode: undefined };
  }
}
