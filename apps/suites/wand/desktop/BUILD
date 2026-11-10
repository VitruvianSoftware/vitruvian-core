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

# gazelle:ignore

load(
    "//apps/suites/wand/build:defs.bzl",
    "wand_rust_binary",
    "wand_rust_clippy",
    "wand_rust_library",
    "wand_rust_test",
)

package(default_visibility = ["//apps/suites/wand:__subpackages__"])

exports_files([
    "Cargo.toml",
])

_DESKTOP_OS = select({
    "@platforms//os:linux": [],
    "@platforms//os:macos": [],
    "//conditions:default": ["@platforms//:incompatible"],
})

_DEPS = [
    "//apps/suites/wand/core:wand_core",
    "@wand_crates//:btleplug",
    "@wand_crates//:eframe",
    "@wand_crates//:egui",
    "@wand_crates//:futures",
    "@wand_crates//:log",
    "@wand_crates//:serde",
    "@wand_crates//:serde_json",
    "@wand_crates//:tokio",
    "@wand_crates//:toml",
    "@wand_crates//:tray-icon",
    "@wand_crates//:uuid",
] + select({
    "@platforms//os:linux": [
        "@wand_crates//:dbus",
        "@wand_crates//:evdev",
    ],
    "@platforms//os:macos": [
        "@wand_crates//:core-foundation",
        "@wand_crates//:core-graphics",
        "@wand_crates//:objc2",
        "@wand_crates//:objc2-app-kit",
        "@wand_crates//:objc2-foundation",
    ],
    "//conditions:default": [],
})

wand_rust_library(
    name = "wand_desktop",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "wand_desktop",
    crate_root = "src/lib.rs",
    edition = "2024",
    target_compatible_with = _DESKTOP_OS,
    deps = _DEPS,
)

wand_rust_binary(
    name = "wand",
    srcs = ["src/main.rs"],
    edition = "2024",
    target_compatible_with = _DESKTOP_OS,
    deps = [":wand_desktop"] + _DEPS,
)

wand_rust_test(
    name = "wand_desktop_test",
    size = "small",
    srcs = glob(["tests/**/*.rs"]),
    compile_data = [
        "//apps/suites/wand/core:testdata/daydream_axes.replay",
        "//apps/suites/wand/core:testdata/session.replay",
    ],
    data = [
        "//apps/suites/wand/core:testdata/daydream_axes.replay",
        "//apps/suites/wand/core:testdata/session.replay",
    ],
    edition = "2024",
    target_compatible_with = _DESKTOP_OS,
    deps = [
        ":wand_desktop",
    ] + _DEPS,
)

wand_rust_clippy(
    name = "wand_clippy",
    testonly = True,
    target_compatible_with = _DESKTOP_OS,
    deps = [
        ":wand",
        ":wand_desktop",
        ":wand_desktop_test",
    ],
)
