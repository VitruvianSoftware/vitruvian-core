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

"""
app_profiles.py
Defines dynamic 6-button shortcut profiles for macOS applications and frontmost app detection.
"""

import os
import re
import subprocess
import time
from typing import Dict, Any, List, Optional, Tuple

# Modifier Bitmask Constants (canonical contract matching USB HID Keyboard)
MOD_NONE  = 0x00  # 0
MOD_CTRL  = 0x01  # 1: Control (KEY_LEFT_CTRL)
MOD_SHIFT = 0x02  # 2: Shift (KEY_LEFT_SHIFT)
MOD_ALT   = 0x04  # 4: Option / Alt (KEY_LEFT_ALT)
MOD_CMD   = 0x08  # 8: Command / GUI (KEY_LEFT_GUI)

# Special Non-Printing Keycodes (matching USBHIDKeyboard.h)
KEY_UP_ARROW    = 0xDA  # 218
KEY_DOWN_ARROW  = 0xD9  # 217
KEY_LEFT_ARROW  = 0xD8  # 216
KEY_RIGHT_ARROW = 0xD7  # 215
KEY_RETURN      = 0xB0  # 176
KEY_ESC         = 0xB1  # 177
KEY_TAB         = 0xB3  # 179
KEY_BACKSPACE   = 0xB2  # 178
KEY_F11         = 0xCC  # 204

# Consumer Control Usages (matching USBHIDConsumerControl.h)
CONS_NONE                         = 0
CONS_MUTE                         = 0x00E2  # 226
CONS_VOL_UP                       = 0x00E9  # 233
CONS_VOL_DOWN                     = 0x00EA  # 234
CONS_PLAY_PAUSE                   = 0x00CD  # 205
CONSUMER_CONTROL_MUTE             = CONS_MUTE
CONSUMER_CONTROL_VOLUME_INCREMENT = CONS_VOL_UP
CONSUMER_CONTROL_VOLUME_DECREMENT = CONS_VOL_DOWN
CONSUMER_CONTROL_PLAY_PAUSE       = CONS_PLAY_PAUSE

# Profiles Catalog (exactly 6 buttons per profile)
PROFILES: Dict[str, Dict[str, Any]] = {
    "vscode": {
        "app": "VS Code",
        "bundle_ids": [
            "com.microsoft.VSCode",
            "com.vscodium",
            "com.microsoft.VSCodeInsiders",
            "com.visualstudio.code.oss",
        ],
        "color": "0x007ACC",
        "buttons": [
            {"label": "Pal",   "mod": MOD_CMD | MOD_SHIFT, "key": ord('p'),  "cons": 0, "color": "0x007ACC"},
            {"label": "File",  "mod": MOD_CMD,              "key": ord('p'),  "cons": 0, "color": "0x007ACC"},
            {"label": "Term",  "mod": MOD_CTRL,             "key": ord('`'),  "cons": 0, "color": "0x30D158"},
            {"label": "Split", "mod": MOD_CMD,              "key": ord('\\'), "cons": 0, "color": "0x007ACC"},
            {"label": "Git",   "mod": MOD_CTRL | MOD_SHIFT, "key": ord('g'),  "cons": 0, "color": "0xFF9F0A"},
            {"label": "Fmt",   "mod": MOD_SHIFT | MOD_ALT,  "key": ord('f'),  "cons": 0, "color": "0xBF5AF2"},
        ]
    },
    "chrome": {
        "app": "Chrome",
        "bundle_ids": [
            "com.google.Chrome",
            "com.google.Chrome.canary",
            "com.brave.Browser",
            "com.apple.Safari",
            "company.thebrowser.Browser",
            "org.mozilla.firefox",
        ],
        "color": "0x4285F4",
        "buttons": [
            {"label": "DevTools", "mod": MOD_CMD | MOD_ALT,   "key": ord('i'), "cons": 0, "color": "0x4285F4"},
            {"label": "Reopen",   "mod": MOD_CMD | MOD_SHIFT, "key": ord('t'), "cons": 0, "color": "0x34A853"},
            {"label": "New Tab",  "mod": MOD_CMD,              "key": ord('t'), "cons": 0, "color": "0x4285F4"},
            {"label": "Reload",   "mod": MOD_CMD | MOD_SHIFT, "key": ord('r'), "cons": 0, "color": "0xEA4335"},
            {"label": "Close",    "mod": MOD_CMD,              "key": ord('w'), "cons": 0, "color": "0xFBBC05"},
            {"label": "Bookmark", "mod": MOD_CMD,              "key": ord('d'), "cons": 0, "color": "0x4285F4"},
        ]
    },
    "terminal": {
        "app": "Terminal",
        "bundle_ids": [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable",
            "com.mitchellh.ghostty",
            "io.alacritty",
            "net.kovidgoyal.kitty",
        ],
        "color": "0x30D158",
        "buttons": [
            {"label": "Clear",   "mod": MOD_CMD,  "key": ord('k'), "cons": 0, "color": "0x30D158"},
            {"label": "New Tab", "mod": MOD_CMD,  "key": ord('t'), "cons": 0, "color": "0x30D158"},
            {"label": "Split",   "mod": MOD_CMD,  "key": ord('d'), "cons": 0, "color": "0x0A84FF"},
            {"label": "Find",    "mod": MOD_CMD,  "key": ord('f'), "cons": 0, "color": "0xFF9F0A"},
            {"label": "Cancel",  "mod": MOD_CTRL, "key": ord('c'), "cons": 0, "color": "0xFF453A"},
            {"label": "Close",   "mod": MOD_CMD,  "key": ord('w'), "cons": 0, "color": "0x8E8E93"},
        ]
    },
    "slack": {
        "app": "Slack",
        "bundle_ids": [
            "com.tinyspeck.slackmacgap",
        ],
        "color": "0x4A154B",
        "buttons": [
            {"label": "Switch", "mod": MOD_CMD,              "key": ord('k'), "cons": 0, "color": "0x4A154B"},
            {"label": "Unread", "mod": MOD_CMD | MOD_SHIFT, "key": ord('a'), "cons": 0, "color": "0x1264A3"},
            {"label": "DMs",    "mod": MOD_CMD | MOD_SHIFT, "key": ord('k'), "cons": 0, "color": "0x2BAC76"},
            {"label": "Search", "mod": MOD_CMD,              "key": ord('g'), "cons": 0, "color": "0xECB22E"},
            {"label": "Huddle", "mod": MOD_CMD | MOD_SHIFT, "key": ord(' '), "cons": 0, "color": "0xE01E5A"},
            {"label": "Back",   "mod": MOD_CMD,              "key": ord('['), "cons": 0, "color": "0x4A154B"},
        ]
    },
    "default": {
        "app": "Default",
        "bundle_ids": [
            "com.apple.finder",
            "default",
        ],
        "color": "0x0A84FF",
        "buttons": [
            {"label": "Mission",   "mod": MOD_CTRL, "key": KEY_UP_ARROW,   "cons": 0,                     "color": "0x0A84FF"},
            {"label": "Desktop",   "mod": MOD_NONE, "key": KEY_F11,        "cons": 0,                     "color": "0x5E5CE6"},
            {"label": "Space L",   "mod": MOD_CTRL, "key": KEY_LEFT_ARROW, "cons": 0,                     "color": "0x30D158"},
            {"label": "Space R",   "mod": MOD_CTRL, "key": KEY_RIGHT_ARROW,"cons": 0,                     "color": "0x30D158"},
            {"label": "Mute",      "mod": MOD_NONE, "key": 0,               "cons": CONSUMER_CONTROL_MUTE,"color": "0xFF453A"},
            {"label": "Spotlight", "mod": MOD_CMD,  "key": ord(' '),        "cons": 0,                     "color": "0xFF9F0A"},
        ]
    }
}


def get_profile_for_app(bundle_id: str, app_name: str = "") -> Dict[str, Any]:
    """Matches an active application bundle ID or display name to its shortcut profile."""
    if not bundle_id and not app_name:
        return PROFILES["default"]

    bundle_lower = bundle_id.lower().strip() if bundle_id else ""
    app_lower = app_name.lower().strip() if app_name else ""

    # 1. Exact or substring bundle ID match
    for profile in PROFILES.values():
        for bid in profile.get("bundle_ids", []):
            bid_lower = bid.lower()
            if bundle_lower and (bid_lower == bundle_lower or bid_lower in bundle_lower or bundle_lower in bid_lower):
                return profile

    # 2. Fuzzy display name heuristics
    if "code" in app_lower or "codium" in app_lower:
        return PROFILES["vscode"]
    if "chrome" in app_lower or "safari" in app_lower or "brave" in app_lower or "firefox" in app_lower:
        return PROFILES["chrome"]
    if "terminal" in app_lower or "iterm" in app_lower or "warp" in app_lower or "ghostty" in app_lower:
        return PROFILES["terminal"]
    if "slack" in app_lower:
        return PROFILES["slack"]

    return PROFILES["default"]


def get_profile_for_bundle(bundle_id: str) -> Dict[str, Any]:
    """Alias for get_profile_for_app."""
    return get_profile_for_app(bundle_id)


def build_app_payload(profile: Dict[str, Any]) -> Dict[str, Any]:
    """Constructs the exact serial wire dictionary for transmission."""
    return {
        "type": "app",
        "app": profile["app"],
        "color": profile["color"],
        "buttons": [
            {
                "label": btn["label"],
                "mod": btn["mod"],
                "key": btn["key"],
                "cons": btn["cons"],
                "color": btn["color"],
            }
            for btn in profile["buttons"]
        ]
    }


def build_app_wire_payload(profile: Dict[str, Any]) -> Dict[str, Any]:
    """Alias for build_app_payload."""
    return build_app_payload(profile)


class FrontmostAppDetector:
    """
    Monitors the active macOS frontmost application with 250ms debouncing.
    Uses /usr/bin/lsappinfo as primary detector (<20ms) with osascript fallback.
    """

    def __init__(self, debounce_seconds: float = 0.25):
        self.debounce_seconds = debounce_seconds
        self.confirmed_bundle_id: Optional[str] = None
        self.confirmed_app_name: Optional[str] = None
        self.pending_bundle_id: Optional[str] = None
        self.pending_app_name: Optional[str] = None
        self.pending_since: float = 0.0

    def query_frontmost_raw(self) -> Tuple[str, str]:
        """Queries the frontmost app bundle ID and display name."""
        # Primary: lsappinfo
        try:
            asn = subprocess.check_output(
                ["/usr/bin/lsappinfo", "front"],
                stderr=subprocess.DEVNULL,
                timeout=0.5
            ).decode().strip()

            if asn:
                info = subprocess.check_output(
                    ["/usr/bin/lsappinfo", "info", "-app", asn],
                    stderr=subprocess.DEVNULL,
                    timeout=0.5
                ).decode()

                m_bundle = re.search(r'bundleID="([^"]+)"', info)
                m_name = re.search(r'^"([^"]+)"', info)

                bundle_id = m_bundle.group(1) if m_bundle else ""
                name = m_name.group(1) if m_name else ""

                if bundle_id:
                    return bundle_id, name
        except Exception:
            pass

        # Fallback: osascript
        try:
            cmd = (
                'tell application "System Events" to set p to first application process '
                'whose frontmost is true\n'
                'return (bundle identifier of p) & "," & (name of p)'
            )
            res = subprocess.check_output(
                ["osascript", "-e", cmd],
                stderr=subprocess.DEVNULL,
                timeout=1.0
            ).decode().strip()
            parts = res.split(",", 1)
            bundle_id = parts[0].strip()
            name = parts[1].strip() if len(parts) > 1 else bundle_id
            if bundle_id:
                return bundle_id, name
        except Exception:
            pass

        return "com.apple.finder", "Finder"

    def update(self, force_immediate: bool = False) -> Optional[str]:
        """
        Polls the frontmost application and applies the debounce filter.
        Returns the confirmed bundle_id if a stable change occurred, else None.
        If force_immediate is True, bypasses debounce (e.g. on serial connection).
        """
        candidate_bundle, candidate_name = self.query_frontmost_raw()
        now = time.monotonic()

        if force_immediate or self.confirmed_bundle_id is None:
            self.confirmed_bundle_id = candidate_bundle
            self.confirmed_app_name = candidate_name
            self.pending_bundle_id = None
            self.pending_app_name = None
            return self.confirmed_bundle_id

        if candidate_bundle == self.confirmed_bundle_id:
            # Reverted back to confirmed app before debounce expired
            self.pending_bundle_id = None
            self.pending_app_name = None
            return None

        # Candidate differs from confirmed
        if candidate_bundle != self.pending_bundle_id:
            # New candidate observed; reset debounce timer
            self.pending_bundle_id = candidate_bundle
            self.pending_app_name = candidate_name
            self.pending_since = now
            return None

        # Same pending candidate; check if debounce duration has elapsed
        if (now - self.pending_since) >= self.debounce_seconds:
            self.confirmed_bundle_id = self.pending_bundle_id
            self.confirmed_app_name = self.pending_app_name
            self.pending_bundle_id = None
            self.pending_app_name = None
            return self.confirmed_bundle_id

        return None
