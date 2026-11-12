# Android TV Setup Guide

This guide explains how to install Vitruvian Wand on Android TV devices, pair the Daydream controller using the in-app scanner, and enable the accessibility service via ADB if your TV settings menu hides it.

---

## 1. Install the APK

Vitruvian Wand distributes a single universal APK for both phones and TV devices. Building requires `ANDROID_HOME` set to the Android SDK installation path (for example, `/opt/homebrew/share/android-commandlinetools`). Install it over ADB:

```bash
# Set Android SDK path
export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"

# Build the universal Android APK
bazel build //apps/suites/vitruvian-wand/android:vitruvian_wand_apk

# Connect to your Android TV over wireless ADB (replace with your TV IP address)
adb connect 192.168.1.100:5555

# Sideload the APK
adb install bazel-bin/apps/suites/vitruvian-wand/android/vitruvian_wand_apk.apk
```

---

## 2. In-App Scan & Pair

Android TV system menus make pairing BLE accessories difficult. Vitruvian Wand includes a dedicated **Scan & Pair** interface designed for navigation with your standard TV remote:

1. Put your Daydream controller in pairing mode by pressing and holding the **Home button** until the LED blinks.
2. Launch **Vitruvian Wand** from the Android TV leanback launcher.
3. Select the **Scan & Pair** card on screen.
4. Highlight **Daydream controller** in the scan list and press your remote's select button to pair.

---

## 3. Enable Accessibility via ADB (The Workaround Route)

Many Android TV distributions (including Google TV dongles and smart TVs) hide the system Accessibility settings menu. Vitruvian Wand provides a direct ADB route to enable the background service:

1. Enable Developer Options and USB/Network Debugging on your Android TV:
   - Go to **Settings > Device Preferences > About**.
   - Click **Build** repeatedly (7 times) until developer mode is unlocked.
   - Go to **Settings > Device Preferences > Developer options** and turn on **Network debugging** (or USB debugging).
2. Connect from your computer via ADB and run the following command to grant secure settings permission:
   ```bash
   adb shell pm grant com.vitruviansoftware.wand android.permission.WRITE_SECURE_SETTINGS
   ```
   *(Note: `com.vitruviansoftware.wand` is the application package ID).*
3. Return to the Vitruvian Wand app on your TV and select the **Try enable** button.
4. Vitruvian Wand writes the service registration directly into Android's secure settings and starts the overlay cursor.

---

## 4. TV Navigation Modes

- **Touch Mode**: Swiping the Daydream touchpad moves the on-screen cursor across your TV apps. Pressing the touchpad clicks the selected item.
- **Gyro Mode with D-Pad Steps**: In gyro mode, swiping the touchpad sends D-pad focus directional events (`AccessibilityNodeInfo.focusSearch`). This allows you to step smoothly between UI cards, streaming tiles, and video controls.
