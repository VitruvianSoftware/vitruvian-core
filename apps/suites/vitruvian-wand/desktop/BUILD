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
    "//apps/suites/vitruvian-wand/build:defs.bzl",
    "vitruvian_wand_rust_binary",
    "vitruvian_wand_rust_clippy",
    "vitruvian_wand_rust_library",
    "vitruvian_wand_rust_test",
)

package(default_visibility = ["//apps/suites/vitruvian-wand:__subpackages__"])

exports_files([
    "Cargo.toml",
])

_DESKTOP_OS = select({
    "@platforms//os:linux": [],
    "@platforms//os:macos": [],
    "//conditions:default": ["@platforms//:incompatible"],
})

_DEPS = [
    "//apps/suites/vitruvian-wand/core:vitruvian_wand_core",
    "@vitruvian_wand_crates//:btleplug",
    "@vitruvian_wand_crates//:eframe",
    "@vitruvian_wand_crates//:egui",
    "@vitruvian_wand_crates//:futures",
    "@vitruvian_wand_crates//:log",
    "@vitruvian_wand_crates//:serde",
    "@vitruvian_wand_crates//:serde_json",
    "@vitruvian_wand_crates//:tokio",
    "@vitruvian_wand_crates//:toml",
    "@vitruvian_wand_crates//:tray-icon",
    "@vitruvian_wand_crates//:uuid",
] + select({
    "@platforms//os:linux": [
        "@vitruvian_wand_crates//:dbus",
        "@vitruvian_wand_crates//:evdev",
    ],
    "@platforms//os:macos": [
        "@vitruvian_wand_crates//:core-foundation",
        "@vitruvian_wand_crates//:core-graphics",
        "@vitruvian_wand_crates//:objc2",
        "@vitruvian_wand_crates//:objc2-app-kit",
        "@vitruvian_wand_crates//:objc2-foundation",
    ],
    "//conditions:default": [],
})

vitruvian_wand_rust_library(
    name = "vitruvian_wand_desktop",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "vitruvian_wand_desktop",
    crate_root = "src/lib.rs",
    edition = "2024",
    target_compatible_with = _DESKTOP_OS,
    deps = _DEPS,
)

vitruvian_wand_rust_binary(
    name = "vitruvian-wand",
    srcs = ["src/main.rs"],
    edition = "2024",
    target_compatible_with = _DESKTOP_OS,
    deps = [":vitruvian_wand_desktop"] + _DEPS,
)

vitruvian_wand_rust_test(
    name = "vitruvian_wand_desktop_test",
    size = "small",
    srcs = glob(["tests/**/*.rs"]),
    compile_data = [
        "//apps/suites/vitruvian-wand/core:testdata/daydream_axes.replay",
        "//apps/suites/vitruvian-wand/core:testdata/session.replay",
    ],
    data = [
        "//apps/suites/vitruvian-wand/core:testdata/daydream_axes.replay",
        "//apps/suites/vitruvian-wand/core:testdata/session.replay",
    ],
    edition = "2024",
    target_compatible_with = _DESKTOP_OS,
    deps = [
        ":vitruvian_wand_desktop",
    ] + _DEPS,
)

vitruvian_wand_rust_clippy(
    name = "vitruvian_wand_clippy",
    testonly = True,
    target_compatible_with = _DESKTOP_OS,
    deps = [
        ":vitruvian-wand",
        ":vitruvian_wand_desktop",
        ":vitruvian_wand_desktop_test",
    ],
)
