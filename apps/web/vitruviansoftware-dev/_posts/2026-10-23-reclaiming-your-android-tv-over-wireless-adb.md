---
title: "Reclaiming Your Android TV Over Wireless ADB: Zero-Root Debloating, 4K Aerials, and Notch Control"
description: >-
  Modern Google TV sets pair stunning 4K OLED panels with 3 GB of RAM choked by home-screen ad
  carousels and background telemetry daemons. Here is how we used wireless ADB to replace the
  stock launcher, wire 4K Dolby Vision aerial screensavers, disable 19 bloat packages, and drive
  our Sony Bravia OLED from the macOS notch and a Pixel Fold.
date: 2026-10-23 16:00:00 +0000
categories: [android-tv, macos, android, hardware, developer-tools]
image: /images/android-tv-before-after.svg
---

A modern high-end television is a study in contradictions. Our living-room **Sony Bravia XR-65A80J** has a phenomenal 4K 120 Hz OLED panel, acoustic surface audio, and Dolby Vision IQ. Yet out of the box, pressing the **Home** button feels like opening a budget smartphone from 2016: D-pad focus stutters across auto-playing sponsored trailers, apps cold-start because background memory is exhausted, and a third of the screen is dedicated to shows you neither watch nor subscribe to.

The bottleneck isn't the panel—it's the software stack running on the TV's MediaTek MT5895 SoC and its 3 GB of RAM. Between the stock Google TV Home launcher (`com.google.android.tvlauncher`), Automatic Content Recognition (ACR) daemons like Samba Interactive TV (`tv.samba.ssm`), and twenty-plus preinstalled promotional services, less than 500 MB of memory remains available for actual apps.

You do not need root access, a custom ROM, or a hardware dongle to fix this. Everything needed to strip an Android TV or Google TV down to a fast, quiet display is already built into the OS and reachable over **wireless ADB**.

In this guide, we walk through the exact scripts and tools we built in [vitruvian-core](https://github.com/VitruvianSoftware/vitruvian-core) to reclaim our Sony Bravia OLED—and how we went one step further by building native **macOS notch** and **Android foldable** remote surfaces so we never have to hunt for the plastic remote again.

![Stock Google TV Home versus Reclaimed Sony Bravia OLED](/images/android-tv-before-after.svg)
*Figure 1: Stock Google TV Home leaves under 500 MB of free RAM on a 3 GB Sony Bravia XR-65A80J. Disabling the stock launcher and 19 telemetry/bloat packages over wireless ADB reclaims over 800 MB of RAM, halves animation latency, and replaces the ad carousel with Projectivy Launcher, Aerial Views 4K Dolby Vision daydreams, and SmartTube.*

---

## 1. The hardware is a 4K OLED; the software is a billboard

When an Android TV feels sluggish, three culprits are almost always responsible:

1. **The stock Google TV launcher is an ad-delivery engine.** `com.google.android.tvlauncher` continuously fetches high-resolution promotional banners, video previews, and personalized recommendation rows across multiple background processes. Worse, a companion system package—`com.google.android.tungsten.setupwraith`—watches for launcher changes and quietly re-asserts the stock home experience.
2. **ACR and retail telemetry daemons run 24/7.** Packages like `tv.samba.ssm` fingerprint what is on screen for cross-device ad targeting, while Sony's retail demo loops, Bravia Sync promotions, and preloaded stub apps (`com.sony.dtv.promotions`, `com.sony.dtv.sonyselect`, Crackle, Play Games) occupy resident memory.
3. **1.0x compositor animations amplify every frame drop.** On a 3 GB device decoding 4K artwork, standard 300 ms window and transition animations make D-pad navigation feel swampy.

Because Android TV uses the same Package Manager (`pm`) and `settings` providers as Android phones, a shell session authenticated as `shell` (UID 2000) over wireless ADB can disable per-user system packages (`pm disable-user --user 0`), grant Accessibility and DreamService bindings, and tune global WindowManager animation scales—all without unlocking the bootloader or tripping Widevine L1 DRM for Netflix and Disney+.

---

## 2. Step 1: Finding a TV on the LAN (`_adb._tcp` vs. Android 11+ wireless debugging)

First, enable **ADB debugging** on the TV:

1. Open **Settings → System → About**, scroll to **Android TV OS build**, and press **Select** seven times until *You are now a developer!* appears.
2. Back out to **Settings → System → Developer options** and enable **USB debugging** (and **Network debugging** if listed separately on your firmware).

Here is the first quirk that trips up scripts written for modern Android phones: **Android 11+ phones and Android TVs do not advertise the same mDNS service.**

- An Android 11+ phone with **Wireless debugging** enabled advertises `_adb-tls-connect._tcp.local.` on a randomized ephemeral port with TLS pairing.
- Most Android TV and Google TV sets—even those running Android 11 or 12—still use the classic ADB-over-TCP daemon on port **5555**, advertising `_adb._tcp.local.` with an instance name like `adb-<serial>` and no human-readable device name in its TXT record.

To make `bazel run //tools/adb-connect` discover phones, tablets, and TVs with zero manual IP entry, our discovery tool ([`tools/adb-connect/adb_connect.py`](https://github.com/VitruvianSoftware/vitruvian-core/blob/main/tools/adb-connect/adb_connect.py)) browses both mDNS service types simultaneously and cross-references `_androidtvremote2._tcp.local.` so a bare `_adb._tcp` serial resolves to its friendly living-room label (for example, `SONY XR-65A80J`):

```python
ADB_MDNS_SERVICES = (
    "_adb-tls-connect._tcp",
    "_adb._tcp",
)


def browse_androidtv_remote_names(timeout_s: float = 0.8) -> Dict[str, str]:
    """Map .local hostnames to friendly Android TV names via _androidtvremote2._tcp."""
    proc = subprocess.Popen(
        ["dns-sd", "-B", "_androidtvremote2._tcp", "local."],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    time.sleep(timeout_s)
    proc.terminate()
    stdout, _ = proc.communicate()

    tv_instances: List[str] = []
    for line in stdout.splitlines():
        if "_androidtvremote2._tcp." in line and "Add" in line:
            parts = line.split("_androidtvremote2._tcp.")
            if len(parts) > 1 and parts[1].strip():
                inst = parts[1].strip()
                if inst not in tv_instances:
                    tv_instances.append(inst)

    host_to_name: Dict[str, str] = {}
    for inst in tv_instances:
        lproc = subprocess.Popen(
            ["dns-sd", "-L", inst, "_androidtvremote2._tcp", "local."],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        time.sleep(0.5)
        lproc.terminate()
        lout, _ = lproc.communicate()
        reach_match = re.search(r"can be reached at (.*?):(\d+)", lout)
        if reach_match:
            host = reach_match.group(1).rstrip(".") + "."
            host_to_name[host.lower()] = inst
    return host_to_name
```

One subtle bug we caught early: when our Mac and Pixel Fold are both on Tailscale, a naive "prefer Tailscale peer" heuristic would match a single discovered device to the active Tailscale phone peer—routing a LAN-only `_adb._tcp` TV connection to the phone's `100.x.y.z` address. We guard against that explicitly in `find_target_device()`:

```python
is_legacy_adb = selected_device.get("service_type") == "_adb._tcp"
# Never route a non-Tailscale _adb._tcp TV to an unrelated active phone peer
fallback_active = (
    not is_legacy_adb
    and len(resolved_devices) == 1
    and peer.get("active", False)
)
```

Running `bazel run //tools/adb-connect` discovers the Bravia TV on the LAN, connects `adb` to `192.168.86.31:5555`, and triggers the one-time **Allow USB debugging?** prompt on the TV screen. Check *Always allow from this computer*, click **OK**, and you own the shell.

---

## 3. Step 2: Replacing the launcher, screensaver, and YouTube client

With an authenticated wireless ADB session, our provisioning pipeline (`bazel run //tools/sony-tv-setup`) replaces the three surfaces you see every day: the home launcher, the idle screensaver, and the YouTube client.

![Zero-Root Wireless ADB Provisioning Pipeline](/images/android-tv-adb-provisioning-pipeline.svg)
*Figure 2: The five-stage idempotent provisioning flow. Everything runs over standard wireless ADB as user 0 (`shell`), so Widevine L1 DRM stays intact and every change can be undone with a single command.*

### Projectivy Launcher (`com.spocky.projengmenu`)

[Projectivy Launcher](https://github.com/spocky/miproject1) is the gold standard for Android TV: clean horizontal rows, direct tiles for hardware inputs (HDMI 1–4), dynamic wallpapers, parental locks, and zero ads.

Installing the APK is half the job; making the physical **Home** button on the remote open Projectivy reliably requires two steps over ADB:

1. **Enable Projectivy's Accessibility Service** so it can intercept Home button events even before the stock launcher is disabled.
2. **Disable the stock Google TV launcher and setup enforcer** for user `0` (`com.google.android.tvlauncher` and `com.google.android.tungsten.setupwraith`) so Android promotes Projectivy to the sole `HOME` intent resolver:

```bash
# 1. Sideload Projectivy Launcher
adb -s 192.168.86.31:5555 install -r projectivy-launcher.apk

# 2. Wire Projectivy's AccessibilityService
adb -s 192.168.86.31:5555 shell settings put secure enabled_accessibility_services \
  com.spocky.projengmenu/com.spocky.projengmenu.services.ProjectivyAccessibilityService
adb -s 192.168.86.31:5555 shell settings put secure accessibility_enabled 1

# 3. Disable the stock Google TV Home launcher & SetupWraith enforcer for user 0
adb -s 192.168.86.31:5555 shell pm disable-user --user 0 com.google.android.tvlauncher
adb -s 192.168.86.31:5555 shell pm disable-user --user 0 com.google.android.tungsten.setupwraith
```

Disabling both `tvlauncher` and `setupwraith` is the difference between a launcher that "mostly works" and one that feels factory-installed: pressing **Home** jumps straight to Projectivy in under 50 milliseconds, and the stock launcher never consumes a megabyte of RAM in the background.

### Aerial Views 4K Dolby Vision Screensaver (`com.fourchars.lmp`)

Google TV's default "Ambient Mode" cycles static photos and weather cards. On a 65-inch OLED, slow-moving 4K HDR10 / Dolby Vision aerial flyovers (Apple TV, Fire TV, and community nature feeds) look breathtaking and prevent static UI burn-in.

We sideload [Aerial Views](https://github.com/theothernt/AerialViews) and register its `DreamService` directly in Android's secure settings so you don't have to dig through hidden settings menus:

```bash
# Sideload Aerial Views
adb -s 192.168.86.31:5555 install -r aerial-views.apk

# Set Aerial Views as the active Android DreamService (screensaver)
adb -s 192.168.86.31:5555 shell settings put secure screensaver_components \
  com.fourchars.lmp/.ui.dream.AerialDreamService
adb -s 192.168.86.31:5555 shell settings put secure screensaver_enabled 1
adb -s 192.168.86.31:5555 shell settings put secure screensaver_activate_on_sleep 1

# Start daydream after 5 minutes (300,000 ms) of inactivity
adb -s 192.168.86.31:5555 shell settings put system screen_off_timeout 300000
```

Want to trigger the screensaver on demand—say, when music is playing or you're stepping away from the couch? Starting Android's built-in `Somnambulator` activity launches the active `DreamService` immediately:

```bash
adb -s 192.168.86.31:5555 shell am start -n com.android.systemui/.Somnambulator
```

### SmartTube (`com.liskovsoft.smarttubetv.beta`)

Finally, we sideload [SmartTube](https://github.com/yuliskov/SmartTube) and disable the stock YouTube TV package (`com.google.android.youtube.tv`). SmartTube brings integrated **SponsorBlock** (automatically skipping sponsor segments, intros, and interaction reminders), **Return YouTube Dislike**, granular 4K 60fps VP9/AV1 codec selection, and frame-rate matching.

---

## 4. Step 3: Debloating 19 packages and cutting animation latency in half

With the core apps in place, `//tools/sony-tv-setup` disables 19 preinstalled telemetry, ACR, and promotional packages for `--user 0`. Using `pm disable-user --user 0` rather than `pm uninstall -k --user 0` makes it trivial to inspect disabled packages (`pm list packages -d`) and re-enable any package (`pm enable <pkg>`) without a factory reset:

```bash
BLOAT_PACKAGES=(
  # Stock Launcher & Setup Enforcer
  "com.google.android.tvlauncher"
  "com.google.android.tungsten.setupwraith"

  # ACR Content Tracking & Telemetry
  "tv.samba.ssm"
  "com.sony.dtv.NextGenDiagnostic"
  "com.sony.dtv.ircamera"

  # Sony Promotional Shelves & Retail Demos
  "com.sony.dtv.promotions"
  "com.sony.dtv.sonyselect"
  "com.sony.dtv.braviasyncmenu"
  "com.sony.dtv.demomode"
  "com.sony.dtv.retailmode"
  "com.sony.dtv.b2b.hotelmode"
  "com.sony.dtv.timers"
  "com.sony.dtv.imanual"
  "com.sony.dtv.smarthelp"

  # Redundant / Preloaded Media & Games Bloat
  "com.google.android.youtube.tv"
  "com.google.android.youtube.tvmusic"
  "com.google.android.play.games"
  "com.gotv.crackle.handset"
  "com.google.android.videos"
)

for pkg in "${BLOAT_PACKAGES[@]}"; do
  adb -s 192.168.86.31:5555 shell pm disable-user --user 0 "$pkg" || true
done
```

> **What NOT to disable on a Sony Bravia:** Leave `com.sony.dtv.tvx` and `com.sony.dtv.tvinput.external` enabled. Those packages handle hardware HDMI 1–4 passthrough, eARC audio routing, and Sony's picture-mode overlays.

Next, we cut all three global WindowManager animation scales from `1.0` to `0.5`, set a 2-hour deep-sleep timer (`7,200,000` ms) so the OLED panel powers down if left idle overnight, and flush accumulated package caches:

```bash
# Halve UI animation durations for instant D-pad focus movement
adb -s 192.168.86.31:5555 shell settings put global window_animation_scale 0.5
adb -s 192.168.86.31:5555 shell settings put global transition_animation_scale 0.5
adb -s 192.168.86.31:5555 shell settings put global animator_duration_scale 0.5

# Auto-sleep after 2 hours of inactivity
adb -s 192.168.86.31:5555 shell settings put secure sleep_timeout 7200000

# Trim package caches to reclaim storage and page cache
adb -s 192.168.86.31:5555 shell pm trim-caches 999999999999999999
```

Checking `/proc/meminfo` before and after tells the story:

```text
# Before (Stock Google TV Home idle)
MemTotal:        2984120 kB
MemAvailable:     471040 kB   (~460 MB free)

# After (Projectivy + 19 packages disabled + cache trim)
MemTotal:        2984120 kB
MemAvailable:    1341824 kB   (~1,310 MB free)
```

That extra **850 MB of headroom** completely eliminates launcher reloads when switching between SmartTube, Netflix, and HDMI inputs.

---

## 5. Step 4: Controlling the TV from the macOS Notch and a Foldable Phone

Once your TV is reachable over wireless ADB in a few milliseconds, an interesting realization sets in: **you no longer need proprietary smart-home hubs or cloud APIs to automate your living room.** A single ADB shell command can read power and memory telemetry, switch hardware HDMI inputs, or deep-link a video URL directly into SmartTube.

So we built first-party Sony TV control right into our desktop and mobile apps.

![Vitruvian TV Control Plane across macOS Notch and Android Foldable](/images/vitruvian-tv-control-plane.svg)
*Figure 3: Two native control surfaces—Vitruvian on macOS (`dev.vitruvian.tv` in the notch island, Command Bar, and Radial menu) and Vitruvian Remote on a Pixel Fold over Tailscale—drive the Sony Bravia XR-65A80J over wireless ADB using a shared `~/.config/vitruvian/tv.json` configuration.*

### 1. From the Mac: Vitruvian Notch Island & `dev.vitruvian.tv`

On macOS, **Vitruvian** turns the MacBook Pro notch into an extensible ambient island alongside a keyboard-first Command Bar and Radial gesture menu. Using [`VitruvianToolKit`](https://github.com/VitruvianSoftware/vitruvian-core/tree/main/packages/vitruvian-sdk)—our open Swift SDK that runs each extension as a sandboxed child process speaking JSON-RPC 2.0 over `stdio`—we built the **[Vitruvian TV (`dev.vitruvian.tv`)](/tools/catalog/#dev.vitruvian.tv)** extension.

Drop your cursor into the macOS notch (or press the Command Bar hotkey) and `dev.vitruvian.tv` shows the TV's live state (`Awake`, `AerialViews 4K`, `SmartTube 4K`, `Projectivy Home`, or `Standby`) and free memory badge, backed by one-click actions:

- **Cast Clipboard URL to SmartTube:** Copy any YouTube link on your Mac and trigger *Play clipboard URL on the TV*. Instead of fighting Cast discovery dialogs or signing into Google Cast, the extension wakes the TV and sends an explicit `android.intent.action.VIEW` intent straight to SmartTube:
  ```bash
  adb -s 192.168.86.31:5555 shell \
    "input keyevent KEYCODE_WAKEUP && am start -a android.intent.action.VIEW -d 'https://youtu.be/dQw4w9WgXcQ' com.liskovsoft.smarttubetv.beta"
  ```
- **Direct Hardware HDMI 1–4 Switching:** Rather than simulating fragile D-pad presses through an input menu, we launch Sony's external hardware input passthrough URI directly:
  ```bash
  adb -s 192.168.86.31:5555 shell \
    "input keyevent KEYCODE_WAKEUP && am start -a android.intent.action.VIEW -d content://android.media.tv/passthrough/com.sony.dtv.tvinput.external/.ExternalTvInputService%2FHW1"
  ```
- **Start 4K Aerial Screensaver / Toggle Power:** One click in the notch island puts the living room into 4K Dolby Vision aerial flyovers (`Somnambulator`) or puts the panel to sleep (`KEYCODE_SLEEP`).

You can install **[Vitruvian TV (`dev.vitruvian.tv`)](/tools/catalog/#dev.vitruvian.tv)** and browse all of our signed macOS extensions in the **[Vitruvian Tool Catalog](/tools/catalog/)**.

### 2. From the Couch: Vitruvian Remote for Android Foldables

When you aren't at your laptop, **[Vitruvian Remote](https://github.com/VitruvianSoftware/vitruvian-core/tree/main/apps/mobile/android-remote)** (`apps/mobile/android-remote`) is our Jetpack Compose remote and observability console built specifically for Android foldables like the Pixel Fold.

Folded closed, it acts as a tactile pocket remote and trackpad. Unfolded—or set half-open on the coffee table in tabletop posture—it displays live Mac CPU/thermal sparklines, Lima VMs, K3s cluster health, HomeSpeaker TTS broadcast controls, and a dedicated **Sony TV dashboard** (`tvDashboard`).

Because the phone talks to `vitruvian-remote-agent` on the Mac over Tailscale, the phone doesn't even need its own ADB key paired to the TV. The Go agent ([`apps/mobile/android-remote/macagent/tv.go`](https://github.com/VitruvianSoftware/vitruvian-core/blob/main/apps/mobile/android-remote/macagent/tv.go)) exposes `GET /v1/tv` and `POST /v1/tv`, coalescing power state, foreground window focus, and `/proc/meminfo` into a single 5-second-bounded ADB shell round-trip:

```go
const statusQuery = "dumpsys power | grep -E 'mWakefulness=' ; " +
	"dumpsys window displays | grep -E 'mCurrentFocus|mFocusedApp' ; " +
	"grep -E 'MemTotal|MemAvailable' /proc/meminfo"
out, stderr, err := t.run(ctx, tvCmdTimeout, adb, "-s", addr, "shell", statusQuery)

awake := strings.Contains(out, "mWakefulness=Awake")
dreaming := strings.Contains(out, "mWakefulness=Dreaming") ||
	strings.Contains(out, "com.fourchars.lmp") ||
	strings.Contains(out, "Somnambulator")

foreground := "Standby"
switch {
case !awake && !dreaming:
	foreground = "Standby"
case dreaming || strings.Contains(out, "com.fourchars.lmp"):
	foreground = "AerialViews 4K"
case strings.Contains(out, "com.liskovsoft.smarttubetv"):
	foreground = "SmartTube 4K"
case strings.Contains(out, "com.spocky.projengmenu"):
	foreground = "Projectivy Home"
case strings.Contains(out, "com.disney.disneyplus"):
	foreground = "Disney+"
case strings.Contains(out, "com.netflix.ninja"):
	foreground = "Netflix"
default:
	foreground = "Awake"
}
```

Both the macOS notch extension and the Go agent read and write the same `~/.config/vitruvian/tv.json` file (falling back to the desktop tool's `storage.json`), so updating the TV's IP address in either place updates both surfaces immediately.

---

## Try it on your own TV

Every script, daemon, and UI surface described in this post is open source in **[vitruvian-core](https://github.com/VitruvianSoftware/vitruvian-core)**:

- **Wireless ADB auto-discovery (`_adb._tcp` + `_adb-tls-connect._tcp`):** [`tools/adb-connect`](https://github.com/VitruvianSoftware/vitruvian-core/tree/main/tools/adb-connect) (`bazel run //tools/adb-connect`)
- **Vitruvian TV macOS extension (`dev.vitruvian.tv`):** **[Tool Catalog (`/tools/catalog/#dev.vitruvian.tv`)](/tools/catalog/#dev.vitruvian.tv)**, **[SDK Overview (`/tools/`)](/tools/)**, and [`apps/desktop/vitruvian-tool-tv`](https://github.com/VitruvianSoftware/vitruvian-core/tree/main/apps/desktop/vitruvian-tool-tv)
- **Vitruvian Remote for Android & Mac Agent (`/v1/tv`):** **[Tool Catalog (`/tools/catalog/#dev.vitruvian.remote`)](/tools/catalog/#dev.vitruvian.remote)** and [`apps/mobile/android-remote`](https://github.com/VitruvianSoftware/vitruvian-core/tree/main/apps/mobile/android-remote) — explore all of our open-source apps and developer tools on **[/projects/](/projects/)**.
