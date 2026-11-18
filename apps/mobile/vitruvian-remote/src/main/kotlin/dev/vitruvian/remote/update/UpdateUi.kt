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

package dev.vitruvian.remote.update

/** Where an update stands, as Settings → About shows it. */
public sealed interface UpdateUi {
  public val release: UpdateFeed.Release?
    get() = null

  /** True while a check, download or install is running, so a second tap does nothing. */
  public val busy: Boolean
    get() = false

  public data object Idle : UpdateUi

  public data object Checking : UpdateUi {
    override val busy: Boolean = true
  }

  public data object UpToDate : UpdateUi

  public data class Available(override val release: UpdateFeed.Release) : UpdateUi

  public data class NeedsNewerAndroid(override val release: UpdateFeed.Release) : UpdateUi

  /** The person tapped Update, and "Install unknown apps" is off for this app. */
  public data class NeedsPermission(override val release: UpdateFeed.Release) : UpdateUi

  public data class Downloading(override val release: UpdateFeed.Release, val fraction: Float) :
      UpdateUi {
    override val busy: Boolean = true
  }

  /** Handed to Android's installer; the app closes as the new version goes in. */
  public data class Installing(override val release: UpdateFeed.Release) : UpdateUi {
    override val busy: Boolean = true
  }

  /** Android wants the person to confirm on its own screen. */
  public data class Confirm(override val release: UpdateFeed.Release) : UpdateUi

  public data class Failed(val reason: String, override val release: UpdateFeed.Release?) :
      UpdateUi

  public companion object {
    /**
     * Whether opening About should check the feed again. Never while something runs, and never over
     * a step waiting on the person (Confirm, NeedsPermission): a fresh Available would hide the
     * button they still need. Otherwise when there is no result yet, the last one failed, or it has
     * gone [stale].
     */
    public fun shouldRecheck(ui: UpdateUi, stale: Boolean): Boolean =
        when {
          ui.busy -> false
          ui is Confirm || ui is NeedsPermission -> false
          ui is Idle || ui is Failed -> true
          else -> stale
        }

    public fun from(check: UpdateCheck): UpdateUi =
        when (check) {
          is UpdateCheck.Failed -> Failed(check.reason, null)
          is UpdateCheck.Decided ->
              when (val d = check.decision) {
                UpdateDecision.UpToDate -> UpToDate
                is UpdateDecision.Available -> Available(d.release)
                is UpdateDecision.NeedsNewerAndroid -> NeedsNewerAndroid(d.release)
              }
        }

    /** The next state once Android's installer reports [event] for [current]. */
    public fun after(current: UpdateUi, event: InstallEvent): UpdateUi {
      val release = current.release
      return when (event) {
        InstallEvent.NeedsConfirmation -> if (release != null) Confirm(release) else current
        InstallEvent.Installed -> UpToDate
        is InstallEvent.Failed -> Failed(event.reason, release)
      }
    }
  }
}

/** What one update check found. */
public sealed interface UpdateCheck {
  public data class Decided(val decision: UpdateDecision) : UpdateCheck

  /** The feed was reached but refused, or could not be reached; [reason] is for the screen. */
  public data class Failed(val reason: String) : UpdateCheck
}

/** What the installer said, delivered by `UpdateInstallReceiver`. */
public sealed interface InstallEvent {
  /** Android wants the person to confirm on its own screen. */
  public data object NeedsConfirmation : InstallEvent

  /** Rarely seen: when the app updates itself, Android stops it as the new version goes in. */
  public data object Installed : InstallEvent

  public data class Failed(val reason: String) : InstallEvent
}

/** The words About uses. Plain, and true to what the code does. */
public object UpdateCopy {
  public fun headline(ui: UpdateUi, installedVersion: String): String =
      when (ui) {
        UpdateUi.Idle,
        UpdateUi.Checking -> "Checking for updates…"
        UpdateUi.UpToDate -> "You're up to date ($installedVersion)."
        is UpdateUi.Available -> "Update available: ${ui.release.version}"
        is UpdateUi.NeedsNewerAndroid ->
            "Version ${ui.release.version} needs a newer version of Android than this phone has."
        is UpdateUi.NeedsPermission -> "Allow updates to install"
        is UpdateUi.Downloading ->
            "Downloading ${ui.release.version}… ${(ui.fraction * 100).toInt().coerceIn(0, 100)}%"
        is UpdateUi.Installing -> "Installing ${ui.release.version}…"
        is UpdateUi.Confirm -> "Confirm the update"
        is UpdateUi.Failed -> ui.reason
      }

  public const val PERMISSION: String =
      "To update itself, Vitruvian Remote needs your OK to install apps. Android calls this " +
          "\"Install unknown apps\". Turn it on for Vitruvian Remote, then come back here. It is " +
          "used only to install Vitruvian Remote's own updates, after checking they are signed " +
          "by Vitruvian Software, and only when you tap Update. You can turn it off again in " +
          "Settings at any time."

  public const val INSTALLING: String =
      "The app closes while the new version goes in. Open it again afterwards: your Macs, " +
          "pairings and settings stay as they are."

  public const val CONFIRM: String =
      "Android wants you to confirm on its own screen. If it isn't showing, tap Confirm."

  public const val WHERE_FROM: String =
      "Updates come from Vitruvian Software's releases on GitHub. Before installing, the app " +
          "checks the update list's signature, the download's checksum, and that the new " +
          "version is signed with the same key as this one."
}
