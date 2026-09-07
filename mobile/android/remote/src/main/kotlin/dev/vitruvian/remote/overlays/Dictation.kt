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

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.speech.RecognizerIntent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import dev.vitruvian.design.VButton
import dev.vitruvian.remote.state.RemoteState

/** The label on every dictation button, so the three of them cannot drift apart. */
public const val DICTATE_LABEL: String = "Mic"

/**
 * Dictation into one text field.
 *
 * The system recognizer rather than a bundled one: it is the same engine the keyboard's own mic
 * uses, it needs no `RECORD_AUDIO` permission of ours (the recognizer app holds it), and it works
 * offline on any phone that has downloaded a language.
 *
 * Returns the lambda a button should call. A phone with no recognizer at all -- an Android build
 * with no Google app, which is not rare on the devices this app is aimed at -- gets a log line
 * saying exactly that, because a mic button that silently does nothing is indistinguishable from a
 * broken one.
 */
@Composable
public fun rememberDictation(state: RemoteState, onText: (String) -> Unit): () -> Unit {
  val launcher =
      rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result
        ->
        if (result.resultCode != Activity.RESULT_OK) return@rememberLauncherForActivityResult
        val spoken =
            result.data
                ?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                ?.firstOrNull()
                .orEmpty()
        // The top hypothesis only. The rest are alternatives the recogniser
        // rejected, and appending them would put words in the user's mouth.
        if (spoken.isNotBlank()) onText(spoken)
      }
  return {
    val intent =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            .putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak")
    // resolveActivity is not enough on API 30+ without a <queries> entry, and
    // the entry is in the manifest -- but a phone can still have the intent
    // registered by a recogniser that fails to start, so the catch stays.
    try {
      launcher.launch(intent)
    } catch (_: ActivityNotFoundException) {
      state.noteNoSpeechRecognizer()
    }
  }
}

/** The mic button itself, so all three call sites look the same. */
@Composable
public fun DictateButton(state: RemoteState, onText: (String) -> Unit) {
  val dictate = rememberDictation(state, onText)
  VButton(label = DICTATE_LABEL, onClick = dictate)
}
