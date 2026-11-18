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
 * Pure restart and stop rules for Phone Bridge, kept free of Android imports so JVM unit tests
 * guard every transition without an emulator or local Android SDK.
 */
public object BridgeRestartPolicy {
  /** `Intent.ACTION_BOOT_COMPLETED`, spelled out so this file stays pure JVM. */
  public const val ACTION_BOOT_COMPLETED: String = "android.intent.action.BOOT_COMPLETED"

  /** `Intent.ACTION_MY_PACKAGE_REPLACED`, spelled out so this file stays pure JVM. */
  public const val ACTION_MY_PACKAGE_REPLACED: String = "android.intent.action.MY_PACKAGE_REPLACED"

  /** Link status when the service is intentionally off. */
  public const val STATUS_OFF: String = "off"

  /**
   * Link status recorded if Android ever invokes `Service.onTimeout` on the foreground service.
   *
   * Distinct from [STATUS_OFF] so `Derive.bridgeProblem` surfaces the exact reason on the Phone
   * Bridge screen and banner while keeping `bridgeEnabled` true for the next allowed start.
   */
  public const val STATUS_TIMED_OUT: String = "paused by Android foreground-service time limit"

  /**
   * Link status recorded when Android refuses `startForeground` (for example
   * `ForegroundServiceStartNotAllowedException` or `SecurityException`).
   *
   * Tells the user how to resume while keeping `bridgeEnabled` true for the next foreground open.
   */
  public const val STATUS_REFUSED: String =
      "Phone Bridge stopped by Android, open the app to resume"

  /**
   * What a stop path should write to `bridgeEnabled` and `BridgeHub.setLink(false, linkStatus)`.
   */
  public data class StopOutcome(
      val bridgeEnabled: Boolean,
      val linkStatus: String,
  )

  /**
   * Whether a system broadcast should start `PhoneBridgeService`.
   *
   * Only `BOOT_COMPLETED` (after credential-encrypted storage unlocks) and `MY_PACKAGE_REPLACED`
   * (after an app update) qualify, and only when [bridgeEnabled] was left on by the user.
   */
  public fun shouldRestartOnBroadcast(action: String?, bridgeEnabled: Boolean): Boolean =
      bridgeEnabled && (action == ACTION_BOOT_COMPLETED || action == ACTION_MY_PACKAGE_REPLACED)

  /**
   * Whether bringing the app to the foreground should start `PhoneBridgeService`.
   *
   * Repairs a bridge left on (`[bridgeEnabled] == true`) whose service stopped (for example after
   * `onTimeout` or a refused background start) without touching a bridge the user turned off.
   */
  public fun shouldStartOnForeground(bridgeEnabled: Boolean, serviceRunning: Boolean): Boolean =
      bridgeEnabled && !serviceRunning

  /** Outcome of a user-initiated Stop (notification button or Settings switch off). */
  public fun onUserStop(): StopOutcome = StopOutcome(bridgeEnabled = false, linkStatus = STATUS_OFF)

  /**
   * Outcome of `Service.onTimeout(startId, fgsType)`.
   *
   * Never flips [bridgeEnabled] off: only the user's Stop does that.
   */
  public fun onSystemTimeout(bridgeEnabled: Boolean): StopOutcome =
      StopOutcome(
          bridgeEnabled = bridgeEnabled,
          linkStatus = if (bridgeEnabled) STATUS_TIMED_OUT else STATUS_OFF,
      )

  /**
   * Outcome when Android refuses a foreground-service start
   * (`ForegroundServiceStartNotAllowedException` or `SecurityException`).
   *
   * Keeps [bridgeEnabled] `true` when enabled so opening the app resumes the bridge, while a
   * service that was already disabled stays off.
   */
  public fun onStartRefused(bridgeEnabled: Boolean = true): StopOutcome =
      StopOutcome(
          bridgeEnabled = bridgeEnabled,
          linkStatus = if (bridgeEnabled) STATUS_REFUSED else STATUS_OFF,
      )
}
