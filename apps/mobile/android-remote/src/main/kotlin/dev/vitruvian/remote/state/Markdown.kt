// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

package dev.vitruvian.remote.state

/**
 * The small part of Markdown that Claude Code actually writes in a reply.
 *
 * The transcript pane printed replies raw -- `**Gist**`, `- ` bullets, backticks -- which is
 * readable to someone who writes Markdown and noise to everyone else. This is deliberately NOT a
 * Markdown parser: bold, inline code, leading `- ` / `* ` bullets and blank-line paragraphs, and
 * nothing else. Anything outside that subset, including an unclosed marker, is left as the literal
 * text it was, because a half-understood construct rendered wrongly is worse than one shown as
 * written.
 *
 * Pure and free of Android imports -- compiled into `:format` -- so the parse can be pinned by a
 * plain JVM test; the screen only turns the result into an `AnnotatedString`.
 */
public object Markdown {

  public enum class Kind {
    Paragraph,
    Bullet,
  }

  /** A run of text with one style. [code] wins over [bold] for the face, but both can be set. */
  public data class Span(val text: String, val bold: Boolean = false, val code: Boolean = false)

  /** A paragraph or one bullet item, as styled runs. */
  public data class Block(val kind: Kind, val spans: List<Span>) {
    /** The text with the markers gone, for a place that has no styles (a one-line row). */
    public val plain: String
      get() = spans.joinToString("") { it.text }
  }

  /**
   * Blocks, in order.
   *
   * Consecutive plain lines join into one paragraph with a space, the way Markdown reflows them; a
   * blank line ends it. Each bullet line is its own block, and a following indented line continues
   * that bullet.
   */
  public fun parse(text: String): List<Block> {
    val blocks = mutableListOf<Block>()
    var kind: Kind? = null
    val buffer = StringBuilder()
    fun flush() {
      val k = kind ?: return
      val body = buffer.toString().trim()
      if (body.isNotEmpty()) blocks += Block(k, inline(body))
      buffer.setLength(0)
      kind = null
    }
    text.replace("\r\n", "\n").split('\n').forEach { raw ->
      val line = raw.trimEnd()
      val trimmed = line.trimStart()
      when {
        trimmed.isEmpty() -> flush()
        isBullet(trimmed) -> {
          flush()
          kind = Kind.Bullet
          buffer.append(trimmed.substring(2))
        }
        // An indented line under a bullet is the bullet wrapping, not a new
        // paragraph.
        kind == Kind.Bullet && line.startsWith(" ") -> buffer.append(' ').append(trimmed)
        kind == Kind.Paragraph -> buffer.append(' ').append(trimmed)
        else -> {
          flush()
          kind = Kind.Paragraph
          buffer.append(trimmed)
        }
      }
    }
    flush()
    return blocks
  }

  /** Every block's plain text, joined with spaces: a whole reply on one line. */
  public fun plain(text: String): String = parse(text).joinToString(" ") { it.plain }

  private fun isBullet(line: String): Boolean =
      line.length > 2 && (line[0] == '-' || line[0] == '*') && line[1] == ' '

  /**
   * `**bold**` and `` `code` ``. Code is literal inside -- `**` in a backtick run is two asterisks
   * -- and bold may contain code. An opener with no closer is kept as text.
   */
  public fun inline(text: String): List<Span> {
    val out = mutableListOf<Span>()
    scan(text, bold = false, out = out)
    return merge(out)
  }

  private fun scan(text: String, bold: Boolean, out: MutableList<Span>) {
    var i = 0
    val plain = StringBuilder()
    fun emitPlain() {
      if (plain.isNotEmpty()) out += Span(plain.toString(), bold = bold)
      plain.setLength(0)
    }
    while (i < text.length) {
      if (text[i] == '`') {
        val close = text.indexOf('`', i + 1)
        if (close > i + 1) {
          emitPlain()
          out += Span(text.substring(i + 1, close), bold = bold, code = true)
          i = close + 1
          continue
        }
      }
      if (!bold && text.startsWith("**", i)) {
        val close = closingBold(text, i + 2)
        if (close > i + 2) {
          emitPlain()
          scan(text.substring(i + 2, close), bold = true, out = out)
          i = close + 2
          continue
        }
      }
      plain.append(text[i])
      i++
    }
    emitPlain()
  }

  /** The next `**` after [from] that is not inside a backtick run, or -1. */
  private fun closingBold(text: String, from: Int): Int {
    var i = from
    while (i < text.length - 1) {
      if (text[i] == '`') {
        val close = text.indexOf('`', i + 1)
        if (close > i) {
          i = close + 1
          continue
        }
      }
      if (text[i] == '*' && text[i + 1] == '*') return i
      i++
    }
    return -1
  }

  /** Neighbouring runs with the same style become one, so the screen builds fewer spans. */
  private fun merge(spans: List<Span>): List<Span> {
    val out = mutableListOf<Span>()
    spans.forEach { span ->
      val last = out.lastOrNull()
      if (last != null && last.bold == span.bold && last.code == span.code) {
        out[out.lastIndex] = last.copy(text = last.text + span.text)
      } else if (span.text.isNotEmpty()) {
        out += span
      }
    }
    return out
  }
}
