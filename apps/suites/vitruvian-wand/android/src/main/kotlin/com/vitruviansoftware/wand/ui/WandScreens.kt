// Copyright (c) 2026 VitruvianSoftware

package com.vitruviansoftware.wand.ui

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.drawscope.Stroke
import com.vitruviansoftware.wand.ble.BleConnectionState
import com.vitruviansoftware.wand.ble.DiscoveredController
import com.vitruviansoftware.wand.core.BrightnessKind
import com.vitruviansoftware.wand.core.DPadDirection
import com.vitruviansoftware.wand.core.MediaKind
import com.vitruviansoftware.wand.core.NavKind
import com.vitruviansoftware.wand.core.SystemKind
import com.vitruviansoftware.wand.core.VolumeKind
import com.vitruviansoftware.wand.core.WandAction
import com.vitruviansoftware.wand.core.WandBinding
import com.vitruviansoftware.wand.core.WandButton
import com.vitruviansoftware.wand.core.WandConfig
import com.vitruviansoftware.wand.core.WandPress
import com.vitruviansoftware.wand.core.WandSample
import com.vitruviansoftware.wand.core.WandSettings
import com.vitruviansoftware.wand.core.WandTriggerMode
import com.vitruviansoftware.wand.service.WandAccessibilityService
import com.vitruviansoftware.wand.service.WandRuntimeSnapshot
import dev.vitruvian.design.Banner
import dev.vitruvian.design.BannerTone
import dev.vitruvian.design.ButtonVariant
import dev.vitruvian.design.Code
import dev.vitruvian.design.CopyButton
import dev.vitruvian.design.EmptyState
import dev.vitruvian.design.Hit
import dev.vitruvian.design.HostChip
import dev.vitruvian.design.Label
import dev.vitruvian.design.ListItem
import dev.vitruvian.design.MenuDivider
import dev.vitruvian.design.Meter
import dev.vitruvian.design.Metric
import dev.vitruvian.design.NavItem
import dev.vitruvian.design.OptionSheet
import dev.vitruvian.design.Plate
import dev.vitruvian.design.Rail
import dev.vitruvian.design.Section
import dev.vitruvian.design.SelectOption
import dev.vitruvian.design.SheetOption
import dev.vitruvian.design.Space
import dev.vitruvian.design.Status
import dev.vitruvian.design.StatusTone
import dev.vitruvian.design.TabBar
import dev.vitruvian.design.Tag
import dev.vitruvian.design.TagTone
import dev.vitruvian.design.Toast
import dev.vitruvian.design.TopBar
import dev.vitruvian.design.VButton
import dev.vitruvian.design.VSelect
import dev.vitruvian.design.VSlider
import dev.vitruvian.design.VSwitch
import dev.vitruvian.design.VText
import dev.vitruvian.design.Vitruvian
import dev.vitruvian.design.VitruvianIcons
import dev.vitruvian.design.VitruvianType
import kotlin.math.roundToInt

/** Installed launcher application entry for the `LaunchApp` binding picker. */
data class InstalledAppEntry(
    val packageName: String,
    val label: String,
)

private enum class WandTab(val id: String, val label: String) {
  CONNECTION("connection", "Connection"),
  CONTROLS("controls", "Controls"),
  BINDINGS("bindings", "Bindings"),
  TEST_MODE("test", "Test Mode"),
}

private enum class TvSubScreen {
  NONE,
  SCAN_AND_PAIR,
  ADB_PERMISSION,
}

const val ADB_GRANT_COMMAND: String =
    "adb shell pm grant com.vitruviansoftware.wand android.permission.WRITE_SECURE_SETTINGS"

/** Queries launcher-capable applications on the device for the `LaunchApp` action picker. */
fun queryInstalledLauncherApps(context: Context): List<InstalledAppEntry> {
  val pm = context.packageManager
  val mainIntent = Intent(Intent.ACTION_MAIN).apply { addCategory(Intent.CATEGORY_LAUNCHER) }
  val leanbackIntent =
      Intent(Intent.ACTION_MAIN).apply { addCategory(Intent.CATEGORY_LEANBACK_LAUNCHER) }
  val seen = LinkedHashMap<String, InstalledAppEntry>()
  val flags = PackageManager.MATCH_ALL
  for (intent in listOf(mainIntent, leanbackIntent)) {
    val resolved =
        try {
          pm.queryIntentActivities(intent, flags)
        } catch (e: Exception) {
          Log.w(TAG, "Failed to query launcher activities", e)
          emptyList()
        }
    for (info in resolved) {
      val pkg = info.activityInfo?.packageName ?: continue
      if (seen.containsKey(pkg)) continue
      val label =
          try {
            info.loadLabel(pm)?.toString()?.takeIf { it.isNotBlank() } ?: pkg
          } catch (e: Exception) {
            Log.w(TAG, "Failed to load application label for $pkg", e)
            pkg
          }
      seen[pkg] = InstalledAppEntry(packageName = pkg, label = label)
    }
  }
  return seen.values.sortedBy { it.label.lowercase() }
}

private const val TAG = "VitruvianWand"

/**
 * Attempts to enable [WandAccessibilityService] directly using `WRITE_SECURE_SETTINGS`, preserving
 * any existing colon-separated accessibility services.
 */
fun tryEnableAccessibilityViaSecureSettings(context: Context): Result<Unit> {
  val granted =
      context.checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) ==
          PackageManager.PERMISSION_GRANTED
  if (!granted) {
    return Result.failure(
        SecurityException("WRITE_SECURE_SETTINGS not granted yet. Run the ADB command first."),
    )
  }
  return try {
    val resolver = context.contentResolver
    val component = "${context.packageName}/${WandAccessibilityService::class.java.name}"
    val existing =
        Settings.Secure.getString(
                resolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            )
            ?.trim()
            .orEmpty()

    val entries = existing.split(':').map { it.trim() }.filter { it.isNotEmpty() }.toMutableList()

    val shortComponent = "${context.packageName}/.service.WandAccessibilityService"
    val alreadyPresent =
        entries.any {
          it.equals(component, ignoreCase = true) || it.equals(shortComponent, ignoreCase = true)
        }
    if (!alreadyPresent) {
      entries.add(component)
    }
    val merged = entries.joinToString(":")
    Settings.Secure.putString(
        resolver,
        Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        merged,
    )
    Settings.Secure.putInt(
        resolver,
        Settings.Secure.ACCESSIBILITY_ENABLED,
        1,
    )
    Result.success(Unit)
  } catch (e: Exception) {
    Log.e(TAG, "Failed to enable accessibility service via WRITE_SECURE_SETTINGS", e)
    Result.failure(e)
  }
}

/**
 * Focus-aware wrapper that enlarges focus borders on Android TV so every interactive group is
 * clearly D-pad navigable.
 */
@Composable
private fun TvFocusableSurface(
    isTv: Boolean,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
  var focused by remember { mutableStateOf(false) }
  val borderColor = if (focused && isTv) Vitruvian.accent else Vitruvian.line
  Box(
      modifier =
          modifier
              .onFocusChanged { focused = it.hasFocus }
              .then(
                  if (isTv) {
                    Modifier.border(width = Space.s1, color = borderColor).padding(Space.s2)
                  } else {
                    Modifier
                  },
              ),
  ) {
    content()
  }
}

/** Framed panel built from design-system [Plate], [Label], [VText], [Tag], and [MenuDivider]. */
@Composable
private fun WandPanel(
    label: String,
    title: String,
    meta: String,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
  Plate(
      modifier = modifier.fillMaxWidth().background(Vitruvian.surface),
  ) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(Space.s4),
        verticalArrangement = Arrangement.spacedBy(Space.s3),
    ) {
      Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.SpaceBetween,
          verticalAlignment = Alignment.CenterVertically,
      ) {
        Column(verticalArrangement = Arrangement.spacedBy(Space.s1)) {
          Label(text = label)
          VText(
              text = title,
              style = VitruvianType.barTitle,
              color = Vitruvian.text,
          )
        }
        Tag(
            text = meta,
            tone = TagTone.Outline,
        )
      }
      MenuDivider()
      Column(
          modifier = Modifier.fillMaxWidth(),
          verticalArrangement = Arrangement.spacedBy(Space.s2),
      ) {
        content()
      }
    }
  }
}

/** Labeled progress bar built from design-system [Label], [VText], and [Meter]. */
@Composable
private fun LabeledMeter(
    label: String,
    value: String,
    progress: Float,
    warn: Boolean = false,
    modifier: Modifier = Modifier,
) {
  Column(
      modifier = modifier.fillMaxWidth(),
      verticalArrangement = Arrangement.spacedBy(Space.s1),
  ) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
      Label(text = label)
      VText(
          text = value,
          style = VitruvianType.mono,
          color = if (warn) Vitruvian.warn else Vitruvian.accentText,
      )
    }
    Meter(
        fraction = progress,
        fillColor = if (warn) Vitruvian.warn else Vitruvian.accent,
    )
  }
}

/** Root Compose screen for Vitruvian Wand on both Android phones/tablets and Android TV. */
@Composable
fun WandAppScreen(
    isTv: Boolean,
    runtime: WandRuntimeSnapshot,
    config: WandConfig,
    installedApps: List<InstalledAppEntry>,
    hasBlePermissions: Boolean,
    onRequestPermissions: () -> Unit,
    onOpenAccessibilitySettings: () -> Unit,
    onConnect: () -> Unit,
    onDisconnect: () -> Unit,
    onRecalibrate: () -> Unit,
    onStartPairingScan: () -> Unit,
    onPairAndConnect: (String) -> Unit,
    onTryEnableViaAdb: () -> String,
    onUpdateConfig: (WandConfig) -> Unit,
    onResetDefaults: () -> Unit,
    onSetTestMode: (Boolean) -> Unit,
    onDismissSaveError: () -> Unit = {},
) {
  var activeTab by remember { mutableStateOf(WandTab.CONNECTION) }
  var tvSubScreen by remember { mutableStateOf(TvSubScreen.NONE) }

  val navItems =
      listOf(
          NavItem(
              key = WandTab.CONNECTION.id,
              label = WandTab.CONNECTION.label,
              iconPath = VitruvianIcons.MOUSE_POINTER,
              onSelect = {
                tvSubScreen = TvSubScreen.NONE
                activeTab = WandTab.CONNECTION
              },
          ),
          NavItem(
              key = WandTab.CONTROLS.id,
              label = WandTab.CONTROLS.label,
              iconPath = VitruvianIcons.SETTINGS,
              onSelect = {
                tvSubScreen = TvSubScreen.NONE
                activeTab = WandTab.CONTROLS
              },
          ),
          NavItem(
              key = WandTab.BINDINGS.id,
              label = WandTab.BINDINGS.label,
              iconPath = VitruvianIcons.GRID_2X2,
              onSelect = {
                tvSubScreen = TvSubScreen.NONE
                activeTab = WandTab.BINDINGS
              },
          ),
          NavItem(
              key = WandTab.TEST_MODE.id,
              label = WandTab.TEST_MODE.label,
              iconPath = VitruvianIcons.ACTIVITY,
              onSelect = {
                tvSubScreen = TvSubScreen.NONE
                activeTab = WandTab.TEST_MODE
              },
          ),
      )

  val statusTone =
      when (runtime.connectionState) {
        BleConnectionState.CONNECTED -> StatusTone.Ok
        BleConnectionState.SCANNING,
        BleConnectionState.CONNECTING,
        BleConnectionState.PAIRING, -> StatusTone.Run
        BleConnectionState.DISCONNECTED -> StatusTone.Neutral
      }

  Column(
      modifier = Modifier.fillMaxSize().background(Vitruvian.bg),
  ) {
    TopBar(
        title = if (isTv) "VITRUVIAN WAND // ANDROID TV" else "VITRUVIAN WAND // AIR MOUSE",
        showMark = !isTv,
        trailing = {
          HostChip(
              text = runtime.connectionState.name.lowercase(),
              tone = statusTone,
              onClick = {
                tvSubScreen = TvSubScreen.NONE
                activeTab = WandTab.CONNECTION
              },
          )
          Tag(
              text = if (isTv) "TV MODE" else "PHONE MODE",
              tone = if (isTv) TagTone.Accent else TagTone.Neutral,
          )
        },
    )

    if (runtime.saveError != null) {
      Box(
          modifier = Modifier.fillMaxWidth().padding(horizontal = Space.s4, vertical = Space.s2),
      ) {
        Toast(
            title = "Failed to save settings",
            tone = StatusTone.Crit,
            detail = runtime.saveError,
            onDismiss = onDismissSaveError,
        )
      }
    }

    if (isTv) {
      Row(modifier = Modifier.weight(1f).fillMaxWidth()) {
        Rail(
            items = navItems,
            selectedKey = activeTab.id,
            dockOpen = tvSubScreen == TvSubScreen.SCAN_AND_PAIR,
            onToggleDock = {
              tvSubScreen =
                  if (tvSubScreen == TvSubScreen.SCAN_AND_PAIR) {
                    TvSubScreen.NONE
                  } else {
                    onStartPairingScan()
                    TvSubScreen.SCAN_AND_PAIR
                  }
            },
            hostLabel = runtime.connectionState.name,
            hostTone = statusTone,
        )
        Box(
            modifier = Modifier.weight(1f).fillMaxHeight(),
        ) {
          WandTabBody(
              isTv = true,
              activeTab = activeTab,
              tvSubScreen = tvSubScreen,
              onChangeTvSubScreen = { tvSubScreen = it },
              runtime = runtime,
              config = config,
              installedApps = installedApps,
              hasBlePermissions = hasBlePermissions,
              onRequestPermissions = onRequestPermissions,
              onOpenAccessibilitySettings = onOpenAccessibilitySettings,
              onConnect = onConnect,
              onDisconnect = onDisconnect,
              onRecalibrate = onRecalibrate,
              onStartPairingScan = onStartPairingScan,
              onPairAndConnect = onPairAndConnect,
              onTryEnableViaAdb = onTryEnableViaAdb,
              onUpdateConfig = onUpdateConfig,
              onResetDefaults = onResetDefaults,
              onSetTestMode = onSetTestMode,
          )
        }
      }
    } else {
      Box(
          modifier = Modifier.weight(1f).fillMaxWidth(),
      ) {
        WandTabBody(
            isTv = false,
            activeTab = activeTab,
            tvSubScreen = tvSubScreen,
            onChangeTvSubScreen = { tvSubScreen = it },
            runtime = runtime,
            config = config,
            installedApps = installedApps,
            hasBlePermissions = hasBlePermissions,
            onRequestPermissions = onRequestPermissions,
            onOpenAccessibilitySettings = onOpenAccessibilitySettings,
            onConnect = onConnect,
            onDisconnect = onDisconnect,
            onRecalibrate = onRecalibrate,
            onStartPairingScan = onStartPairingScan,
            onPairAndConnect = onPairAndConnect,
            onTryEnableViaAdb = onTryEnableViaAdb,
            onUpdateConfig = onUpdateConfig,
            onResetDefaults = onResetDefaults,
            onSetTestMode = onSetTestMode,
        )
      }
      TabBar(
          items = navItems,
          selectedKey = activeTab.id,
      )
    }
  }
}

@Composable
private fun WandTabBody(
    isTv: Boolean,
    activeTab: WandTab,
    tvSubScreen: TvSubScreen,
    onChangeTvSubScreen: (TvSubScreen) -> Unit,
    runtime: WandRuntimeSnapshot,
    config: WandConfig,
    installedApps: List<InstalledAppEntry>,
    hasBlePermissions: Boolean,
    onRequestPermissions: () -> Unit,
    onOpenAccessibilitySettings: () -> Unit,
    onConnect: () -> Unit,
    onDisconnect: () -> Unit,
    onRecalibrate: () -> Unit,
    onStartPairingScan: () -> Unit,
    onPairAndConnect: (String) -> Unit,
    onTryEnableViaAdb: () -> String,
    onUpdateConfig: (WandConfig) -> Unit,
    onResetDefaults: () -> Unit,
    onSetTestMode: (Boolean) -> Unit,
    onDismissSaveError: () -> Unit = {},
) {
  when {
    tvSubScreen == TvSubScreen.SCAN_AND_PAIR -> {
      ScanAndPairScreen(
          isTv = isTv,
          runtime = runtime,
          onStartScan = onStartPairingScan,
          onPairDevice = onPairAndConnect,
          onBack = { onChangeTvSubScreen(TvSubScreen.NONE) },
      )
    }
    tvSubScreen == TvSubScreen.ADB_PERMISSION -> {
      AdbPermissionScreen(
          isTv = isTv,
          serviceEnabled = runtime.serviceRunning,
          onTryEnable = onTryEnableViaAdb,
          onOpenAccessibilitySettings = onOpenAccessibilitySettings,
          onBack = { onChangeTvSubScreen(TvSubScreen.NONE) },
      )
    }
    activeTab == WandTab.CONNECTION -> {
      ConnectionTab(
          isTv = isTv,
          runtime = runtime,
          settings = config.settings,
          hasBlePermissions = hasBlePermissions,
          onRequestPermissions = onRequestPermissions,
          onOpenAccessibilitySettings = onOpenAccessibilitySettings,
          onOpenScanAndPair = {
            onStartPairingScan()
            onChangeTvSubScreen(TvSubScreen.SCAN_AND_PAIR)
          },
          onOpenAdbScreen = { onChangeTvSubScreen(TvSubScreen.ADB_PERMISSION) },
          onConnect = onConnect,
          onDisconnect = onDisconnect,
          onRecalibrate = onRecalibrate,
          onToggleAutoReconnect = { enabled ->
            onUpdateConfig(
                config.copy(settings = config.settings.copy(autoReconnect = enabled)),
            )
          },
      )
    }
    activeTab == WandTab.CONTROLS -> {
      ControlsTab(
          isTv = isTv,
          settings = config.settings,
          onUpdateSettings = { updated -> onUpdateConfig(config.copy(settings = updated)) },
          onResetDefaults = onResetDefaults,
      )
    }
    activeTab == WandTab.BINDINGS -> {
      BindingsTab(
          isTv = isTv,
          config = config,
          installedApps = installedApps,
          onUpdateConfig = onUpdateConfig,
          onResetDefaults = onResetDefaults,
      )
    }
    activeTab == WandTab.TEST_MODE -> {
      TestModeTab(
          isTv = isTv,
          runtime = runtime,
          onSetTestMode = onSetTestMode,
      )
    }
  }
}

@Composable
private fun ConnectionTab(
    isTv: Boolean,
    runtime: WandRuntimeSnapshot,
    settings: WandSettings,
    hasBlePermissions: Boolean,
    onRequestPermissions: () -> Unit,
    onOpenAccessibilitySettings: () -> Unit,
    onOpenScanAndPair: () -> Unit,
    onOpenAdbScreen: () -> Unit,
    onConnect: () -> Unit,
    onDisconnect: () -> Unit,
    onRecalibrate: () -> Unit,
    onToggleAutoReconnect: (Boolean) -> Unit,
) {
  val scroll = rememberScrollState()
  Column(
      modifier = Modifier.fillMaxSize().verticalScroll(scroll).padding(Space.s4),
      verticalArrangement = Arrangement.spacedBy(Space.s4),
  ) {
    if (!hasBlePermissions) {
      Banner(
          tone = BannerTone.Warn,
          label = "Bluetooth & Notification Permissions Required",
          body =
              "Grant Nearby Devices (Bluetooth scan & connect) and notification permissions so Vitruvian Wand can discover and monitor your Daydream controller.",
          actions = {
            VButton(
                label = "Grant Permissions",
                onClick = onRequestPermissions,
                variant = ButtonVariant.Primary,
            )
          },
      )
    }

    if (!runtime.serviceRunning) {
      Banner(
          tone = BannerTone.Warn,
          label = "Accessibility Service Not Enabled",
          body =
              if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                "Android 13+ blocks sideloaded accessibility services until unlocked: open Settings > Apps > Vitruvian Wand > ⋮ (top-right) > Allow restricted settings, then enable Vitruvian Wand in Accessibility Settings."
              } else {
                "Enable Vitruvian Wand in Android Accessibility Settings so the app can render the air-mouse cursor and dispatch taps, drags, and system navigation."
              },
          actions = {
            Row(horizontalArrangement = Arrangement.spacedBy(Space.s3)) {
              VButton(
                  label = "Enable Accessibility",
                  onClick = onOpenAccessibilitySettings,
                  variant = ButtonVariant.Primary,
              )
              VButton(
                  label = "ADB Permission Setup",
                  onClick = onOpenAdbScreen,
                  variant = ButtonVariant.Secondary,
              )
            }
          },
      )
    }

    TvFocusableSurface(isTv = isTv) {
      WandPanel(
          label = "CONTROLLER STATUS",
          title = runtime.statusDetail ?: "Daydream Controller",
          meta = if (runtime.serviceRunning) "SERVICE ACTIVE" else "SERVICE INACTIVE",
      ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
          Status(
              tone =
                  when (runtime.connectionState) {
                    BleConnectionState.CONNECTED -> StatusTone.Ok
                    BleConnectionState.SCANNING,
                    BleConnectionState.CONNECTING,
                    BleConnectionState.PAIRING, -> StatusTone.Run
                    BleConnectionState.DISCONNECTED -> StatusTone.Neutral
                  },
              text = runtime.connectionState.name,
          )
          val batText = runtime.batteryPercent?.let { "$it%" } ?: "—"
          Metric(
              label = "BATTERY",
              value = batText,
              delta = if ((runtime.batteryPercent ?: 100) < 15) "LOW (< 15%)" else "BLE 0x180F",
          )
        }

        if (runtime.batteryPercent != null) {
          Spacer(modifier = Modifier.height(Space.s3))
          LabeledMeter(
              label = "Charge Level",
              value = "${runtime.batteryPercent}%",
              progress = runtime.batteryPercent / 100f,
              warn = runtime.batteryPercent < 15,
          )
        }

        Spacer(modifier = Modifier.height(Space.s4))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(Space.s3),
        ) {
          if (runtime.connectionState == BleConnectionState.CONNECTED) {
            VButton(
                label = "Disconnect",
                onClick = onDisconnect,
                variant = ButtonVariant.Danger,
            )
          } else {
            VButton(
                label = "Connect",
                onClick = onConnect,
                variant = ButtonVariant.Primary,
            )
          }
          VButton(
              label = "Recalibrate",
              onClick = onRecalibrate,
              variant = ButtonVariant.Secondary,
          )
          VButton(
              label = "Scan & Pair",
              onClick = onOpenScanAndPair,
              variant = ButtonVariant.Secondary,
          )
        }

        Spacer(modifier = Modifier.height(Space.s4))
        MenuDivider()
        Spacer(modifier = Modifier.height(Space.s3))

        VSwitch(
            checked = settings.autoReconnect,
            onCheckedChange = onToggleAutoReconnect,
            label = "Auto-reconnect on disconnect",
        )
      }
    }

    TvFocusableSurface(isTv = isTv) {
      WandPanel(
          label = "ACCESSIBILITY & TV SETUP",
          title = "System Integration",
          meta = if (isTv) "ANDROID TV" else "PHONE / TABLET",
      ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(Space.s3),
        ) {
          VButton(
              label = "Enable Accessibility",
              onClick = onOpenAccessibilitySettings,
              variant = ButtonVariant.Secondary,
          )
          VButton(
              label = "ADB Permission (TV)",
              onClick = onOpenAdbScreen,
              variant = ButtonVariant.Ghost,
          )
        }
      }
    }
  }
}

@Composable
private fun ScanAndPairScreen(
    isTv: Boolean,
    runtime: WandRuntimeSnapshot,
    onStartScan: () -> Unit,
    onPairDevice: (String) -> Unit,
    onBack: () -> Unit,
) {
  val scroll = rememberScrollState()
  Column(
      modifier = Modifier.fillMaxSize().verticalScroll(scroll).padding(Space.s4),
      verticalArrangement = Arrangement.spacedBy(Space.s4),
  ) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
      Label(text = "SCAN & PAIR DAYDREAM CONTROLLER")
      Row(horizontalArrangement = Arrangement.spacedBy(Space.s3)) {
        VButton(
            label = "Rescan",
            onClick = onStartScan,
            variant = ButtonVariant.Primary,
        )
        VButton(
            label = "Back",
            onClick = onBack,
            variant = ButtonVariant.Secondary,
        )
      }
    }

    Banner(
        tone = BannerTone.Info,
        label = "Put Controller in Pairing Mode",
        body =
            "Hold the Home button on your Daydream controller until the status LED blinks, then select it below to bond and connect.",
    )

    if (runtime.discoveredControllers.isEmpty()) {
      EmptyState(
          label = "BLE DISCOVERY",
          title =
              if (runtime.connectionState == BleConnectionState.SCANNING) {
                "Scanning for Daydream controllers…"
              } else {
                "No controllers found yet"
              },
          body =
              "Filtered by name \"Daydream controller\" and service 0000fe55-0000-1000-8000-00805f9b34fb.",
      )
    } else {
      Section {
        Label(text = "Discovered Controllers (${runtime.discoveredControllers.size})")
        Spacer(modifier = Modifier.height(Space.s3))
        runtime.discoveredControllers.forEach { dev: DiscoveredController ->
          TvFocusableSurface(isTv = isTv) {
            ListItem(
                title = dev.name,
                subtitle = "${dev.address} · RSSI ${dev.rssi} dBm",
                trailing = {
                  Tag(
                      text = if (dev.bonded) "BONDED" else "PAIR",
                      tone = if (dev.bonded) TagTone.Ok else TagTone.Accent,
                  )
                },
                onClick = { onPairDevice(dev.address) },
            )
          }
        }
      }
    }
  }
}

@Composable
private fun AdbPermissionScreen(
    isTv: Boolean,
    serviceEnabled: Boolean,
    onTryEnable: () -> String,
    onOpenAccessibilitySettings: () -> Unit,
    onBack: () -> Unit,
) {
  var statusMessage by remember { mutableStateOf<String?>(null) }
  val scroll = rememberScrollState()

  Column(
      modifier = Modifier.fillMaxSize().verticalScroll(scroll).padding(Space.s4),
      verticalArrangement = Arrangement.spacedBy(Space.s4),
  ) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
      Label(text = "ANDROID TV // ADB PERMISSION SETUP")
      VButton(
          label = "Back",
          onClick = onBack,
          variant = ButtonVariant.Secondary,
      )
    }

    WandPanel(
        label = "STEP 1",
        title = "Grant WRITE_SECURE_SETTINGS over ADB",
        meta = if (serviceEnabled) "ENABLED" else "REQUIRED ON TV",
    ) {
      VText(
          text =
              "Many Android TV builds hide the system Accessibility Settings screen. Run this one-time ADB command from your computer, then press Try Enable:",
          style = VitruvianType.body,
          color = Vitruvian.textDim,
      )
      Spacer(modifier = Modifier.height(Space.s3))
      Code(code = ADB_GRANT_COMMAND)
      Spacer(modifier = Modifier.height(Space.s3))
      Row(horizontalArrangement = Arrangement.spacedBy(Space.s3)) {
        CopyButton(value = ADB_GRANT_COMMAND, label = "Copy ADB Command")
        TvFocusableSurface(isTv = isTv) {
          VButton(
              label = "Try enable",
              onClick = { statusMessage = onTryEnable() },
              variant = ButtonVariant.Primary,
          )
        }
        VButton(
            label = "Open System Settings",
            onClick = onOpenAccessibilitySettings,
            variant = ButtonVariant.Ghost,
        )
      }

      if (statusMessage != null) {
        Spacer(modifier = Modifier.height(Space.s3))
        Banner(
            tone = if (serviceEnabled) BannerTone.Info else BannerTone.Warn,
            label = "Result",
            body = statusMessage!!,
        )
      }
    }
  }
}

@Composable
private fun ControlsTab(
    isTv: Boolean,
    settings: WandSettings,
    onUpdateSettings: (WandSettings) -> Unit,
    onResetDefaults: () -> Unit,
) {
  val scroll = rememberScrollState()
  Column(
      modifier = Modifier.fillMaxSize().verticalScroll(scroll).padding(Space.s4),
      verticalArrangement = Arrangement.spacedBy(Space.s4),
  ) {
    TvFocusableSurface(isTv = isTv) {
      WandPanel(
          label = "POINTER & GYRO",
          title = "Sensitivity & Smoothing",
          meta = "ENGINE SETTINGS",
      ) {
        VSlider(
            value = settings.touchSensitivity,
            onValueChange = { onUpdateSettings(settings.copy(touchSensitivity = it)) },
            label = "Touch Sensitivity",
            valueRange = 100f..1000f,
            formatValue = { "${it.roundToInt()}" },
        )
        Spacer(modifier = Modifier.height(Space.s3))
        VSlider(
            value = settings.gyroXSpeed,
            onValueChange = { onUpdateSettings(settings.copy(gyroXSpeed = it)) },
            label = "Gyro Horizontal Speed (Yaw)",
            valueRange = 2f..60f,
            formatValue = { "${it.roundToInt()}" },
        )
        Spacer(modifier = Modifier.height(Space.s3))
        VSlider(
            value = settings.gyroYSpeed,
            onValueChange = { onUpdateSettings(settings.copy(gyroYSpeed = it)) },
            label = "Gyro Vertical Speed (Pitch)",
            valueRange = 2f..60f,
            formatValue = { "${it.roundToInt()}" },
        )
        Spacer(modifier = Modifier.height(Space.s3))
        VSlider(
            value = settings.gyroDeadzone,
            onValueChange = { onUpdateSettings(settings.copy(gyroDeadzone = it)) },
            label = "Gyro Deadzone",
            valueRange = 0f..0.20f,
            unit = "%",
            formatValue = { "${(it * 100f).roundToInt()}" },
        )
        Spacer(modifier = Modifier.height(Space.s3))
        VSlider(
            value = settings.touchDeadzone,
            onValueChange = { onUpdateSettings(settings.copy(touchDeadzone = it)) },
            label = "Touch Deadzone",
            valueRange = 0f..0.05f,
            unit = "‰",
            formatValue = { "${(it * 1000f).roundToInt()}" },
        )
        Spacer(modifier = Modifier.height(Space.s3))
        VSlider(
            value = settings.accelerationCurve,
            onValueChange = { onUpdateSettings(settings.copy(accelerationCurve = it)) },
            label = "Acceleration Curve",
            valueRange = 1.0f..3.0f,
            unit = "x",
            formatValue = { "${(it * 10f).roundToInt() / 10f}" },
        )
        Spacer(modifier = Modifier.height(Space.s3))
        VSlider(
            value = settings.emaSmoothing,
            onValueChange = { onUpdateSettings(settings.copy(emaSmoothing = it)) },
            label = "Smoothing",
            valueRange = 0f..0.95f,
            unit = "%",
            formatValue = { "${(it * 100f).roundToInt()}" },
        )
      }
    }

    TvFocusableSurface(isTv = isTv) {
      WandPanel(
          label = "CURSOR OVERLAY",
          title = "Visibility & Size",
          meta = "ACCESSIBILITY OVERLAY",
      ) {
        VSwitch(
            checked = settings.overlayCursor,
            onCheckedChange = { onUpdateSettings(settings.copy(overlayCursor = it)) },
            label = "Enable cursor overlay",
        )
        Spacer(modifier = Modifier.height(Space.s3))
        VSlider(
            value = settings.overlayCursorSize,
            onValueChange = { onUpdateSettings(settings.copy(overlayCursorSize = it)) },
            label = "Cursor size",
            valueRange = 12f..64f,
            unit = " dp",
            formatValue = { "${it.roundToInt()}" },
        )
      }
    }

    TvFocusableSurface(isTv = isTv) {
      WandPanel(
          label = "SCROLL & TAP",
          title = "Gesture Behavior",
          meta = "SWIPE & TAP",
      ) {
        VSlider(
            value = settings.scrollStrength,
            onValueChange = { onUpdateSettings(settings.copy(scrollStrength = it)) },
            label = "Scroll strength",
            valueRange = 0.25f..3.0f,
            unit = "x",
            formatValue = { "${(it * 10f).roundToInt() / 10f}" },
        )
        Spacer(modifier = Modifier.height(Space.s3))
        VSwitch(
            checked = settings.reverseScroll,
            onCheckedChange = { onUpdateSettings(settings.copy(reverseScroll = it)) },
            label = "Reverse scroll direction",
        )
        Spacer(modifier = Modifier.height(Space.s2))
        VSwitch(
            checked = settings.horizontalScroll,
            onCheckedChange = { onUpdateSettings(settings.copy(horizontalScroll = it)) },
            label = "Enable horizontal scroll",
        )
        Spacer(modifier = Modifier.height(Space.s2))
        VSwitch(
            checked = settings.tapInTouchMode,
            onCheckedChange = { onUpdateSettings(settings.copy(tapInTouchMode = it)) },
            label = "Touchpad tap clicks in touch mode",
        )
        Spacer(modifier = Modifier.height(Space.s2))
        VSwitch(
            checked = settings.tapInGyroMode,
            onCheckedChange = { onUpdateSettings(settings.copy(tapInGyroMode = it)) },
            label = "Touchpad tap clicks in gyro mode",
        )
      }
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.End,
    ) {
      VButton(
          label = "Reset All Controls to Defaults",
          onClick = onResetDefaults,
          variant = ButtonVariant.Danger,
      )
    }
  }
}

private data class EditingSlot(
    val button: WandButton,
    val press: WandPress,
)

private data class PresetActionChoice(
    val id: String,
    val label: String,
    val sub: String,
    val action: WandAction?,
)

@Composable
private fun BindingsTab(
    isTv: Boolean,
    config: WandConfig,
    installedApps: List<InstalledAppEntry>,
    onUpdateConfig: (WandConfig) -> Unit,
    onResetDefaults: () -> Unit,
) {
  var editingSlot by remember { mutableStateOf<EditingSlot?>(null) }
  var pickingAppForSlot by remember { mutableStateOf<EditingSlot?>(null) }
  val scroll = rememberScrollState()

  val presetChoices = remember {
    listOf(
        PresetActionChoice(
            "tap", "Tap / Left Click", "Primary tap at cursor", WandAction.LeftClick),
        PresetActionChoice(
            "secondary", "Secondary Click", "Long-press at cursor", WandAction.RightClick),
        PresetActionChoice(
            "gyro",
            "Toggle Gyro Mode",
            "Switch between touchpad and air-mouse",
            WandAction.ToggleGyro),
        PresetActionChoice(
            "nav_back", "Navigate: Back", "Global Back action", WandAction.Nav(NavKind.BACK)),
        PresetActionChoice(
            "nav_home", "Navigate: Home", "Global Home action", WandAction.Nav(NavKind.HOME)),
        PresetActionChoice(
            "nav_recents",
            "Navigate: Recents",
            "Open recent apps",
            WandAction.Nav(NavKind.RECENTS)),
        PresetActionChoice(
            "nav_notif",
            "Navigate: Notifications",
            "Expand notification shade",
            WandAction.Nav(NavKind.NOTIFICATIONS)),
        PresetActionChoice(
            "nav_qs",
            "Navigate: Quick Settings",
            "Expand quick settings",
            WandAction.Nav(NavKind.QUICK_SETTINGS)),
        PresetActionChoice(
            "dpad_center",
            "TV D-Pad: Center / Select",
            "Click focused TV element",
            WandAction.DPad(DPadDirection.CENTER)),
        PresetActionChoice(
            "dpad_up", "TV D-Pad: Up", "Move focus up", WandAction.DPad(DPadDirection.UP)),
        PresetActionChoice(
            "dpad_down", "TV D-Pad: Down", "Move focus down", WandAction.DPad(DPadDirection.DOWN)),
        PresetActionChoice(
            "dpad_left", "TV D-Pad: Left", "Move focus left", WandAction.DPad(DPadDirection.LEFT)),
        PresetActionChoice(
            "dpad_right",
            "TV D-Pad: Right",
            "Move focus right",
            WandAction.DPad(DPadDirection.RIGHT)),
        PresetActionChoice("scroll_up", "Scroll Up", "Swipe content up", WandAction.Scroll(0f, 1f)),
        PresetActionChoice(
            "scroll_down", "Scroll Down", "Swipe content down", WandAction.Scroll(0f, -1f)),
        PresetActionChoice(
            "scroll_left", "Scroll Left", "Swipe content left", WandAction.Scroll(-1f, 0f)),
        PresetActionChoice(
            "scroll_right", "Scroll Right", "Swipe content right", WandAction.Scroll(1f, 0f)),
        PresetActionChoice(
            "vol_up", "Volume Up", "Raise media volume", WandAction.Volume(VolumeKind.UP)),
        PresetActionChoice(
            "vol_down", "Volume Down", "Lower media volume", WandAction.Volume(VolumeKind.DOWN)),
        PresetActionChoice(
            "vol_mute", "Volume Mute", "Toggle mute", WandAction.Volume(VolumeKind.MUTE)),
        PresetActionChoice(
            "brightness_up",
            "Brightness Up",
            "Increase screen brightness",
            WandAction.Brightness(BrightnessKind.UP)),
        PresetActionChoice(
            "brightness_down",
            "Brightness Down",
            "Decrease screen brightness",
            WandAction.Brightness(BrightnessKind.DOWN)),
        PresetActionChoice(
            "media_pp",
            "Media: Play / Pause",
            "Dispatch play/pause key",
            WandAction.Media(MediaKind.PLAY_PAUSE)),
        PresetActionChoice(
            "media_next",
            "Media: Next Track",
            "Dispatch next track key",
            WandAction.Media(MediaKind.NEXT)),
        PresetActionChoice(
            "media_prev",
            "Media: Previous Track",
            "Dispatch previous track key",
            WandAction.Media(MediaKind.PREVIOUS)),
        PresetActionChoice(
            "sys_copy",
            "System: Copy",
            "Copy selection in focused input",
            WandAction.System(SystemKind.COPY)),
        PresetActionChoice(
            "sys_paste",
            "System: Paste",
            "Paste clipboard into focused input",
            WandAction.System(SystemKind.PASTE)),
        PresetActionChoice(
            "sys_app_switcher",
            "System: App Switcher",
            "Open recent apps switcher",
            WandAction.System(SystemKind.APP_SWITCHER)),
        PresetActionChoice(
            "screen_off", "Screen Off (Lock)", "Lock screen (Android 9+)", WandAction.ScreenOff),
        PresetActionChoice(
            "assistant", "Assistant", "Launch voice assistant", WandAction.Assistant),
        PresetActionChoice(
            "voice_typing", "Voice Typing", "Launch voice command", WandAction.VoiceTyping),
        PresetActionChoice(
            "launch_app", "Launch Installed App…", "Choose an installed app to launch", null),
        PresetActionChoice("unbind", "Unbound (None)", "Disable this press slot", null),
    )
  }

  val triggerOptions = remember {
    WandTriggerMode.entries.map { SelectOption(value = it.wire, label = it.label) }
  }

  Column(
      modifier = Modifier.fillMaxSize().verticalScroll(scroll).padding(Space.s4),
      verticalArrangement = Arrangement.spacedBy(Space.s4),
  ) {
    WandButton.entries.forEach { button ->
      Section {
        Label(text = button.label)
        Spacer(modifier = Modifier.height(Space.s3))
        WandPress.entries.forEach { press ->
          val current = config.bindingFor(button, press)
          val subtitle =
              current?.let { "${it.action.displayLabel()} · ${it.trigger.label}" } ?: "Unbound"
          TvFocusableSurface(isTv = isTv) {
            Column(
                modifier = Modifier.fillMaxWidth().background(Vitruvian.surface).padding(Space.s3),
            ) {
              ListItem(
                  title = "${button.label} — ${press.label}",
                  subtitle = subtitle,
                  trailing = {
                    Tag(
                        text = current?.trigger?.label ?: "NONE",
                        tone = if (current != null) TagTone.Accent else TagTone.Neutral,
                    )
                  },
                  onClick = { editingSlot = EditingSlot(button, press) },
              )
              if (current != null) {
                Spacer(modifier = Modifier.height(Space.s2))
                VSelect(
                    value = current.trigger.wire,
                    onValueChange = { wire ->
                      val mode = WandTriggerMode.fromWire(wire)
                      onUpdateConfig(
                          config.withBinding(
                              button,
                              press,
                              current.copy(trigger = mode),
                          ),
                      )
                    },
                    options = triggerOptions,
                    title = "Trigger Mode",
                )
              }
            }
          }
        }
      }
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.End,
    ) {
      VButton(
          label = "Reset Bindings to Defaults",
          onClick = onResetDefaults,
          variant = ButtonVariant.Danger,
      )
    }
  }

  val slot = editingSlot
  if (slot != null) {
    OptionSheet(
        title = "${slot.button.label} · ${slot.press.label}",
        options =
            presetChoices.map { choice ->
              SheetOption(
                  label = choice.label,
                  meta = choice.sub,
                  danger = choice.id == "unbind",
              )
            },
        onSelect = { index ->
          val chosen = presetChoices.getOrNull(index) ?: return@OptionSheet
          when (chosen.id) {
            "unbind" -> {
              onUpdateConfig(config.withBinding(slot.button, slot.press, null))
              editingSlot = null
            }
            "launch_app" -> {
              editingSlot = null
              pickingAppForSlot = slot
            }
            else -> {
              val act = chosen.action ?: return@OptionSheet
              val existingTrigger =
                  config.bindingFor(slot.button, slot.press)?.trigger ?: WandTriggerMode.ONCE
              onUpdateConfig(
                  config.withBinding(
                      slot.button,
                      slot.press,
                      WandBinding(action = act, trigger = existingTrigger),
                  ),
              )
              editingSlot = null
            }
          }
        },
        onDismissRequest = { editingSlot = null },
    )
  }

  val appSlot = pickingAppForSlot
  if (appSlot != null) {
    val appsList =
        if (installedApps.isEmpty()) {
          listOf(
              InstalledAppEntry(
                  packageName = "com.vitruviansoftware.wand", label = "Vitruvian Wand"))
        } else {
          installedApps
        }
    OptionSheet(
        title = "Select App to Launch",
        options =
            appsList.map { app ->
              SheetOption(
                  label = app.label,
                  meta = app.packageName,
              )
            },
        onSelect = { index ->
          val app = appsList.getOrNull(index) ?: return@OptionSheet
          onUpdateConfig(
              config.withBinding(
                  appSlot.button,
                  appSlot.press,
                  WandBinding(
                      action = WandAction.LaunchApp(app.packageName),
                      trigger = WandTriggerMode.ONCE,
                  ),
              ),
          )
          pickingAppForSlot = null
        },
        onDismissRequest = { pickingAppForSlot = null },
    )
  }
}

@Composable
private fun TestModeTab(
    isTv: Boolean,
    runtime: WandRuntimeSnapshot,
    onSetTestMode: (Boolean) -> Unit,
) {
  DisposableEffect(Unit) {
    onSetTestMode(true)
    onDispose { onSetTestMode(false) }
  }

  val sample = runtime.lastSample ?: WandSample()
  val scroll = rememberScrollState()

  Column(
      modifier = Modifier.fillMaxSize().verticalScroll(scroll).padding(Space.s4),
      verticalArrangement = Arrangement.spacedBy(Space.s4),
  ) {
    TvFocusableSurface(isTv = isTv) {
      WandPanel(
          label = "DIAGNOSTIC MODE",
          title = "Live Controller Telemetry",
          meta = if (runtime.testMode) "ACTIONS SUPPRESSED" else "IDLE",
      ) {
        VSwitch(
            checked = runtime.testMode,
            onCheckedChange = onSetTestMode,
            label = "Enable Test Mode (suppresses cursor/gestures while inspecting raw packets)",
        )
      }
    }

    WandPanel(
        label = "TOUCHPAD SURFACE",
        title =
            if (sample.touching) {
              "Touch Active (${(sample.touchX * 100).roundToInt()}%, ${(sample.touchY * 100).roundToInt()}%)"
            } else {
              "No Touch Detected"
            },
        meta = "SEQ #${sample.seq}",
    ) {
      Box(
          modifier = Modifier.fillMaxWidth().padding(Space.s3),
          contentAlignment = Alignment.Center,
      ) {
        TouchpadCircleVisualizer(sample = sample)
      }
      Spacer(modifier = Modifier.height(Space.s2))
      Plate(
          modifier = Modifier.fillMaxWidth().height(Hit.h2).padding(Space.s2),
          gridField = true,
      ) {
        LabeledMeter(
            label = "Touch X",
            value = "${(sample.touchX * 100).roundToInt()}%",
            progress = sample.touchX.coerceIn(0f, 1f),
            warn = sample.touching,
        )
      }
      Spacer(modifier = Modifier.height(Space.s2))
      Plate(
          modifier = Modifier.fillMaxWidth().height(Hit.h2).padding(Space.s2),
          gridField = true,
      ) {
        LabeledMeter(
            label = "Touch Y",
            value = "${(sample.touchY * 100).roundToInt()}%",
            progress = sample.touchY.coerceIn(0f, 1f),
            warn = sample.touching,
        )
      }
    }

    WandPanel(
        label = "PHYSICAL BUTTONS",
        title = "Button State Matrix",
        meta = "5 BUTTONS + TOUCH",
    ) {
      Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.spacedBy(Space.s2),
      ) {
        Tag(
            text = "CLICK",
            tone = if (sample.click) TagTone.Accent else TagTone.Neutral,
        )
        Tag(
            text = "APP",
            tone = if (sample.app) TagTone.Accent else TagTone.Neutral,
        )
        Tag(
            text = "HOME",
            tone = if (sample.home) TagTone.Accent else TagTone.Neutral,
        )
        Tag(
            text = "VOL +",
            tone = if (sample.volUp) TagTone.Accent else TagTone.Neutral,
        )
        Tag(
            text = "VOL -",
            tone = if (sample.volDown) TagTone.Accent else TagTone.Neutral,
        )
        Tag(
            text = "TOUCH",
            tone = if (sample.touching) TagTone.Ok else TagTone.Neutral,
        )
      }
    }

    WandPanel(
        label = "IMU SENSORS",
        title = "Orientation · Gyro · Accelerometer",
        meta = "TIME ${sample.time}",
    ) {
      SensorAxisBars(
          prefix = "Orientation",
          x = sample.orientation.x,
          y = sample.orientation.y,
          z = sample.orientation.z,
          scale = 3.15f,
      )
      Spacer(modifier = Modifier.height(Space.s3))
      MenuDivider()
      Spacer(modifier = Modifier.height(Space.s3))
      SensorAxisBars(
          prefix = "Gyro",
          x = sample.gyro.x,
          y = sample.gyro.y,
          z = sample.gyro.z,
          scale = 10f,
      )
      Spacer(modifier = Modifier.height(Space.s3))
      MenuDivider()
      Spacer(modifier = Modifier.height(Space.s3))
      SensorAxisBars(
          prefix = "Accel",
          x = sample.accel.x,
          y = sample.accel.y,
          z = sample.accel.z,
          scale = 20f,
      )
    }
  }
}

/**
 * 2D circular touchpad visualizer with crosshairs and live touch dot built strictly from
 * `Vitruvian` colour tokens and `Space` dimensions.
 */
@Composable
private fun TouchpadCircleVisualizer(sample: WandSample) {
  val surfaceColor = Vitruvian.surface2
  val borderColor = if (sample.touching) Vitruvian.accent else Vitruvian.divider
  val crosshairColor = Vitruvian.line
  val dotFillColor =
      if (sample.click) {
        Vitruvian.warn
      } else if (sample.touching) {
        Vitruvian.ok
      } else {
        Vitruvian.textDim
      }
  val dotOutlineColor = Vitruvian.text

  Canvas(
      modifier = Modifier.size(Space.s8 * 2),
  ) {
    val radius = size.minDimension / 2f
    val center = Offset(size.width / 2f, size.height / 2f)
    val strokeWidth = Space.s1.toPx()

    drawCircle(
        color = surfaceColor,
        radius = radius,
        center = center,
    )
    drawLine(
        color = crosshairColor,
        start = Offset(center.x - radius, center.y),
        end = Offset(center.x + radius, center.y),
        strokeWidth = strokeWidth / 2f,
    )
    drawLine(
        color = crosshairColor,
        start = Offset(center.x, center.y - radius),
        end = Offset(center.x, center.y + radius),
        strokeWidth = strokeWidth / 2f,
    )
    drawCircle(
        color = borderColor,
        radius = radius - strokeWidth / 2f,
        center = center,
        style = Stroke(width = strokeWidth),
    )

    val normX = if (sample.touching) sample.touchX.coerceIn(0f, 1f) else 0.5f
    val normY = if (sample.touching) sample.touchY.coerceIn(0f, 1f) else 0.5f
    val dotRadius = Space.s3.toPx()
    val usableRadius = (radius - dotRadius - strokeWidth).coerceAtLeast(1f)
    val dx = (normX - 0.5f) * 2f
    val dy = (normY - 0.5f) * 2f
    val dotPos =
        Offset(
            x = center.x + dx * usableRadius,
            y = center.y + dy * usableRadius,
        )

    drawCircle(
        color = dotFillColor,
        radius = dotRadius,
        center = dotPos,
    )
    if (sample.touching) {
      drawCircle(
          color = dotOutlineColor,
          radius = dotRadius,
          center = dotPos,
          style = Stroke(width = strokeWidth / 2f),
      )
    }
  }
}

@Composable
private fun SensorAxisBars(
    prefix: String,
    x: Float,
    y: Float,
    z: Float,
    scale: Float,
) {
  fun norm(v: Float): Float = ((v / scale) * 0.5f + 0.5f).coerceIn(0f, 1f)
  Column(verticalArrangement = Arrangement.spacedBy(Space.s2)) {
    LabeledMeter(
        label = "$prefix X",
        value = "${(x * 100f).roundToInt() / 100f}",
        progress = norm(x),
    )
    LabeledMeter(
        label = "$prefix Y",
        value = "${(y * 100f).roundToInt() / 100f}",
        progress = norm(y),
    )
    LabeledMeter(
        label = "$prefix Z",
        value = "${(z * 100f).roundToInt() / 100f}",
        progress = norm(z),
    )
  }
}
