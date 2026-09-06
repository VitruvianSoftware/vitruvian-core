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

/** A Docker container. */
public data class Container(val name: String, val subtitle: String, val cpu: String)

/** Which confirmation dialog is open, if any. */
public enum class DialogKind {
  Sleep,
  Restart,
  Halt
}
