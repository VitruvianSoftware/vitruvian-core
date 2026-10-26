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

load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("//tools/delivery:defs.bzl", "delivery")

package(default_visibility = ["//apps/embedded/esp32-s3:__subpackages__"])

# The three flashable images, compiled by PlatformIO. NOT stamped: a genrule's
# action sees no HOME/USER/git and none of the caller's env (see
# build_firmware.sh), so version/grade/commit are applied by :publish, outside
# Bazel, where the release context exists.
genrule(
    name = "firmware",
    srcs = glob([
        "src/**",
        "include/**",
    ]) + ["platformio.ini"],
    outs = [
        "firmware.bin",
        "bootloader.bin",
        "partitions.bin",
    ],
    cmd = "$(location :builder) --project_dir apps/embedded/esp32-s3 --out_firmware $(location firmware.bin) --out_bootloader $(location bootloader.bin) --out_partitions $(location partitions.bin)",
    tags = [
        "local",
        "manual",
        "no-remote-exec",
        "requires-network",
    ],
    tools = [":builder"],
)

sh_binary(
    name = "builder",
    srcs = ["build_firmware.sh"],
    tags = ["manual"],
)

# `bazel run //apps/embedded/esp32-s3:flash [-- /dev/cu.usbmodemXXXX]`: the images land
# beside flash.sh in runfiles, which is the bundle layout it flashes from.
sh_binary(
    name = "flash",
    srcs = ["flash.sh"],
    data = [":firmware"],
    tags = [
        "local",
        "manual",
    ],
)

# Read by //tools/delivery/gen's guard that every `run:` in the generated
# workflow points at a script that exists and is executable.
exports_files(["publish.sh"])

# Build + stamp + upload. The generated delivery workflow runs the script
# directly (`bash apps/embedded/esp32-s3/publish.sh`); this target is the break-glass
# path the runbook points at, and what the delivery() below names as `run`.
sh_binary(
    name = "publish",
    srcs = ["publish.sh"],
    tags = ["manual"],
)

# Delivery unit: the firmware release ladder.
#   beta        on every affected push to main -> rolling prerelease
#               esp32-s3-beta-latest (assets clobbered, tag moved to HEAD);
#   production  on the release-please release esp32-s3-vX.Y.Z -> assets
#               attached to that release.
# Declared here because this package owns the artifact. The release-please
# machinery that cuts the production tag lives in
# .github/workflows/iot-esp32-s3-release.yaml (release machinery, not
# delivery -- the same split as tabula-release.yaml vs delivery-tabula.yaml).
delivery(
    name = "esp32-s3",
    app = "esp32-s3",
    environments = [
        "beta",
        "production",
    ],
    # Path-only mode: this regex IS the unit's complete trigger set
    # (tools/ci/deploy-affected.sh step 2), so it names the whole package.
    extra_paths = ["apps/embedded/esp32-s3/"],
    # No GitHub Environment: the publish binds none; it uploads with the run's
    # own GITHUB_TOKEN under a job-level contents: write.
    github_environment = "",
    kind = "publish",
    legacy_job = "release-and-publish",
    legacy_workflow = ".github/workflows/iot-esp32-s3.yaml",
    promotion = "release:esp32-s3-v",
    render = "transcribed",
    run = "//apps/embedded/esp32-s3:publish",
)

# ---------------------------------------------------------------------------
# Native Rust build/flash/publish & host companion tools
# ---------------------------------------------------------------------------

rust_library(
    name = "build_firmware_lib",
    srcs = ["host_companion/src/build_firmware/lib.rs"],
    crate_name = "build_firmware",
    edition = "2021",
)

rust_binary(
    name = "build_firmware_rs",
    srcs = ["host_companion/src/build_firmware/main.rs"],
    edition = "2021",
    deps = [":build_firmware_lib"],
)

rust_test(
    name = "build_firmware_rs_test",
    size = "small",
    crate = ":build_firmware_lib",
    edition = "2021",
)

rust_library(
    name = "flash_lib",
    srcs = ["host_companion/src/flash/lib.rs"],
    crate_name = "flash",
    edition = "2021",
)

rust_binary(
    name = "flash_rs",
    srcs = ["host_companion/src/flash/main.rs"],
    edition = "2021",
    deps = [":flash_lib"],
)

rust_test(
    name = "flash_rs_test",
    size = "small",
    crate = ":flash_lib",
    edition = "2021",
)

rust_library(
    name = "publish_lib",
    srcs = ["host_companion/src/publish/lib.rs"],
    crate_name = "publish",
    edition = "2021",
)

rust_binary(
    name = "publish_rs",
    srcs = ["host_companion/src/publish/main.rs"],
    edition = "2021",
    deps = [":publish_lib"],
)

rust_test(
    name = "publish_rs_test",
    size = "small",
    crate = ":publish_lib",
    edition = "2021",
)

rust_library(
    name = "app_profiles_lib",
    srcs = ["host_companion/src/app_profiles/lib.rs"],
    crate_name = "app_profiles",
    edition = "2021",
)

rust_binary(
    name = "app_profiles_rs",
    srcs = ["host_companion/src/app_profiles/main.rs"],
    edition = "2021",
    deps = [":app_profiles_lib"],
)

rust_test(
    name = "app_profiles_rs_test",
    size = "small",
    crate = ":app_profiles_lib",
    edition = "2021",
)

rust_library(
    name = "agent_ci_monitor_lib",
    srcs = ["host_companion/src/agent_ci_monitor/lib.rs"],
    crate_name = "agent_ci_monitor",
    edition = "2021",
)

rust_binary(
    name = "agent_ci_monitor_rs",
    srcs = ["host_companion/src/agent_ci_monitor/main.rs"],
    edition = "2021",
    deps = [":agent_ci_monitor_lib"],
)

rust_test(
    name = "agent_ci_monitor_rs_test",
    size = "small",
    crate = ":agent_ci_monitor_lib",
    edition = "2021",
)

rust_library(
    name = "mac_stats_daemon_lib",
    srcs = ["host_companion/src/mac_stats_daemon/lib.rs"],
    crate_name = "mac_stats_daemon",
    edition = "2021",
)

rust_binary(
    name = "mac_stats_daemon_rs",
    srcs = ["host_companion/src/mac_stats_daemon/main.rs"],
    edition = "2021",
    deps = [":mac_stats_daemon_lib"],
)

rust_test(
    name = "mac_stats_daemon_rs_test",
    size = "small",
    crate = ":mac_stats_daemon_lib",
    edition = "2021",
)

rust_library(
    name = "firmware_tests_lib",
    srcs = glob(
        ["tests/src/*.rs"],
        exclude = ["tests/src/main.rs"],
    ),
    crate_name = "firmware_tests",
    crate_root = "tests/src/lib.rs",
    data = glob([
        "src/**",
        "include/**",
        "host_companion/**",
        "docs/**",
        "tests/*.py",
    ]) + [
        "OWNERS",
        "README.md",
        "catalog-info.yaml",
        "platformio.ini",
    ],
    edition = "2021",
    deps = [
        ":agent_ci_monitor_lib",
        ":app_profiles_lib",
        ":mac_stats_daemon_lib",
    ],
)

rust_binary(
    name = "firmware_tests_rs",
    srcs = ["tests/src/main.rs"],
    edition = "2021",
    deps = [":firmware_tests_lib"],
)

rust_test(
    name = "firmware_tests_rs_test",
    size = "small",
    crate = ":firmware_tests_lib",
    edition = "2021",
)
