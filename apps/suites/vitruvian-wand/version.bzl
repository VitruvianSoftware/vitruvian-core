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

"""Vitruvian Wand's version: the one place it is written.

release-please bumps the line below (the `x-release-please-version` marker) in
the release PR, together with Cargo.toml and .release-please-manifest.json.
The Android versionName and versionCode, the desktop binary's
CARGO_PKG_VERSION and both apps' crash-report release names all come from it.
//apps/suites/vitruvian-wand/build/release:release_test fails if the three
files disagree.
"""

VITRUVIAN_WAND_VERSION = "0.1.2"  # x-release-please-version

def _version_code(version):
    parts = version.split(".")
    if len(parts) != 3:
        fail("VITRUVIAN_WAND_VERSION must be major.minor.patch, got %s" % version)
    major, minor, patch = [int(p) for p in parts]
    if minor > 99 or patch > 99:
        fail("minor and patch must be under 100 for the Android versionCode, got %s" % version)
    return major * 10000 + minor * 100 + patch

# Android's versionCode: 0.1.0 is 100, 1.2.3 is 10203. Always above the 1 the
# app shipped with before releases, so every release installs over it.
VITRUVIAN_WAND_VERSION_CODE = _version_code(VITRUVIAN_WAND_VERSION)
