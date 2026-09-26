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

/** A paired Mac, as one row of the Hosts list. */
public data class Host(
    val id: String,
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
    /** Worse than [warn]: drawn in the error colour. A disk at 95% is the first user. */
    val crit: Boolean = false,
)

/**
 * Why a list is not on screen, in place of the list.
 *
 * Two fields rather than one string because the tool's own words are rarely the headline: Docker's
 * reason is a sentence about a socket path, and what the reader needs first is that the daemon is
 * not running. [title] is that headline; [detail] keeps the original underneath, where someone
 * debugging it can still read it.
 */
public data class Notice(val title: String, val detail: String)

/** One row of the PromQL panel: a series, and its newest value. */
public data class PanelRow(val name: String, val value: String)

/** One metric plate on a module dashboard. */
public data class ModuleMetric(val label: String, val value: String, val sub: String)

/**
 * One row of a module's list pane.
 *
 * [tag] and [actions] arrived with the pull-request and ArgoCD modules: a row that reports a state
 * ("red", "OutOfSync") and a row you can act on from the phone are both list rows, and giving them
 * their own list type would have duplicated the pane. Both default to absent, so every row that was
 * only ever text still is.
 */
public data class ModuleRow(
    val title: String,
    val subtitle: String,
    val trailing: String,
    val tone: StatusTone,
    val tag: String? = null,
    val tagTone: TagTone = TagTone.Outline,
    val actions: List<RowAction> = emptyList(),
    /** Marked with the accent rule, the way the selected host is on the Hosts list. */
    val selected: Boolean = false,
    val onSelect: (() -> Unit)? = null,
    /**
     * How many lines the title may take. One everywhere except pull requests, whose title IS the
     * content: cut to one line on a folded phone it was the repository and nothing else.
     */
    val titleLines: Int = 1,
)

/**
 * A button on a module row.
 *
 * [enabled] is false when the phone is not paired rather than the button being hidden: "Merge is
 * here and you cannot use it yet" is a different sentence from "this list has no actions", and only
 * one of them tells the user to go and pair.
 */
public data class RowAction(
    val label: String,
    val enabled: Boolean = true,
    val danger: Boolean = false,
    val onClick: () -> Unit,
)

/**
 * A one-line input with a button, under a module's stream.
 *
 * The Claude module's prompt box is wired to `sendModulePrompt` and carries Pause / Halt with it,
 * which is right for a coding agent and wrong for anything else. A module that wants to SAY
 * something -- HomeSpeaker's announce box -- supplies this instead. Null means no box.
 */
public data class ModuleComposer(
    val placeholder: String,
    val buttonLabel: String,
    val value: String,
    val enabled: Boolean,
    val onValueChange: (String) -> Unit,
    val onSubmit: () -> Unit,
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
    val composer: ModuleComposer? = null,
    /**
     * Whether [lines] are Claude Code's own replies, written in Markdown. The stream pane then
     * draws bold, code and bullets instead of the asterisks and backticks.
     */
    val markdown: Boolean = false,
    /**
     * More lists after [rows], each on its own plate. Antigravity's models and agents: its main
     * list became the sessions, and the models it always showed are still worth a glance.
     */
    val extraLists: List<ModuleList> = emptyList(),
    /**
     * [meta] is a warning, drawn in the warn colour: HomeSpeaker's "No outputs — nothing will be
     * spoken" is a setting the user chose, and a dim line would read as fine.
     */
    val metaWarn: Boolean = false,
)

/** A titled list of rows on a dashboard, beside or under the main one. */
public data class ModuleList(val label: String, val rows: List<ModuleRow>)

/** A module as the gallery lists it, installed or not. */
public data class GalleryEntry(
    val id: String,
    val name: String,
    val subtitle: String,
    /**
     * What the Mac agent runs to feed this module, as the gallery tag shows it: `kubectl`,
     * `limactl`, `gh`. Every module is read THROUGH the agent -- there is no SSH, no signed bundle
     * and no second connection -- so the tag names the tool, not a transport.
     */
    val source: String,
    /**
     * The program the Mac must have for this module to mean anything; null if the agent alone
     * suffices.
     */
    val requires: String? = null,
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

/**
 * The phone's notification shade, behind a port for the same reason as [PhoneClipboard].
 *
 * These notifications are the phone's own, not the agent's: they say the Mac stopped answering, or
 * that a command finished while the app was in the background. The agent has its own ntfy path for
 * everything it observes on the Mac itself.
 */
public interface Notifier {
  /**
   * Posts, or replaces, one notification.
   *
   * [id] is a stable key per KIND of message, not per message: a second "unreachable" replaces the
   * first rather than stacking, because the shade should say what is true now and not keep a
   * history of every time the tailnet blinked. [deepLink] is a `vitruvian-remote://<screen>` URL.
   */
  public fun notify(id: String, title: String, body: String, deepLink: String)
}

/**
 * One phone permission, as the Hosts plate draws it.
 *
 * [grantable] is what separates a runtime permission -- a dialog this app can raise -- from one
 * that lives in Settings, which is where Part 2's notification access and accessibility service
 * will land. A row that cannot be granted from here still has to SAY where it is granted, which is
 * what [howTo] carries.
 */
public data class BridgePermissionState(
    val id: String,
    val label: String,
    val tools: String,
    val granted: Boolean,
    val grantable: Boolean,
    val howTo: String,
)

/** An outbound call waiting for the person to answer, as the plate shows it. */
public data class BridgePending(val id: String, val tool: String, val question: String)

/** Everything the bridge tells the UI, in one call, from whichever thread it happened on. */
public data class BridgeStatus(
    val enabled: Boolean,
    val linked: Boolean,
    val link: String,
    val trustUntil: Long,
    val pending: BridgePending?,
    val audit: List<BridgeAuditEntry>,
)

/**
 * The phone bridge, as a port -- the same shape as [Notifier] and for the same reason.
 *
 * The bridge is a foreground service, a broadcast receiver and a permission launcher, none of which
 * this class may hold: it has no `Context` and must not acquire one. Null in previews and tests,
 * and the plate then says the bridge is unavailable rather than drawing controls that do nothing.
 */
public interface BridgeControl {
  /** Starts or stops the service, and remembers which. */
  public fun setEnabled(enabled: Boolean)

  /** Opens the trust window for an hour. */
  public fun trustForAnHour()

  /** Shuts it now. */
  public fun endTrust()

  /** Answers the pending approval from inside the app rather than from the notification. */
  public fun answer(approved: Boolean)

  /** Every permission row, with its current state. */
  public fun permissions(): List<BridgePermissionState>

  /** Raises the runtime-permission dialog for one row. */
  public fun grant(id: String)
}

/**
 * Which confirmation dialog is open, if any.
 *
 * A sealed hierarchy rather than an enum since v1.2, because two of these confirm something about a
 * NAMED thing: merging pull request 2196 of vitruvian-core, syncing the `argocd/grafana`
 * application. Keeping the target in a separate field beside the enum was the alternative, and it
 * makes "which PR is this dialog about" a question with two answers that can disagree.
 */
public sealed interface DialogKind {
  public data object Sleep : DialogKind

  public data object Restart : DialogKind

  public data object Halt : DialogKind

  /** Merge this pull request. [title] is carried so the dialog can name what it is merging. */
  public data class MergePr(val repo: String, val number: Int, val title: String) : DialogKind

  /** Sync this ArgoCD application. */
  public data class SyncApp(val name: String, val namespace: String) : DialogKind

  /**
   * Install the phone-approval hook in Claude Code on the Mac. [waitSeconds] is the agent's hold
   * time, so the dialog promises the fallback the Mac will actually give; 0 means not known yet.
   */
  public data class EnableClaudePrompts(val waitSeconds: Int) : DialogKind
}

/**
 * The Remote screen's collapsible sections, by the id [Persistence] stores.
 *
 * The screen ran to three phone-heights with everything open. The trackpad and its buttons are not
 * in here: they are what the screen is for, and they never fold away.
 */
public object RemoteSection {
  public const val MEDIA: String = "media"
  public const val DESKTOP: String = "desktop"
  public const val WINDOW: String = "window"
  public const val OUTPUT: String = "output"
  public const val AGENT: String = "agent"
  public const val MACROS: String = "macros"
  public const val CLIPBOARD: String = "clipboard"
  public const val POWER: String = "power"
}

/**
 * Open on a fresh install: the two grids with no other home. Media keys and volume are one tap
 * away, and the dock and the quick-settings tiles already carry the commonest of the rest.
 */
public val REMOTE_SECTIONS_OPEN_BY_DEFAULT: Set<String> =
    setOf(RemoteSection.DESKTOP, RemoteSection.WINDOW)
