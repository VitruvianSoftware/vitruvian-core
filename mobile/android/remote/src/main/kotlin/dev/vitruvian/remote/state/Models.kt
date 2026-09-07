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

import dev.vitruvian.design.StatusTone
import dev.vitruvian.design.TagTone
import dev.vitruvian.design.TerminalLine

/** The six destinations. Hosts is reachable from the host chip and the rail only. */
public enum class Screen(public val title: String) {
  Home("Home"),
  Remote("Remote"),
  Mac("Mac"),
  Apps("Apps"),
  Console("Console"),
  Hosts("Hosts"),
}

/** Whether this remote has a Mac, and whether it can reach it. */
public enum class Connection {
  Connected,
  Offline,
  Unpaired
}

/**
 * Where the numbers on screen come from. Shown as a tag on the Home screen, because a dashboard
 * that cannot say whether it is measuring or pretending is worse than either.
 */
public enum class MetricsSource(public val label: String) {
  /** No agent configured: MockHost's random walk, as the app shipped. */
  Simulated("simulated"),
  /** The agent answered within the last poll. */
  Live("live"),
  /** An agent is configured and is not answering. Values are frozen at the last reading. */
  Unreachable("unreachable"),
}

/** The two panes the Apps screen switches between. */
public enum class AppsView {
  Dashboards,
  Gallery
}

/** How a macro reaches the Mac. */
public enum class MacroKind(public val label: String) {
  Ssh("SSH"),
  AppleScript("AppleScript"),
  Shortcut("Shortcut"),
}

/** A button bound to a script on the host. */
public data class Macro(
    val id: String,
    val label: String,
    val command: String,
    val kind: MacroKind,
    val confirm: Boolean = false,
)

/** A paired Mac. */
public data class Host(
    val id: Int,
    val name: String,
    val subtitle: String,
    val tone: StatusTone,
    val tag: String,
    val tagTone: TagTone,
)

/** A widget on the Home grid. */
public data class Widget(
    val id: String,
    val label: String,
    val value: String,
    val sub: String,
    val percent: Int,
    val warn: Boolean = false,
)

/** A row of the Home screen's "Running now" list. */
public data class RunningItem(
    val moduleId: String,
    val title: String,
    val subtitle: String,
    val tone: StatusTone,
    val tag: String,
    val tagTone: TagTone,
)

/**
 * A figure with somewhere to admit it has no source.
 *
 * [percent] is nullable and that is the whole point of the type: a meter drawn at zero is a claim
 * that the thing is idle, and "we cannot read this" is not the same claim. Null means the screen
 * draws no bar at all.
 */
public data class HonestMetric(
    val label: String,
    val value: String,
    val sub: String,
    val percent: Int?,
    val warn: Boolean = false,
)

/** One metric plate on a module dashboard. */
public data class ModuleMetric(val label: String, val value: String, val sub: String)

/** One row of a module's list pane. */
public data class ModuleRow(
    val title: String,
    val subtitle: String,
    val trailing: String,
    val tone: StatusTone,
)

/** An installed module's dashboard. */
public data class ModuleDashboard(
    val id: String,
    val name: String,
    val meta: String,
    val status: String,
    val statusTone: StatusTone,
    val metrics: List<ModuleMetric>,
    val streamLabel: String,
    val lines: List<TerminalLine>,
    val cursor: Boolean,
    val prompts: Boolean,
    val listLabel: String,
    val rows: List<ModuleRow>,
)

/** A module as the gallery lists it, installed or not. */
public data class GalleryEntry(
    val id: String,
    val name: String,
    val subtitle: String,
    val source: String,
)

/** A row of the Mac screen's process table. */
public data class Process(val name: String, val cpu: Int, val memory: String)

/** A Lima VM or K3s node. */
public data class Vm(
    val name: String,
    val subtitle: String,
    val tone: StatusTone,
    val tag: String,
    val tagTone: TagTone,
)

/**
 * A Docker or Podman container.
 *
 * [trailing] was `cpu`, and nothing ever put a CPU figure in it: `docker ps` does not report one
 * (that is `docker stats`, a second call with a sampling window), so what the agent can supply is
 * the status string. Renamed rather than left to imply a measurement the column never held.
 */
public data class Container(val name: String, val subtitle: String, val trailing: String)

/**
 * The phone's own clipboard.
 *
 * An interface rather than a `ClipboardManager` because [RemoteState] has no `Context` and should
 * not acquire one: it is the app's model, and giving it an Android system service to reach for
 * would make every test of it an instrumentation test. `MainActivity` supplies the real thing.
 */
public interface PhoneClipboard {
  /** The current clip as text, or blank when there is none this app can read. */
  public fun read(): String

  public fun write(text: String)
}

/** Which confirmation dialog is open, if any. */
public enum class DialogKind {
  Sleep,
  Restart,
  Halt
}
