// Copyright (c) 2026 VitruvianSoftware

package com.vitruviansoftware.wand

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import com.vitruviansoftware.wand.ble.BleConnectionState
import com.vitruviansoftware.wand.ble.DaydreamPairingHelper
import com.vitruviansoftware.wand.core.WandConfig
import com.vitruviansoftware.wand.service.WandAccessibilityService
import com.vitruviansoftware.wand.service.WandRuntimeHub
import com.vitruviansoftware.wand.ui.WandAppScreen
import com.vitruviansoftware.wand.ui.queryInstalledLauncherApps
import com.vitruviansoftware.wand.ui.tryEnableAccessibilityViaSecureSettings
import dev.vitruvian.design.VitruvianTheme

/**
 * Single activity entrypoint for both Android phones/tablets (`LAUNCHER`) and Android TV
 * (`LEANBACK_LAUNCHER`).
 *
 * Owns a [DaydreamPairingHelper] so Scan & Pair works directly from `MainActivity` even before
 * `WandAccessibilityService` is enabled.
 */
class MainActivity : ComponentActivity() {

  private var permissionsGrantedState by mutableStateOf(false)
  private var pendingScanAfterPermissions: Boolean = false
  private var pairingHelper: DaydreamPairingHelper? = null

  private val permissionLauncher =
      registerForActivityResult(
          ActivityResultContracts.RequestMultiplePermissions(),
      ) {
        val granted = checkRequiredPermissions()
        permissionsGrantedState = granted
        if (granted && pendingScanAfterPermissions) {
          pendingScanAfterPermissions = false
          pairingHelper?.startScan()
        }
      }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    pairingHelper =
        DaydreamPairingHelper(
            context = this,
            onDiscoveredControllers = { list ->
              WandRuntimeHub.update { it.copy(discoveredControllers = list) }
            },
            onPairingStateChanged = { state, detail ->
              WandRuntimeHub.update { snap ->
                if (snap.connectionState == BleConnectionState.CONNECTED) {
                  snap.copy(statusDetail = detail ?: snap.statusDetail)
                } else {
                  snap.copy(connectionState = state, statusDetail = detail)
                }
              }
            },
            onDeviceBonded = { address ->
              WandAccessibilityService.instance?.connectToAddress(address)
            },
        )

    permissionsGrantedState = checkRequiredPermissions()
    if (!permissionsGrantedState) {
      requestRequiredPermissions()
    }

    val isTv = WandRuntimeHub.isTvMode(this)

    setContent {
      VitruvianTheme {
        val runtime by WandRuntimeHub.state.collectAsState()
        var config by remember {
          mutableStateOf(WandConfig(platform = if (isTv) "android_tv" else "android"))
        }
        val installedApps = remember { queryInstalledLauncherApps(this@MainActivity) }

        LaunchedEffect(Unit) {
          WandRuntimeHub.loadConfig(this@MainActivity) { loaded -> config = loaded }
        }

        WandAppScreen(
            isTv = isTv,
            runtime =
                runtime.copy(
                    serviceRunning =
                        WandRuntimeHub.isAccessibilityServiceEnabled(this@MainActivity),
                ),
            config = config,
            installedApps = installedApps,
            hasBlePermissions = permissionsGrantedState,
            onRequestPermissions = { requestRequiredPermissions() },
            onOpenAccessibilitySettings = { openAccessibilitySettings() },
            onConnect = {
              if (!checkRequiredPermissions()) {
                requestRequiredPermissions()
              } else {
                WandAccessibilityService.instance?.connectController()
              }
            },
            onDisconnect = {
              pairingHelper?.stopScan()
              WandAccessibilityService.instance?.disconnectController()
            },
            onRecalibrate = { WandAccessibilityService.instance?.recalibrateController() },
            onStartPairingScan = {
              if (!checkRequiredPermissions()) {
                pendingScanAfterPermissions = true
                requestRequiredPermissions()
              } else {
                pairingHelper?.startScan()
              }
            },
            onPairAndConnect = { address ->
              if (!checkRequiredPermissions()) {
                requestRequiredPermissions()
              } else {
                pairingHelper?.pairDevice(address)
              }
            },
            onTryEnableViaAdb = {
              val res = tryEnableAccessibilityViaSecureSettings(this@MainActivity)
              res.fold(
                  onSuccess = {
                    "WandAccessibilityService enabled in Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES."
                  },
                  onFailure = { err ->
                    err.message ?: "Failed to enable service via WRITE_SECURE_SETTINGS."
                  },
              )
            },
            onUpdateConfig = { updated ->
              config = updated
              WandRuntimeHub.saveConfig(this@MainActivity, updated)
            },
            onResetDefaults = {
              WandRuntimeHub.resetToDefaults(this@MainActivity) { defaults -> config = defaults }
            },
            onSetTestMode = { enabled -> WandAccessibilityService.instance?.setTestMode(enabled) },
            onDismissSaveError = { WandRuntimeHub.clearSaveError() },
        )
      }
    }
  }

  override fun onResume() {
    super.onResume()
    permissionsGrantedState = checkRequiredPermissions()
  }

  override fun onDestroy() {
    pairingHelper?.destroy()
    pairingHelper = null
    super.onDestroy()
  }

  private fun requiredPermissions(): List<String> = buildList {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      add(Manifest.permission.BLUETOOTH_SCAN)
      add(Manifest.permission.BLUETOOTH_CONNECT)
    } else {
      add(Manifest.permission.ACCESS_FINE_LOCATION)
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      add(Manifest.permission.POST_NOTIFICATIONS)
    }
  }

  private fun checkRequiredPermissions(): Boolean =
      requiredPermissions().all { perm ->
        ContextCompat.checkSelfPermission(this, perm) == PackageManager.PERMISSION_GRANTED
      }

  private fun requestRequiredPermissions() {
    val missing =
        requiredPermissions().filter { perm ->
          ContextCompat.checkSelfPermission(this, perm) != PackageManager.PERMISSION_GRANTED
        }
    if (missing.isNotEmpty()) {
      permissionLauncher.launch(missing.toTypedArray())
    }
  }

  private fun openAccessibilitySettings() {
    val intent =
        Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
          addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    try {
      startActivity(intent)
    } catch (e: Exception) {
      Log.w(TAG, "Failed to open ACTION_ACCESSIBILITY_SETTINGS, falling back to ACTION_SETTINGS", e)
      try {
        startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
      } catch (fallbackErr: Exception) {
        Log.e(TAG, "Failed to open ACTION_SETTINGS fallback", fallbackErr)
      }
    }
  }

  companion object {
    private const val TAG = "VitruvianWand"
  }
}
