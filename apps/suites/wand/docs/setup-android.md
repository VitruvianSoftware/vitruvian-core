# Android Setup Guide

This guide explains how to install Wand on an Android phone, grant restricted accessibility permissions, and configure background permissions.

---

## 1. Install the APK

Build and install the Wand universal APK using Bazel and ADB. Building requires `ANDROID_HOME` set to the Android SDK installation path (for example, `/opt/homebrew/share/android-commandlinetools`):

```bash
# Set Android SDK path
export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"

# Build the universal Android APK
bazel build //apps/suites/wand/android:wand_apk

# Install the APK onto a connected Android device
adb install bazel-bin/apps/suites/wand/android/wand_apk.apk
```

---

## 2. Enable Restricted Settings (Android 13+)

On Android 13 and newer, sideloaded applications cannot enable accessibility services by default. If Android shows a "Restricted setting" prompt:

1. Open **Settings > Apps > All apps > Wand**.
2. Tap the **three-dot menu** in the top-right corner.
3. Select **Allow restricted settings**.
4. Authenticate using your device PIN, pattern, or biometric prompt.

---

## 3. Grant Accessibility Service

Wand uses an Accessibility Service to draw the system cursor overlay and dispatch screen touches, swipes, and navigation actions:

1. Open **Settings > Accessibility**.
2. Tap **Wand** under Downloaded Apps.
3. Toggle **Use Wand** to On.
4. Review the accessibility dialogue and tap **Allow**.

Once granted, the overlay pointer appears when the Daydream controller connects.

---

## 4. Grant Runtime Permissions

When you open Wand for the first time, grant the requested runtime permissions:

- **Nearby Devices (`BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT`)**: Required on Android 12+ to discover, pair, and receive sensor data from the Daydream controller.
- **Notifications (`POST_NOTIFICATIONS`)**: Required on Android 13+ to maintain a persistent foreground service with quick Disconnect and Recalibrate controls.

---

## 5. Pair and Connect

1. Hold the **Home button** on the Daydream controller until the LED pulses.
2. Open **Settings > Connected devices > Pair new device** (or use the in-app connection tab).
3. Select **Daydream controller** to complete pairing.
