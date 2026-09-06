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
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.vitruvian.design.BottomSheet
import dev.vitruvian.design.ButtonVariant
import dev.vitruvian.design.Field
import dev.vitruvian.design.Label
import dev.vitruvian.design.SegmentOption
import dev.vitruvian.design.Segmented
import dev.vitruvian.design.Space
import dev.vitruvian.design.Tag
import dev.vitruvian.design.TagTone
import dev.vitruvian.design.VButton
import dev.vitruvian.design.VInput
import dev.vitruvian.design.VSwitch
import dev.vitruvian.design.VText
import dev.vitruvian.design.Vitruvian
import dev.vitruvian.design.VitruvianType
import dev.vitruvian.remote.state.MacroKind
import dev.vitruvian.remote.state.RemoteState

private val COMMAND_FIELD_HEIGHT = 72.dp

/**
 * The macro editor.
 *
 * A bottom glass sheet rather than a screen: binding a button to a script is a one-field-at-a-time
 * job you return from, and pushing a whole screen for it would lose the place you were in.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
public fun MacroEditor(state: RemoteState) {
  if (!state.macroEditorOpen) return
  val colors = Vitruvian
  BottomSheet(onDismissRequest = state::closeMacroEditor) {
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
      Column(
          modifier = Modifier.weight(1f),
          verticalArrangement = Arrangement.spacedBy(Space.s1),
      ) {
        Label(text = "Macro · new", color = colors.accentText)
        VText(text = "Bind a button to a script", style = VitruvianType.h2)
      }
      VText(
          text = "runs on ${state.hostShortName}",
          style = VitruvianType.listSub,
          color = colors.textDim,
      )
    }
    Field(label = "Label") {
      VInput(
          value = state.macroName,
          onValueChange = state::setMacroName,
          modifier = Modifier.fillMaxWidth(),
          placeholder = "Deploy staging",
      )
    }
    Field(label = "Kind") {
      Segmented(
          options =
              MacroKind.entries.map { kind ->
                SegmentOption(
                    label = kind.label,
                    selected = state.macroKind == kind,
                    onSelect = { state.setMacroKind(kind) },
                )
              },
      )
    }
    Field(label = "Command") {
      VInput(
          value = state.macroCommand,
          onValueChange = state::setMacroCommand,
          modifier = Modifier.fillMaxWidth().heightIn(min = COMMAND_FIELD_HEIGHT),
          placeholder = "bazel run //tools/gitops:sync -- staging",
          textStyle = VitruvianType.mono,
          singleLine = false,
      )
    }
    VSwitch(
        checked = state.macroConfirm,
        onCheckedChange = state::setMacroConfirm,
        label = "Ask before running (destructive)",
    )
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(Space.s3),
        verticalArrangement = Arrangement.spacedBy(Space.s3),
        modifier = Modifier.fillMaxWidth(),
    ) {
      Label(text = "Show on")
      Tag(text = "Home", tone = TagTone.Accent)
      Tag(text = "Dock", tone = TagTone.Accent)
      Tag(text = "Remote", tone = TagTone.Outline)
    }
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(Space.s3, Alignment.End),
    ) {
      VButton("Cancel", state::closeMacroEditor)
      VButton(
          label = "Save macro",
          onClick = state::saveMacro,
          enabled = !state.macroSaveBlocked,
          variant = ButtonVariant.Primary,
      )
    }
  }
}
