#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware

"""Derive the bundle's Info.plist from upstream's Resources/Info.plist.

rules_apple validates CFBundleShortVersionString against Apple's format (one to
four dot-separated integers) and rejects upstream's pre-release versions such
as `3.4.1-beta.1`, which build.sh copies into the bundle unchecked. Keep the
numeric prefix and record the full upstream version under its own key so it is
not lost. Everything else passes through unchanged.

usage: bundle_info_plist.py <in Info.plist> <out Info.plist>
"""

import plistlib
import re
import sys


def main(source, target):
    with open(source, "rb") as f:
        plist = plistlib.load(f)
    version = plist["CFBundleShortVersionString"]
    numeric = re.match(r"\d+(?:\.\d+){0,3}", version)
    if numeric is None:
        sys.exit(
            f"{source}: CFBundleShortVersionString {version!r} has no numeric prefix"
        )
    plist["CFBundleShortVersionString"] = numeric.group(0)
    plist["VitruvianUpstreamVersion"] = version
    with open(target, "wb") as f:
        plistlib.dump(plist, f)


if __name__ == "__main__":
    main(*sys.argv[1:])
