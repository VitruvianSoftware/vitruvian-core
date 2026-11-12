# User Acceptance Testing Checklist (Hardware UAT)

This checklist is for manual verification by James using a physical Google Daydream controller across supported platforms.

---

## 1. Acceptance Criteria Checklist (Spec §5)

- [ ] **Criterion 1 (macOS Connection & Touch)**: On a Mac, pair the Daydream controller, launch Vitruvian Wand, and connect. Swiping the touchpad moves the pointer smoothly. Pressing the touchpad performs a left click. Holding the touchpad while moving executes a drag.
- [ ] **Criterion 2 (Gyro Mode & Deadzone)**: Pressing the App button switches to gyro mode. Waving the controller moves the pointer. Resting the controller or slight hand tremors do not produce cursor drift (gyro deadzone filter functions).
- [ ] **Criterion 3 (Volume & Home Defaults)**: Pressing Volume Up/Down scrolls content up and down one step per press. Pressing Home right-clicks on desktop, triggers Back on Android, and holding Home returns to the Android home screen.
- [ ] **Criterion 4 (Rebinding Persistence)**: Rebind any button across short, long, or double press. Confirm the custom binding triggers correctly and persists across application restarts.
- [ ] **Criterion 5 (Radial Menu)**: In the Bindings settings tab, bind any button (e.g., Home or App long press) to 'Radial menu'. Holding that button displays 8 slices at the cursor (centered on Wayland). Releasing over a sector executes the assigned action.
- [ ] **Criterion 6 (Test Mode)**: Open Test Mode tab. Verify live touch coordinates, button press indicators, and 3D IMU motion visualizer update in real time without moving the OS pointer.
- [ ] **Criterion 7 (Battery & Low-Battery Alert)**: Controller battery percentage displays in the UI. Simulating or reaching below 15% battery triggers a warning notification.
- [ ] **Criterion 8 (Linux uinput on X11 & Wayland)**: Connect on a Linux desktop under both X11 and Wayland sessions. Confirm `/dev/uinput` translates motions, clicks, and scrolls cleanly.
- [ ] **Criterion 9 (Android Phone Navigation)**: On an Android phone with Accessibility granted, an overlay cursor appears. Taps, drags, flings, Back, and Home navigation gestures work reliably.
- [ ] **Criterion 10 (Android TV Scan & ADB Flow)**: On Android TV, use Scan & Pair to connect the controller. Run the ADB command to grant `WRITE_SECURE_SETTINGS` and activate the service using "Try enable". In gyro mode, verify touchpad swipes move D-pad focus between on-screen tiles.

---

## 2. Platform Default Bindings Verification

### macOS & Linux Desktop
- [ ] **Touchpad Swipe (Touch Mode)**: Moves mouse cursor with linear acceleration and no jitter.
- [ ] **Touchpad Swipe (Gyro Mode)**: Scrolls document or web page vertically.
- [ ] **Touchpad Click (Short / Hold)**: Hold trigger (press emits mouse down, release emits mouse up). Short press performs a left click; holding while moving executes left drag.
- [ ] **Touchpad Tap (When Enabled)**: Emulates left click on light tap.
- [ ] **App Button (Short Press)**: Toggles pointer between Touchpad and Gyro air-mouse modes.
- [ ] **Home Button (Short Press)**: Triggers secondary right mouse click (no long-press action by default).
- [ ] **Radial Menu (Opt-in Binding)**: Bind any button or press type to "Radial menu" in settings. Holding the bound button opens the 8-slot radial menu at cursor (centered on Wayland).
- [ ] **Volume Up (Short Press)**: Scrolls content up one step per press (no hold-to-repeat).
- [ ] **Volume Down (Short Press)**: Scrolls content down one step per press (no hold-to-repeat).

### Android Phone
- [ ] **Overlay Pointer**: Cursor renders over all applications and hides when disconnected.
- [ ] **Touchpad Click**: Dispatches click gesture at current pointer coordinates (holding while moving performs drag).
- [ ] **App Button (Short Press)**: Toggles between touch mode and gyro mode.
- [ ] **Home Button (Short Press)**: Navigates back (`GLOBAL_ACTION_BACK`).
- [ ] **Home Button (Long Press)**: Returns to launcher (`GLOBAL_ACTION_HOME`).
- [ ] **Volume Buttons (Short Press)**: Scrolls content up/down one step per press.
- [ ] **Foreground Notification**: Displays Disconnect and Recalibrate quick actions.

### Android TV
- [ ] **In-App Scan & Pair**: Discovers and establishes BLE connection without opening TV settings.
- [ ] **ADB Service Activation**: `WRITE_SECURE_SETTINGS` allows in-app "Try enable" button to start service.
- [ ] **App Button (Short Press)**: Toggles between touch mode and gyro mode.
- [ ] **Touchpad Swipe in Gyro Mode**: Steps D-pad focus (`focusSearch`) between TV tiles and buttons.
- [ ] **Touchpad Click**: Activates selected tile or button (holding while moving performs drag).
- [ ] **Home Button**: Short press returns to previous screen (`GLOBAL_ACTION_BACK`); long press returns to TV home (`GLOBAL_ACTION_HOME`).
- [ ] **Volume Buttons (Short Press)**: Scrolls content up/down one step per press.
