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

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("//tools/delivery:defs.bzl", "delivery")

package(default_visibility = ["//visibility:public"])

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
    cmd = "$(location :builder) --project_dir iot/esp32-s3 --out_firmware $(location firmware.bin) --out_bootloader $(location bootloader.bin) --out_partitions $(location partitions.bin)",
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

# `bazel run //iot/esp32-s3:flash [-- /dev/cu.usbmodemXXXX]`: the images land
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
# directly (`bash iot/esp32-s3/publish.sh`); this target is the break-glass
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
# delivery -- the same split as tabula-release.yaml vs delivery.yaml).
delivery(
    name = "esp32-s3",
    environments = [
        "beta",
        "production",
    ],
    # Path-only mode: this regex IS the unit's complete trigger set
    # (tools/ci/deploy-affected.sh step 2), so it names the whole package.
    extra_paths = ["iot/esp32-s3/"],
    # No GitHub Environment: the publish binds none; it uploads with the run's
    # own GITHUB_TOKEN under a job-level contents: write.
    github_environment = "",
    kind = "publish",
    legacy_job = "release-and-publish",
    legacy_workflow = ".github/workflows/iot-esp32-s3.yaml",
    promotion = "release:esp32-s3-v",
    render = "transcribed",
    run = "//iot/esp32-s3:publish",
)
