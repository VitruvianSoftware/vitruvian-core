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

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Pure unit tests for [BridgeRestartPolicy] boot, package-update, timeout, and Stop rules. */
public class BridgeRestartPolicyTest {

  @Test
  public fun bootCompletedRestartsWhenBridgeIsEnabled() {
    assertTrue(
        BridgeRestartPolicy.shouldRestartOnBroadcast(
            action = BridgeRestartPolicy.ACTION_BOOT_COMPLETED,
            bridgeEnabled = true,
        ))
  }

  @Test
  public fun bootCompletedIsNoOpWhenBridgeIsDisabled() {
    assertFalse(
        BridgeRestartPolicy.shouldRestartOnBroadcast(
            action = BridgeRestartPolicy.ACTION_BOOT_COMPLETED,
            bridgeEnabled = false,
        ))
  }

  @Test
  public fun packageReplacedBehavesLikeBoot() {
    assertTrue(
        BridgeRestartPolicy.shouldRestartOnBroadcast(
            action = BridgeRestartPolicy.ACTION_MY_PACKAGE_REPLACED,
            bridgeEnabled = true,
        ))
    assertFalse(
        BridgeRestartPolicy.shouldRestartOnBroadcast(
            action = BridgeRestartPolicy.ACTION_MY_PACKAGE_REPLACED,
            bridgeEnabled = false,
        ))
  }

  @Test
  public fun lockedBootAndUnrelatedActionsNeverRestart() {
    val ignoredActions =
        listOf(
            null,
            "",
            "android.intent.action.LOCKED_BOOT_COMPLETED",
            "dev.vitruvian.remote.bridge.STOP",
        )
    for (action in ignoredActions) {
      assertFalse(
          "Action $action must not trigger bridge restart",
          BridgeRestartPolicy.shouldRestartOnBroadcast(action = action, bridgeEnabled = true),
      )
    }
  }

  @Test
  public fun timeoutKeepsBridgeEnabledForNextAllowedStart() {
    val timedOut = BridgeRestartPolicy.onSystemTimeout(bridgeEnabled = true)
    assertTrue(timedOut.bridgeEnabled)
    assertEquals(BridgeRestartPolicy.STATUS_TIMED_OUT, timedOut.linkStatus)
    assertTrue(
        BridgeRestartPolicy.shouldRestartOnBroadcast(
            action = BridgeRestartPolicy.ACTION_BOOT_COMPLETED,
            bridgeEnabled = timedOut.bridgeEnabled,
        ))
    assertTrue(
        BridgeRestartPolicy.shouldStartOnForeground(
            bridgeEnabled = timedOut.bridgeEnabled,
            serviceRunning = false,
        ))

    val alreadyOff = BridgeRestartPolicy.onSystemTimeout(bridgeEnabled = false)
    assertFalse(alreadyOff.bridgeEnabled)
    assertEquals(BridgeRestartPolicy.STATUS_OFF, alreadyOff.linkStatus)
  }

  @Test
  public fun userStopClearsEnabledAndBlocksFutureRestarts() {
    val stopped = BridgeRestartPolicy.onUserStop()
    assertFalse(stopped.bridgeEnabled)
    assertEquals(BridgeRestartPolicy.STATUS_OFF, stopped.linkStatus)
    assertFalse(
        BridgeRestartPolicy.shouldRestartOnBroadcast(
            action = BridgeRestartPolicy.ACTION_BOOT_COMPLETED,
            bridgeEnabled = stopped.bridgeEnabled,
        ))
    assertFalse(
        BridgeRestartPolicy.shouldRestartOnBroadcast(
            action = BridgeRestartPolicy.ACTION_MY_PACKAGE_REPLACED,
            bridgeEnabled = stopped.bridgeEnabled,
        ))
    assertFalse(
        BridgeRestartPolicy.shouldStartOnForeground(
            bridgeEnabled = stopped.bridgeEnabled,
            serviceRunning = false,
        ))
  }

  @Test
  public fun foregroundOpenStartsOnlyWhenEnabledAndStopped() {
    assertTrue(
        BridgeRestartPolicy.shouldStartOnForeground(
            bridgeEnabled = true,
            serviceRunning = false,
        ))
    assertFalse(
        BridgeRestartPolicy.shouldStartOnForeground(
            bridgeEnabled = true,
            serviceRunning = true,
        ))
    assertFalse(
        BridgeRestartPolicy.shouldStartOnForeground(
            bridgeEnabled = false,
            serviceRunning = false,
        ))
    assertFalse(
        BridgeRestartPolicy.shouldStartOnForeground(
            bridgeEnabled = false,
            serviceRunning = true,
        ))
  }

  @Test
  public fun startRefusedKeepsBridgeEnabledAndSetsResumeMessage() {
    val refused = BridgeRestartPolicy.onStartRefused()
    assertTrue(refused.bridgeEnabled)
    assertEquals(
        "Phone Bridge stopped by Android, open the app to resume",
        refused.linkStatus,
    )
    assertEquals(BridgeRestartPolicy.STATUS_REFUSED, refused.linkStatus)
    assertTrue(
        BridgeRestartPolicy.shouldStartOnForeground(
            bridgeEnabled = refused.bridgeEnabled,
            serviceRunning = false,
        ))

    val refusedWhileDisabled = BridgeRestartPolicy.onStartRefused(bridgeEnabled = false)
    assertFalse(refusedWhileDisabled.bridgeEnabled)
    assertEquals(BridgeRestartPolicy.STATUS_OFF, refusedWhileDisabled.linkStatus)
  }
}
