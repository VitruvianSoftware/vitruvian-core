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

package dev.vitruvian.design

import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextOverflow

/**
 * The one text primitive.
 *
 * Everything renders through [BasicText] rather than Material's `Text` so the language keeps its
 * own colour and type locals; there is no Material typography or colour scheme underneath any of
 * this.
 */
@Composable
public fun VText(
    text: String,
    modifier: Modifier = Modifier,
    style: TextStyle = VitruvianType.body,
    color: Color = LocalContentColor.current,
    maxLines: Int = Int.MAX_VALUE,
    overflow: TextOverflow = TextOverflow.Clip,
    softWrap: Boolean = true,
) {
  BasicText(
      text = text,
      modifier = modifier,
      style = style.copy(color = color),
      maxLines = maxLines,
      overflow = overflow,
      softWrap = softWrap,
  )
}

/** The [AnnotatedString] overload, for the few places that mix colours in one line. */
@Composable
public fun VText(
    text: AnnotatedString,
    modifier: Modifier = Modifier,
    style: TextStyle = VitruvianType.body,
    color: Color = LocalContentColor.current,
    maxLines: Int = Int.MAX_VALUE,
    overflow: TextOverflow = TextOverflow.Clip,
    softWrap: Boolean = true,
) {
  BasicText(
      text = text,
      modifier = modifier,
      style = style.copy(color = color),
      maxLines = maxLines,
      overflow = overflow,
      softWrap = softWrap,
  )
}

/**
 * `.label` - the uppercase mono caption that titles every section.
 *
 * The CSS uppercases with `text-transform`, which has no Compose equivalent, so the transform
 * happens here and call sites pass ordinary sentence case.
 */
@Composable
public fun Label(
    text: String,
    modifier: Modifier = Modifier,
    color: Color = Vitruvian.textDim,
    style: TextStyle = VitruvianType.label,
) {
  VText(
      text = text.uppercase(),
      modifier = modifier,
      style = style,
      color = color,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis,
      softWrap = false,
  )
}
