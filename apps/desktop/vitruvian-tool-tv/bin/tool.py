#!/usr/bin/env python3
# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

"""Vitruvian TV extension (dev.vitruvian.tv).

Controls the Living Room Sony BRAVIA 4K Google TV over ADB from the Vitruvian
Dynamic Island, Command Bar, Radial Menu, and Shortcuts.
"""

import os
import shlex
import shutil
import subprocess
import sys
from urllib.parse import urlsplit

sys.dont_write_bytecode = True

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))

from vitruvian_tool_kit import (  # noqa: E402
    Feature,
    PanelAnswer,
    Refusal,
    Tool,
    UIChoiceOption,
    button,
    choice,
    divider,
    field,
    heading,
    row,
    text,
    toggle,
    tree,
)

tool = Tool(version="0.1.0")

APPS = {
    "smarttube": ("SmartTube (Ad-Free 4K)", "org.smarttube.stable", None),
    "projectivy": (
        "Projectivy Home",
        "com.spocky.projengmenu",
        "com.spocky.projengmenu/.ui.home.MainActivity",
    ),
    "aerial": (
        "AerialViews Screensaver",
        "com.neilturner.aerialviews",
        "com.android.systemui/.Somnambulator",
    ),
    "disney": ("Disney+", "com.disney.disneyplus", None),
    "netflix": ("Netflix", "com.netflix.ninja", None),
}

INPUTS = {
    "home": (
        "Google TV Home (Projectivy)",
        "com.spocky.projengmenu/.ui.home.MainActivity",
    ),
    "hdmi1": (
        "HDMI 1",
        "com.spocky.projengmenu/.ui.guidedActions.activities.input.SourceHDMI1Activity",
    ),
    "hdmi2": (
        "HDMI 2",
        "com.spocky.projengmenu/.ui.guidedActions.activities.input.SourceHDMI2Activity",
    ),
    "hdmi3": (
        "HDMI 3 (eARC)",
        "com.spocky.projengmenu/.ui.guidedActions.activities.input.SourceHDMI3Activity",
    ),
    "hdmi4": (
        "HDMI 4",
        "com.spocky.projengmenu/.ui.guidedActions.activities.input.SourceHDMI4Activity",
    ),
}

STATUS_PROBE = (
    "dumpsys power | grep 'mWakefulness='; "
    "dumpsys window | grep 'mCurrentFocus='; "
    "grep MemAvailable /proc/meminfo"
)


def find_adb() -> str:
    for candidate in (
        "/opt/homebrew/bin/adb",
        "/usr/local/bin/adb",
        os.path.expanduser("~/Library/Android/sdk/platform-tools/adb"),
    ):
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return shutil.which("adb") or "/opt/homebrew/bin/adb"


def is_safe_http_url(raw: str) -> bool:
    if not raw or any(ch.isspace() or ord(ch) < 32 for ch in raw):
        return False
    try:
        parsed = urlsplit(raw)
    except ValueError:
        return False
    return parsed.scheme in ("http", "https") and bool(parsed.netloc)


class SonyTVState:
    def __init__(self):
        self.tv_address = "192.168.86.31:5555"
        self.show_island_status = True
        self.selected_app = "smarttube"
        self.selected_input = "home"
        self.awake = False
        self.foreground = "Checking TV…"
        self.mem_available_mb = 0
        self.connected = False
        self.dry_run = False

    def load_preferences(self, app):
        data_folder = getattr(app, "data_folder", "") or ""
        self.dry_run = (
            "Application Support" not in data_folder
            and os.environ.get("VITRUVIAN_TV_LIVE") != "1"
        )
        try:
            addr = app.storage.get(key="tvAddress").value
            if isinstance(addr, str) and addr.strip():
                self.tv_address = addr.strip()
        except Refusal:
            pass
        try:
            show = app.storage.get(key="showIslandStatus").value
            if isinstance(show, bool):
                self.show_island_status = show
        except Refusal:
            pass

    def run_adb_shell(self, shell_cmd: str, timeout: float = 0.85) -> str:
        """Runs a single ADB shell call well inside the 2s request limit.
        Only runs `adb connect` on fallback if the device is not already connected."""
        if self.dry_run:
            self.connected = True
            return ""
        adb = find_adb()
        try:
            res = subprocess.run(
                [adb, "-s", self.tv_address, "shell", shell_cmd],
                capture_output=True,
                text=True,
                timeout=timeout,
                check=False,
            )
            if res.returncode == 0:
                self.connected = True
                return res.stdout.strip()
            subprocess.run(
                [adb, "connect", self.tv_address],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=0.45,
                check=False,
            )
            res = subprocess.run(
                [adb, "-s", self.tv_address, "shell", shell_cmd],
                capture_output=True,
                text=True,
                timeout=0.65,
                check=False,
            )
            if res.returncode == 0:
                self.connected = True
                return res.stdout.strip()
        except Exception:
            pass
        self.connected = False
        return ""

    def parse_status_output(self, out: str):
        if not out:
            return
        self.awake = "Awake" in out or "Dreaming" in out
        if "com.neilturner.aerialviews" in out or "DreamActivity" in out:
            self.foreground = "AerialViews 4K"
        elif "org.smarttube.stable" in out:
            self.foreground = "SmartTube 4K"
        elif "com.spocky.projengmenu" in out:
            self.foreground = "Projectivy Home"
        elif "com.disney.disneyplus" in out:
            self.foreground = "Disney+"
        elif "com.netflix.ninja" in out:
            self.foreground = "Netflix"
        elif not self.awake:
            self.foreground = "Standby (Remote Start Ready)"
        else:
            self.foreground = "Active"

        for line in out.splitlines():
            if "MemAvailable:" in line:
                parts = line.split()
                if len(parts) >= 2 and parts[1].isdigit():
                    self.mem_available_mb = int(parts[1]) // 1024

    def refresh(self):
        if self.dry_run:
            self.connected = True
            self.awake = True
            self.foreground = "Projectivy Home"
            self.mem_available_mb = 640
            return
        out = self.run_adb_shell(STATUS_PROBE, timeout=0.85)
        self.parse_status_output(out)

    def toggle_power_atomic(self) -> bool:
        """Toggles TV wakefulness in a single atomic shell call so it never
        guesses from stale local state or exceeds the 2s timeout."""
        if self.dry_run:
            self.connected = True
            self.awake = not self.awake
            self.foreground = (
                "Projectivy Home" if self.awake else "Standby (Remote Start Ready)"
            )
            return self.awake
        out = self.run_adb_shell(
            "if dumpsys power | grep -qE 'mWakefulness=(Awake|Dreaming)'; then "
            "input keyevent KEYCODE_SLEEP; echo POWER_STATE=SLEEP; "
            "else input keyevent KEYCODE_WAKEUP; echo POWER_STATE=AWAKE; fi; "
            "grep MemAvailable /proc/meminfo",
            timeout=0.95,
        )
        if "POWER_STATE=SLEEP" in out:
            self.awake = False
            self.foreground = "Standby (Remote Start Ready)"
        elif "POWER_STATE=AWAKE" in out:
            self.awake = True
            self.foreground = "Projectivy Home"
        for line in out.splitlines():
            if "MemAvailable:" in line:
                parts = line.split()
                if len(parts) >= 2 and parts[1].isdigit():
                    self.mem_available_mb = int(parts[1]) // 1024
        return self.awake

    def sync_status(self, app):
        try:
            if not self.show_island_status or not self.connected or not self.awake:
                return app.status("none")
            short = "TV"
            if "SmartTube" in self.foreground:
                short = "YT"
            elif "Aerial" in self.foreground:
                short = "4K"
            return app.status(
                "ok",
                text=f"Sony TV: {self.foreground}",
                activity=short if app.supports(Feature.STATUS_ACTIVITY) else None,
            )
        except Refusal as refusal:
            app.log(message=f"status refused: {refusal}")
            return False

    def launch_app(self, app_key: str):
        if app_key not in APPS:
            return
        self.selected_app = app_key
        label, pkg, component = APPS[app_key]
        if component:
            cmd = f"input keyevent KEYCODE_WAKEUP; am start -n {shlex.quote(component)}"
        else:
            cmd = (
                f"input keyevent KEYCODE_WAKEUP; "
                f"monkey -p {shlex.quote(pkg)} -c android.intent.category.leanback.LAUNCHER 1 >/dev/null 2>&1"
            )
        self.run_adb_shell(cmd, timeout=0.95)
        self.awake = True
        self.foreground = label

    def switch_input(self, input_key: str):
        if input_key not in INPUTS:
            return
        self.selected_input = input_key
        label, component = INPUTS[input_key]
        self.run_adb_shell(
            f"input keyevent KEYCODE_WAKEUP; am start -n {shlex.quote(component)}",
            timeout=0.95,
        )
        self.awake = True
        self.foreground = label

    def page(self, app):
        status_line = (
            f"{self.foreground} • {self.mem_available_mb} MB available"
            if self.connected
            else f"Disconnected ({self.tv_address})"
        )
        app_options = [UIChoiceOption(value=k, title=v[0]) for k, v in APPS.items()]
        input_options = [UIChoiceOption(value=k, title=v[0]) for k, v in INPUTS.items()]

        app_picker = (
            choice("launchApp", self.selected_app, app_options, title="Launch TV App")
            if app.supports(Feature.CHOICE)
            else field(
                "launchApp",
                title="App (smarttube, projectivy, aerial, disney, netflix)",
                value=self.selected_app,
            )
        )
        input_picker = (
            choice(
                "switchInput",
                self.selected_input,
                input_options,
                title="TV Input / Source",
            )
            if app.supports(Feature.CHOICE)
            else field(
                "switchInput",
                title="Input (home, hdmi1, hdmi2, hdmi3, hdmi4)",
                value=self.selected_input,
            )
        )

        return tree(
            heading("Living Room Sony TV"),
            row(
                "BRAVIA 4K VH22",
                subtitle=status_line,
                icon="tv.fill" if self.awake else "tv",
                trailing="Awake" if self.awake else "Standby",
            ),
            button(
                "togglePower",
                "Put TV to Sleep" if self.awake else "Wake TV Now",
                style="prominent",
            ),
            button("startScreensaver", "Start 4K Aerial Screensaver"),
            button("playClipboard", "Cast Clipboard URL to SmartTube"),
            divider(),
            app_picker,
            input_picker,
            divider(),
            button("volUp", "Volume Up"),
            button("volDown", "Volume Down"),
            button("muteTV", "Mute / Unmute"),
            button("refresh", "Refresh TV Status"),
        )

    def settings(self, app):
        help_text = (
            "Shows a green mark on the closed island while the Sony TV is awake."
        )
        if not app.supports(Feature.SECTIONS):
            return tree(
                field(
                    "tvAddress",
                    title="Sony TV ADB Address",
                    value=self.tv_address,
                    placeholder="192.168.86.31:5555",
                ),
                toggle(
                    "showIslandStatus",
                    "Show TV status on closed island",
                    self.show_island_status,
                ),
                text(help_text, style="caption"),
                button("trimCaches", "Trim TV Caches in Background"),
            )
        return tree(
            heading("Connection", section=True),
            field(
                "tvAddress",
                title="Sony TV ADB Address",
                value=self.tv_address,
                placeholder="192.168.86.31:5555",
                help="IP:port of your Sony BRAVIA TV with Network ADB enabled.",
            ),
            heading("Dynamic Island", section=True),
            toggle(
                "showIslandStatus",
                "Show TV status on closed island",
                self.show_island_status,
                help=help_text,
            ),
            heading("Maintenance", section=True),
            button("trimCaches", "Trim TV Caches in Background"),
        )


tv = SonyTVState()


def notify_safe(app, icon: str, message: str):
    try:
        app.notify.hud(icon=icon, message=message)
    except Refusal:
        pass


def cast_clipboard_url(app):
    try:
        clip = (app.clipboard.read_text().text or "").strip()
    except Refusal:
        clip = ""
    if is_safe_http_url(clip):
        quoted_url = shlex.quote(clip)
        tv.run_adb_shell(
            f"input keyevent KEYCODE_WAKEUP; "
            f"am start -a android.intent.action.VIEW -d {quoted_url} org.smarttube.stable",
            timeout=0.95,
        )
        tv.awake = True
        tv.foreground = "SmartTube 4K"
        notify_safe(app, "play.tv", "Playing clipboard URL on Sony TV")
    else:
        notify_safe(
            app,
            "exclamationmark.triangle",
            "Clipboard does not contain a valid HTTP(S) URL",
        )


def open_island(app, panel):
    tv.refresh()
    tv.sync_status(app)
    return tv.page(app)


def island_event(app, panel, event):
    if event.block == "togglePower":
        tv.toggle_power_atomic()
        tv.sync_status(app)
    elif event.block == "startScreensaver":
        tv.run_adb_shell(
            "input keyevent KEYCODE_WAKEUP; am start -n com.android.systemui/.Somnambulator",
            timeout=0.95,
        )
        tv.awake = True
        tv.foreground = "AerialViews 4K"
        tv.sync_status(app)
    elif event.block == "playClipboard":
        cast_clipboard_url(app)
        tv.sync_status(app)
    elif event.block == "launchApp":
        if event.text not in APPS:
            return PanelAnswer.keep()
        tv.launch_app(event.text)
        tv.sync_status(app)
    elif event.block == "switchInput":
        if event.text not in INPUTS:
            return PanelAnswer.keep()
        tv.switch_input(event.text)
        tv.sync_status(app)
    elif event.block == "volUp":
        tv.run_adb_shell("input keyevent KEYCODE_VOLUME_UP", timeout=0.6)
    elif event.block == "volDown":
        tv.run_adb_shell("input keyevent KEYCODE_VOLUME_DOWN", timeout=0.6)
    elif event.block == "muteTV":
        tv.run_adb_shell("input keyevent KEYCODE_VOLUME_MUTE", timeout=0.6)
    elif event.block == "refresh":
        tv.refresh()
        tv.sync_status(app)
    else:
        return PanelAnswer.keep()
    return PanelAnswer.page(tv.page(app))


island_panel = tool.panel(
    "tv",
    on_open=open_island,
    on_event=island_event,
)


def settings_event(app, panel, event):
    if event.block == "tvAddress" and event.text is not None:
        addr = event.text.strip()
        if addr:
            tv.tv_address = addr
            try:
                app.storage.set(key="tvAddress", value=addr)
            except Refusal:
                pass
    elif event.block == "showIslandStatus" and event.is_on is not None:
        tv.show_island_status = event.is_on
        try:
            app.storage.set(key="showIslandStatus", value=event.is_on)
        except Refusal:
            pass
        tv.sync_status(app)
    elif event.block == "trimCaches":
        tv.run_adb_shell(
            "nohup sh -c 'pm trim-caches 999999999G' >/dev/null 2>&1 &",
            timeout=0.75,
        )
        notify_safe(app, "sparkles", "Started background cache trim on Sony TV")
    else:
        return PanelAnswer.keep()
    return PanelAnswer.page(tv.settings(app))


tool.panel(
    "settings",
    on_open=lambda app, panel: tv.settings(app),
    on_event=settings_event,
)


@tool.command("togglePower")
def cmd_toggle_power(app):
    awake_now = tv.toggle_power_atomic()
    if awake_now:
        notify_safe(app, "tv.fill", "Sony TV woken up")
    else:
        notify_safe(app, "moon.fill", "Sony TV put to sleep")
    tv.sync_status(app)
    island_panel.render(tv.page(app))


@tool.command("startScreensaver")
def cmd_start_screensaver(app):
    tv.run_adb_shell(
        "input keyevent KEYCODE_WAKEUP; am start -n com.android.systemui/.Somnambulator",
        timeout=0.95,
    )
    tv.awake = True
    tv.foreground = "AerialViews 4K"
    notify_safe(app, "sparkles.tv", "Started 4K Aerial screensaver")
    tv.sync_status(app)
    island_panel.render(tv.page(app))


@tool.command("openSmartTube")
def cmd_open_smarttube(app):
    tv.launch_app("smarttube")
    notify_safe(app, "play.tv", "Opened SmartTube on Sony TV")
    tv.sync_status(app)
    island_panel.render(tv.page(app))


@tool.command("playClipboard")
def cmd_play_clipboard(app):
    cast_clipboard_url(app)
    tv.sync_status(app)
    island_panel.render(tv.page(app))


@tool.command("goHome")
def cmd_go_home(app):
    tv.launch_app("projectivy")
    notify_safe(app, "house", "Returned to Projectivy Home")
    tv.sync_status(app)
    island_panel.render(tv.page(app))


@tool.command("muteTV")
def cmd_mute_tv(app):
    tv.run_adb_shell("input keyevent KEYCODE_VOLUME_MUTE", timeout=0.6)
    notify_safe(app, "speaker.slash", "Toggled Sony TV mute")


def on_start(app):
    tv.load_preferences(app)
    tv.refresh()
    tv.sync_status(app)


def on_preferences_changed(app, values):
    if "tvAddress" in values and isinstance(values["tvAddress"], str):
        tv.tv_address = values["tvAddress"].strip() or tv.tv_address
    if "showIslandStatus" in values and isinstance(values["showIslandStatus"], bool):
        tv.show_island_status = values["showIslandStatus"]
        tv.sync_status(app)


tool.on_start = on_start
tool.on_preferences_changed = on_preferences_changed


if __name__ == "__main__":
    tool.run()
