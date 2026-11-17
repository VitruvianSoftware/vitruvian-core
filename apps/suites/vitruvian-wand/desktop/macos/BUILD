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

# The Mac app: Vitruvian Wand.app around the desktop binary.
#
#   bazel build --config=macos-app --macos_cpus=arm64,x86_64 \
#     //apps/suites/vitruvian-wand/desktop/macos:VitruvianWand
#
# macOS asks for Bluetooth only on behalf of an app bundle with a usage
# description; a bare binary run from a terminal borrows the terminal's
# permission. So the release ships this bundle, not the binary. The output is
# VitruvianWand.zip holding the .app, which //tools/desktop-package signs with
# the Developer ID, notarises and turns into DMGs (see ../../build/release).
#
# gazelle:ignore

load("@build_bazel_rules_apple//apple:apple.bzl", "apple_universal_binary")
load("//apps/suites/vitruvian-wand:version.bzl", "VITRUVIAN_WAND_VERSION")

package(default_visibility = ["//apps/suites/vitruvian-wand:__subpackages__"])

# One binary for both Mac CPUs: built once per CPU in --macos_cpus and joined
# with lipo. A plain build (one CPU) gives a one-architecture app.
apple_universal_binary(
    name = "vitruvian_wand_universal",
    binary = "//apps/suites/vitruvian-wand/desktop:vitruvian-wand",
    minimum_os_version = "13.0",
    platform_type = "macos",
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
)

genrule(
    name = "info_plist",
    srcs = ["Info.plist.in"],
    outs = ["Info.plist"],
    cmd = "sed -e 's|@VERSION@|%s|g' $< > $@" % VITRUVIAN_WAND_VERSION,
)

# Signed ad hoc here because lipo leaves the x86_64 half unsigned and a bundle
# with an unsigned executable will not launch; the release signs it again with
# the Developer ID. The bundle is staged next to the output, in a folder no
# other rule writes.
genrule(
    name = "VitruvianWand",
    srcs = [
        ":info_plist",
        ":vitruvian_wand_universal",
    ],
    outs = ["VitruvianWand.zip"],
    cmd = """
set -euo pipefail
stage="$(RULEDIR)/VitruvianWand.stage"
app="$$stage/Vitruvian Wand.app"
mkdir -p "$$app/Contents/MacOS"
cp -f $(location :info_plist) "$$app/Contents/Info.plist"
printf 'APPL????' > "$$app/Contents/PkgInfo"
cp -f $(location :vitruvian_wand_universal) "$$app/Contents/MacOS/vitruvian-wand"
chmod 755 "$$app/Contents/MacOS/vitruvian-wand"
/usr/bin/codesign --force --sign - --identifier com.vitruviansoftware.wand "$$app"
out="$$PWD/$@"
(cd "$$stage" && /usr/bin/ditto -c -k --keepParent "Vitruvian Wand.app" "$$out")
""",
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
)
