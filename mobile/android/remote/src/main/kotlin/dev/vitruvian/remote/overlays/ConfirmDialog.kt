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

package dev.vitruvian.remote.overlays

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import dev.vitruvian.design.ButtonVariant
import dev.vitruvian.design.Field
import dev.vitruvian.design.Space
import dev.vitruvian.design.VButton
import dev.vitruvian.design.VDialog
import dev.vitruvian.design.VInput
import dev.vitruvian.design.VText
import dev.vitruvian.design.Vitruvian
import dev.vitruvian.design.VitruvianType
import dev.vitruvian.remote.state.RemoteState

/**
 * The confirmation dialogs: Sleep, Restart and Halt.
 *
 * A destructive one asks for its word to be typed before its button unlocks - never a swipe, which
 * this language does not use for destruction at all. Whether the word is required is a host
 * setting, so a dialog with no word simply renders without the field.
 */
@Composable
public fun ConfirmDialog(state: RemoteState) {
  val spec = state.dialogSpec ?: return
  val colors = Vitruvian
  VDialog(
      onDismissRequest = state::closeDialog,
      kicker = spec.kicker,
      kickerColor = if (spec.destructive) colors.sanguineText else colors.accentText,
      title = spec.title,
      body = spec.body,
  ) {
    val word = spec.word
    if (word != null) {
      Field(label = "") {
        VText(text = confirmPrompt(word), style = VitruvianType.label, color = colors.textDim)
        VInput(
            value = state.confirmText,
            onValueChange = state::setConfirmText,
            modifier = Modifier.fillMaxWidth(),
            textStyle = VitruvianType.mono,
        )
      }
    }
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(Space.s3, Alignment.End),
    ) {
      VButton("Cancel", state::closeDialog)
      VButton(
          label = spec.action,
          onClick = state::confirmDialog,
          enabled = !state.dialogBlocked,
          variant = if (spec.destructive) ButtonVariant.Danger else ButtonVariant.Primary,
      )
    }
  }
}

/** `Type <word> to confirm`, with the word itself lit to full text colour. */
@Composable
private fun confirmPrompt(word: String): AnnotatedString = buildAnnotatedString {
  append("Type ")
  withStyle(SpanStyle(color = Vitruvian.text)) { append(word) }
  append(" to confirm")
}
