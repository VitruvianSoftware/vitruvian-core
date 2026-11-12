// Copyright (c) 2026 VitruvianSoftware

package com.vitruviansoftware.wand.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.os.SystemClock
import android.util.Log
import java.util.UUID
import kotlin.math.min

/** Connection state of the Daydream BLE controller. */
enum class BleConnectionState {
  DISCONNECTED,
  SCANNING,
  CONNECTING,
  PAIRING,
  CONNECTED,
}

/** Discovered Daydream controller entry for the Scan & Pair screen. */
data class DiscoveredController(
    val address: String,
    val name: String,
    val rssi: Int,
    val bonded: Boolean,
)

/**
 * Activity-scoped BLE Scan & Pair helper owned by `MainActivity` so Scan & Pair works even before
 * `WandAccessibilityService` has been enabled.
 * - Filters BLE scans by device name `"Daydream controller"` and service UUID
 *   `0000fe55-0000-1000-8000-00805f9b34fb`.
 * - Its `ACTION_BOND_STATE_CHANGED` receiver reacts ONLY to the `pendingBondAddress` explicitly
 *   selected by the user.
 */
@SuppressLint("MissingPermission")
class DaydreamPairingHelper(
    private val context: Context,
    private val onDiscoveredControllers: (List<DiscoveredController>) -> Unit,
    private val onPairingStateChanged: (BleConnectionState, String?) -> Unit,
    private val onDeviceBonded: (String) -> Unit,
) {
  private val mainHandler = Handler(Looper.getMainLooper())
  private val bluetoothManager =
      context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
  private val bluetoothAdapter: BluetoothAdapter?
    get() = bluetoothManager?.adapter

  private var scanner: BluetoothLeScanner? = null
  private val discoveredMap = LinkedHashMap<String, DiscoveredController>()

  @Volatile private var pendingBondAddress: String? = null

  private val scanTimeoutRunnable = Runnable {
    stopScan()
    if (pendingBondAddress == null) {
      onPairingStateChanged(BleConnectionState.DISCONNECTED, null)
    }
  }

  private val bondReceiver =
      object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
          if (intent?.action != BluetoothDevice.ACTION_BOND_STATE_CHANGED) return
          val device: BluetoothDevice? =
              if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
              } else {
                @Suppress("DEPRECATION") intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
              }
          val addr = device?.address ?: return
          // React ONLY to the address the user explicitly chose to pair.
          if (addr != pendingBondAddress) return

          val bondState =
              intent.getIntExtra(
                  BluetoothDevice.EXTRA_BOND_STATE,
                  BluetoothDevice.BOND_NONE,
              )
          mainHandler.post {
            val existing = discoveredMap[addr]
            if (existing != null) {
              discoveredMap[addr] =
                  existing.copy(
                      bonded = bondState == BluetoothDevice.BOND_BONDED,
                  )
              onDiscoveredControllers(discoveredMap.values.toList())
            }
            when (bondState) {
              BluetoothDevice.BOND_BONDED -> {
                pendingBondAddress = null
                onPairingStateChanged(
                    BleConnectionState.DISCONNECTED,
                    "Bonded with ${device.name ?: DaydreamGatt.CONTROLLER_NAME}",
                )
                onDeviceBonded(addr)
              }
              BluetoothDevice.BOND_NONE -> {
                pendingBondAddress = null
                onPairingStateChanged(
                    BleConnectionState.DISCONNECTED,
                    "Pairing cancelled or failed",
                )
              }
            }
          }
        }
      }

  init {
    val filter = IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      context.registerReceiver(bondReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
    } else {
      context.registerReceiver(bondReceiver, filter)
    }
  }

  fun startScan() {
    stopScan()
    discoveredMap.clear()
    val adapter = bluetoothAdapter
    if (adapter == null || !adapter.isEnabled) {
      onPairingStateChanged(BleConnectionState.DISCONNECTED, "Bluetooth is off")
      return
    }

    try {
      adapter.bondedDevices?.forEach { dev ->
        if (dev.name == DaydreamGatt.CONTROLLER_NAME) {
          discoveredMap[dev.address] =
              DiscoveredController(
                  address = dev.address,
                  name = dev.name ?: DaydreamGatt.CONTROLLER_NAME,
                  rssi = 0,
                  bonded = true,
              )
        }
      }
    } catch (e: SecurityException) {
      Log.w(TAG, "Missing permission while reading bonded devices", e)
    }
    onDiscoveredControllers(discoveredMap.values.toList())

    val leScanner =
        try {
          adapter.bluetoothLeScanner
        } catch (e: SecurityException) {
          Log.w(TAG, "Missing permission while acquiring BLE scanner", e)
          null
        }
    if (leScanner == null) {
      onPairingStateChanged(BleConnectionState.DISCONNECTED, "BLE scanner unavailable")
      return
    }

    val filters =
        listOf(
            ScanFilter.Builder().setDeviceName(DaydreamGatt.CONTROLLER_NAME).build(),
            ScanFilter.Builder()
                .setServiceUuid(ParcelUuid(DaydreamGatt.DAYDREAM_SERVICE_UUID))
                .build(),
        )
    val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()

    try {
      scanner = leScanner
      leScanner.startScan(filters, settings, scanCallback)
      onPairingStateChanged(BleConnectionState.SCANNING, DaydreamGatt.CONTROLLER_NAME)
      mainHandler.removeCallbacks(scanTimeoutRunnable)
      mainHandler.postDelayed(scanTimeoutRunnable, DaydreamGatt.SCAN_TIMEOUT_MS)
    } catch (e: SecurityException) {
      Log.e(TAG, "Missing BLUETOOTH_SCAN permission", e)
      onPairingStateChanged(BleConnectionState.DISCONNECTED, "Missing Bluetooth scan permission")
    } catch (e: Exception) {
      Log.e(TAG, "Failed to start BLE scan", e)
      onPairingStateChanged(BleConnectionState.DISCONNECTED, e.message)
    }
  }

  fun stopScan() {
    mainHandler.removeCallbacks(scanTimeoutRunnable)
    val activeScanner = scanner ?: return
    scanner = null
    try {
      activeScanner.stopScan(scanCallback)
    } catch (e: Exception) {
      Log.w(TAG, "Failed to stop BLE pairing scan", e)
    }
  }

  fun pairDevice(address: String) {
    stopScan()
    val adapter = bluetoothAdapter ?: return
    val device =
        try {
          adapter.getRemoteDevice(address)
        } catch (e: Exception) {
          Log.w(TAG, "Invalid Bluetooth address: $address", e)
          onPairingStateChanged(BleConnectionState.DISCONNECTED, "Invalid address: $address")
          return
        }
    if (device.bondState == BluetoothDevice.BOND_BONDED) {
      pendingBondAddress = null
      val existing = discoveredMap[address]
      if (existing != null) {
        discoveredMap[address] = existing.copy(bonded = true)
        onDiscoveredControllers(discoveredMap.values.toList())
      }
      onDeviceBonded(address)
      return
    }

    pendingBondAddress = address
    onPairingStateChanged(
        BleConnectionState.PAIRING,
        device.name ?: DaydreamGatt.CONTROLLER_NAME,
    )
    val started =
        try {
          device.createBond()
        } catch (e: SecurityException) {
          Log.w(TAG, "Missing permission for createBond on $address", e)
          false
        }
    if (!started) {
      pendingBondAddress = null
      onDeviceBonded(address)
    }
  }

  fun destroy() {
    stopScan()
    pendingBondAddress = null
    try {
      context.unregisterReceiver(bondReceiver)
    } catch (e: Exception) {
      Log.w(TAG, "Failed to unregister pairing bondReceiver", e)
    }
  }

  private val scanCallback =
      object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
          val device = result.device ?: return
          val name = result.scanRecord?.deviceName ?: device.name ?: ""
          val hasUuid =
              result.scanRecord?.serviceUuids?.any {
                it.uuid == DaydreamGatt.DAYDREAM_SERVICE_UUID
              } == true
          if (name != DaydreamGatt.CONTROLLER_NAME && !hasUuid) return

          mainHandler.post {
            discoveredMap[device.address] =
                DiscoveredController(
                    address = device.address,
                    name = if (name.isNotBlank()) name else DaydreamGatt.CONTROLLER_NAME,
                    rssi = result.rssi,
                    bonded = device.bondState == BluetoothDevice.BOND_BONDED,
                )
            onDiscoveredControllers(discoveredMap.values.toList())
          }
        }
      }

  companion object {
    private const val TAG = "VitruvianWand"
  }
}

/**
 * BLE GATT client and scanner for the Google Daydream controller.
 * - Filters scans by device name `"Daydream controller"` and service UUID
 *   `0000fe55-0000-1000-8000-00805f9b34fb`.
 * - Connects via `connectGatt(autoConnect = autoReconnect)`, requests MTU, enables notifications on
 *   `00000001-1000-1000-8000-00805f9b34fb` (writing CCCD `0x2902`), and reads battery
 *   `0x180F`/`0x2A19` on connect and every 60 seconds.
 * - Dispatches every 20-byte notification payload along with `SystemClock.elapsedRealtimeNanos() /
 *   1000` onto the shared engine [Handler].
 * - Implements exponential-backoff auto-reconnect and `createBond` pairing whose bond receiver
 *   reacts only to the address chosen by the user.
 */
@SuppressLint("MissingPermission")
class DaydreamGatt(
    private val context: Context,
    private val engineHandler: Handler,
    private val onStateChanged: (BleConnectionState, String?) -> Unit,
    private val onBatteryLevel: (Int) -> Unit,
    private val onDiscoveredControllers: (List<DiscoveredController>) -> Unit,
    private val onPacket: (ByteArray, Long) -> Unit,
) {
  private val bluetoothManager =
      context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
  private val bluetoothAdapter: BluetoothAdapter?
    get() = bluetoothManager?.adapter

  private var scanner: BluetoothLeScanner? = null
  private var gatt: BluetoothGatt? = null

  @Volatile private var state: BleConnectionState = BleConnectionState.DISCONNECTED

  @Volatile private var lastDeviceAddress: String? = null

  @Volatile private var pendingBondAddress: String? = null

  @Volatile private var userRequestedDisconnect: Boolean = false

  @Volatile private var autoReconnectEnabled: Boolean = true

  private var reconnectAttempts: Int = 0
  private var scanningForPairOnly: Boolean = false

  private val discoveredMap = LinkedHashMap<String, DiscoveredController>()

  private val batteryPollRunnable =
      object : Runnable {
        override fun run() {
          readBatteryCharacteristic()
          engineHandler.postDelayed(this, BATTERY_POLL_INTERVAL_MS)
        }
      }

  private val reconnectRunnable = Runnable {
    if (!userRequestedDisconnect &&
        autoReconnectEnabled &&
        state == BleConnectionState.DISCONNECTED) {
      val targetAddr = lastDeviceAddress
      val adapter = bluetoothAdapter
      if (targetAddr != null && adapter != null && adapter.isEnabled) {
        try {
          val device = adapter.getRemoteDevice(targetAddr)
          connectToDevice(device)
          return@Runnable
        } catch (e: Exception) {
          Log.w(TAG, "Direct reconnect failed, falling back to scan", e)
        }
      }
      startConnectScan()
    }
  }

  private val scanTimeoutRunnable = Runnable {
    stopScanInternal()
    if (state == BleConnectionState.SCANNING) {
      if (!scanningForPairOnly && autoReconnectEnabled && !userRequestedDisconnect) {
        updateState(BleConnectionState.DISCONNECTED, "Scan timed out; retrying")
        scheduleReconnect()
      } else {
        updateState(BleConnectionState.DISCONNECTED, null)
      }
    }
  }

  private val bondReceiver =
      object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
          if (intent?.action != BluetoothDevice.ACTION_BOND_STATE_CHANGED) return
          val device: BluetoothDevice? =
              if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
              } else {
                @Suppress("DEPRECATION") intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
              }
          val addr = device?.address ?: return
          // React ONLY to the address the user explicitly selected.
          if (addr != pendingBondAddress) return

          val bondState =
              intent.getIntExtra(
                  BluetoothDevice.EXTRA_BOND_STATE,
                  BluetoothDevice.BOND_NONE,
              )
          engineHandler.post {
            val existing = discoveredMap[addr]
            if (existing != null) {
              discoveredMap[addr] =
                  existing.copy(
                      bonded = bondState == BluetoothDevice.BOND_BONDED,
                  )
              onDiscoveredControllers(discoveredMap.values.toList())
            }
            if (bondState == BluetoothDevice.BOND_BONDED) {
              pendingBondAddress = null
              connectToDevice(device)
            } else if (bondState == BluetoothDevice.BOND_NONE &&
                state == BleConnectionState.PAIRING) {
              pendingBondAddress = null
              updateState(BleConnectionState.DISCONNECTED, "Pairing cancelled or failed")
            }
          }
        }
      }

  init {
    val filter = IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      context.registerReceiver(bondReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
    } else {
      context.registerReceiver(bondReceiver, filter)
    }
  }

  fun setAutoReconnect(enabled: Boolean) {
    engineHandler.post {
      autoReconnectEnabled = enabled
      if (!enabled) {
        engineHandler.removeCallbacks(reconnectRunnable)
      }
    }
  }

  /** Connects to a bonded Daydream controller if available, or starts a filtered BLE scan. */
  fun connect() {
    engineHandler.post {
      userRequestedDisconnect = false
      reconnectAttempts = 0
      engineHandler.removeCallbacks(reconnectRunnable)

      val adapter = bluetoothAdapter
      if (adapter == null || !adapter.isEnabled) {
        updateState(BleConnectionState.DISCONNECTED, "Bluetooth is disabled")
        return@post
      }

      val bonded =
          try {
            adapter.bondedDevices?.firstOrNull { dev ->
              dev.name == CONTROLLER_NAME || dev.address == lastDeviceAddress
            }
          } catch (e: SecurityException) {
            Log.w(TAG, "Missing permission while checking bonded devices", e)
            null
          }

      if (bonded != null) {
        connectToDevice(bonded)
      } else {
        startConnectScan()
      }
    }
  }

  /**
   * Connects directly to the specified MAC `address` (e.g., after `DaydreamPairingHelper` finishes
   * bonding in `MainActivity`).
   */
  fun connectToAddress(address: String) {
    engineHandler.post {
      userRequestedDisconnect = false
      reconnectAttempts = 0
      engineHandler.removeCallbacks(reconnectRunnable)
      stopScanInternal()
      val adapter = bluetoothAdapter ?: return@post
      val device =
          try {
            adapter.getRemoteDevice(address)
          } catch (e: Exception) {
            Log.w(TAG, "Invalid device address: $address", e)
            updateState(BleConnectionState.DISCONNECTED, "Invalid device address: $address")
            return@post
          }
      connectToDevice(device)
    }
  }

  /**
   * Starts a BLE discovery scan for the Scan & Pair screen without immediately auto-connecting
   * unbonded devices until selected.
   */
  fun startPairingScan() {
    engineHandler.post {
      userRequestedDisconnect = false
      scanningForPairOnly = true
      discoveredMap.clear()

      val adapter = bluetoothAdapter
      if (adapter != null && adapter.isEnabled) {
        try {
          adapter.bondedDevices?.forEach { dev ->
            if (dev.name == CONTROLLER_NAME) {
              discoveredMap[dev.address] =
                  DiscoveredController(
                      address = dev.address,
                      name = dev.name ?: CONTROLLER_NAME,
                      rssi = 0,
                      bonded = true,
                  )
            }
          }
        } catch (e: SecurityException) {
          Log.w(TAG, "Missing permission while listing bonded controllers", e)
        }
      }
      onDiscoveredControllers(discoveredMap.values.toList())
      startBleScanner()
    }
  }

  /** Initiates bonding (`createBond`) or direct GATT connection for `address`. */
  fun pairAndConnect(address: String) {
    engineHandler.post {
      stopScanInternal()
      val adapter = bluetoothAdapter ?: return@post
      val device =
          try {
            adapter.getRemoteDevice(address)
          } catch (e: Exception) {
            Log.w(TAG, "Invalid device address for pairAndConnect: $address", e)
            updateState(BleConnectionState.DISCONNECTED, "Invalid device address: $address")
            return@post
          }
      lastDeviceAddress = address
      if (device.bondState == BluetoothDevice.BOND_BONDED) {
        pendingBondAddress = null
        connectToDevice(device)
      } else {
        pendingBondAddress = address
        updateState(BleConnectionState.PAIRING, device.name ?: CONTROLLER_NAME)
        val started =
            try {
              device.createBond()
            } catch (e: SecurityException) {
              Log.w(TAG, "Missing permission for createBond on $address", e)
              false
            }
        if (!started) {
          pendingBondAddress = null
          connectToDevice(device)
        }
      }
    }
  }

  fun disconnect() {
    engineHandler.post {
      userRequestedDisconnect = true
      pendingBondAddress = null
      engineHandler.removeCallbacks(reconnectRunnable)
      engineHandler.removeCallbacks(batteryPollRunnable)
      engineHandler.removeCallbacks(scanTimeoutRunnable)
      stopScanInternal()
      closeGattInternal()
      updateState(BleConnectionState.DISCONNECTED, null)
    }
  }

  /**
   * Stops BLE scanning and closes the active GATT client on the engine thread BEFORE
   * `NativeEngine.destroy()` runs as the final message on that thread.
   */
  fun stopBeforeDestroy() {
    try {
      context.unregisterReceiver(bondReceiver)
    } catch (e: Exception) {
      Log.w(TAG, "Failed to unregister GATT bondReceiver", e)
    }
    engineHandler.post {
      userRequestedDisconnect = true
      pendingBondAddress = null
      engineHandler.removeCallbacks(reconnectRunnable)
      engineHandler.removeCallbacks(batteryPollRunnable)
      engineHandler.removeCallbacks(scanTimeoutRunnable)
      stopScanInternal()
      closeGattInternal()
    }
  }

  private fun startConnectScan() {
    scanningForPairOnly = false
    startBleScanner()
  }

  private fun startBleScanner() {
    stopScanInternal()
    val adapter = bluetoothAdapter
    if (adapter == null || !adapter.isEnabled) {
      updateState(BleConnectionState.DISCONNECTED, "Bluetooth is off")
      return
    }
    val leScanner =
        try {
          adapter.bluetoothLeScanner
        } catch (e: SecurityException) {
          Log.w(TAG, "Missing permission while acquiring BLE scanner", e)
          null
        }
    if (leScanner == null) {
      updateState(BleConnectionState.DISCONNECTED, "BLE scanner unavailable")
      return
    }

    val filters =
        listOf(
            ScanFilter.Builder().setDeviceName(CONTROLLER_NAME).build(),
            ScanFilter.Builder().setServiceUuid(ParcelUuid(DAYDREAM_SERVICE_UUID)).build(),
        )
    val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()

    try {
      scanner = leScanner
      leScanner.startScan(filters, settings, scanCallback)
      updateState(BleConnectionState.SCANNING, CONTROLLER_NAME)
      engineHandler.removeCallbacks(scanTimeoutRunnable)
      engineHandler.postDelayed(scanTimeoutRunnable, SCAN_TIMEOUT_MS)
    } catch (e: SecurityException) {
      Log.e(TAG, "Missing BLUETOOTH_SCAN permission", e)
      updateState(BleConnectionState.DISCONNECTED, "Missing Bluetooth scan permission")
    } catch (e: Exception) {
      Log.e(TAG, "Failed to start BLE scan", e)
      updateState(BleConnectionState.DISCONNECTED, e.message)
    }
  }

  private fun stopScanInternal() {
    engineHandler.removeCallbacks(scanTimeoutRunnable)
    val activeScanner = scanner ?: return
    scanner = null
    try {
      activeScanner.stopScan(scanCallback)
    } catch (e: Exception) {
      Log.w(TAG, "Failed to stop BLE scan", e)
    }
  }

  private fun connectToDevice(device: BluetoothDevice) {
    stopScanInternal()
    closeGattInternal()
    lastDeviceAddress = device.address
    updateState(BleConnectionState.CONNECTING, device.name ?: device.address)
    try {
      gatt =
          device.connectGatt(
              context,
              autoReconnectEnabled,
              gattCallback,
              BluetoothDevice.TRANSPORT_LE,
          )
    } catch (e: SecurityException) {
      Log.e(TAG, "Missing BLUETOOTH_CONNECT permission", e)
      updateState(BleConnectionState.DISCONNECTED, "Missing Bluetooth connect permission")
    }
  }

  private fun closeGattInternal() {
    engineHandler.removeCallbacks(batteryPollRunnable)
    val active = gatt ?: return
    gatt = null
    try {
      active.disconnect()
    } catch (e: Exception) {
      Log.w(TAG, "Failed to disconnect GATT", e)
    }
    try {
      active.close()
    } catch (e: Exception) {
      Log.w(TAG, "Failed to close GATT", e)
    }
  }

  private fun scheduleReconnect() {
    if (userRequestedDisconnect || !autoReconnectEnabled) return
    engineHandler.removeCallbacks(reconnectRunnable)
    val shift = min(reconnectAttempts, 5)
    val delayMs = min(INITIAL_BACKOFF_MS * (1L shl shift), MAX_BACKOFF_MS)
    reconnectAttempts++
    engineHandler.postDelayed(reconnectRunnable, delayMs)
  }

  private fun updateState(newState: BleConnectionState, detail: String?) {
    state = newState
    onStateChanged(newState, detail)
  }

  private fun enableDaydreamNotifications(activeGatt: BluetoothGatt) {
    val service = activeGatt.getService(DAYDREAM_SERVICE_UUID)
    if (service == null) {
      Log.w(TAG, "Daydream service $DAYDREAM_SERVICE_UUID not found")
      return
    }
    val notifyChar = service.getCharacteristic(DAYDREAM_NOTIFY_CHAR_UUID)
    if (notifyChar == null) {
      Log.w(TAG, "Daydream characteristic $DAYDREAM_NOTIFY_CHAR_UUID not found")
      return
    }
    activeGatt.setCharacteristicNotification(notifyChar, true)
    val cccd = notifyChar.getDescriptor(CCCD_UUID)
    if (cccd != null) {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        activeGatt.writeDescriptor(cccd, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
      } else {
        @Suppress("DEPRECATION")
        cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
        @Suppress("DEPRECATION") activeGatt.writeDescriptor(cccd)
      }
    } else {
      startBatteryPolling()
    }
  }

  private fun startBatteryPolling() {
    engineHandler.removeCallbacks(batteryPollRunnable)
    engineHandler.post(batteryPollRunnable)
  }

  private fun readBatteryCharacteristic() {
    val activeGatt = gatt ?: return
    val batteryService = activeGatt.getService(BATTERY_SERVICE_UUID) ?: return
    val batteryChar = batteryService.getCharacteristic(BATTERY_LEVEL_CHAR_UUID) ?: return
    try {
      activeGatt.readCharacteristic(batteryChar)
    } catch (e: Exception) {
      Log.w(TAG, "Failed to read battery characteristic", e)
    }
  }

  private val scanCallback =
      object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
          val device = result.device ?: return
          val name = result.scanRecord?.deviceName ?: device.name ?: ""
          val hasUuid =
              result.scanRecord?.serviceUuids?.any { it.uuid == DAYDREAM_SERVICE_UUID } == true
          if (name != CONTROLLER_NAME && !hasUuid) return

          engineHandler.post {
            val entry =
                DiscoveredController(
                    address = device.address,
                    name = if (name.isNotBlank()) name else CONTROLLER_NAME,
                    rssi = result.rssi,
                    bonded = device.bondState == BluetoothDevice.BOND_BONDED,
                )
            discoveredMap[device.address] = entry
            onDiscoveredControllers(discoveredMap.values.toList())

            if (!scanningForPairOnly) {
              connectToDevice(device)
            }
          }
        }

        override fun onScanFailed(errorCode: Int) {
          engineHandler.post {
            updateState(BleConnectionState.DISCONNECTED, "BLE scan error ($errorCode)")
            scheduleReconnect()
          }
        }
      }

  private val gattCallback =
      object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
          engineHandler.post {
            when (newState) {
              BluetoothProfile.STATE_CONNECTED -> {
                reconnectAttempts = 0
                updateState(
                    BleConnectionState.CONNECTED,
                    gatt.device?.name ?: gatt.device?.address ?: CONTROLLER_NAME,
                )
                val mtuRequested =
                    try {
                      gatt.requestMtu(REQUESTED_MTU)
                    } catch (e: Exception) {
                      Log.w(TAG, "Failed to request MTU", e)
                      false
                    }
                if (!mtuRequested) {
                  gatt.discoverServices()
                }
              }
              BluetoothProfile.STATE_DISCONNECTED -> {
                engineHandler.removeCallbacks(batteryPollRunnable)
                closeGattInternal()
                updateState(BleConnectionState.DISCONNECTED, null)
                if (!userRequestedDisconnect && autoReconnectEnabled) {
                  scheduleReconnect()
                }
              }
            }
          }
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
          engineHandler.post { gatt.discoverServices() }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
          if (status != BluetoothGatt.GATT_SUCCESS) return
          engineHandler.post { enableDaydreamNotifications(gatt) }
        }

        override fun onDescriptorWrite(
            gatt: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int,
        ) {
          if (descriptor.uuid == CCCD_UUID) {
            engineHandler.post { startBatteryPolling() }
          }
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) {
          if (characteristic.uuid != DAYDREAM_NOTIFY_CHAR_UUID) return
          val packetCopy = value.copyOf()
          val timestampUs = SystemClock.elapsedRealtimeNanos() / 1000L
          onPacket(packetCopy, timestampUs)
        }

        @Suppress("DEPRECATION")
        @Deprecated("Deprecated in API 33")
        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
        ) {
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) return
          if (characteristic.uuid != DAYDREAM_NOTIFY_CHAR_UUID) return
          val raw = characteristic.value ?: return
          val packetCopy = raw.copyOf()
          val timestampUs = SystemClock.elapsedRealtimeNanos() / 1000L
          onPacket(packetCopy, timestampUs)
        }

        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
            status: Int,
        ) {
          if (status == BluetoothGatt.GATT_SUCCESS &&
              characteristic.uuid == BATTERY_LEVEL_CHAR_UUID) {
            val level = value.firstOrNull()?.toInt()?.and(0xFF) ?: return
            engineHandler.post { onBatteryLevel(level.coerceIn(0, 100)) }
          }
        }

        @Suppress("DEPRECATION")
        @Deprecated("Deprecated in API 33")
        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) return
          if (status == BluetoothGatt.GATT_SUCCESS &&
              characteristic.uuid == BATTERY_LEVEL_CHAR_UUID) {
            val level = characteristic.value?.firstOrNull()?.toInt()?.and(0xFF) ?: return
            engineHandler.post { onBatteryLevel(level.coerceIn(0, 100)) }
          }
        }
      }

  companion object {
    private const val TAG = "VitruvianWand"
    const val CONTROLLER_NAME = "Daydream controller"
    val DAYDREAM_SERVICE_UUID: UUID = UUID.fromString("0000fe55-0000-1000-8000-00805f9b34fb")
    val DAYDREAM_NOTIFY_CHAR_UUID: UUID = UUID.fromString("00000001-1000-1000-8000-00805f9b34fb")
    val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    val BATTERY_SERVICE_UUID: UUID = UUID.fromString("0000180f-0000-1000-8000-00805f9b34fb")
    val BATTERY_LEVEL_CHAR_UUID: UUID = UUID.fromString("00002a19-0000-1000-8000-00805f9b34fb")

    private const val REQUESTED_MTU = 64
    private const val BATTERY_POLL_INTERVAL_MS = 60_000L
    const val SCAN_TIMEOUT_MS = 15_000L
    private const val INITIAL_BACKOFF_MS = 1_000L
    private const val MAX_BACKOFF_MS = 30_000L
  }
}
