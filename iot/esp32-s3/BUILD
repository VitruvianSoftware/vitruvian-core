# gazelle:ignore

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

package(default_visibility = ["//visibility:public"])

# ESP32-S3 firmware build target
# Generates the application firmware, bootloader, partition table, and full distribution zip bundle.
# Tagged "manual" so it is only built when explicitly requested (e.g. CI workflow or local development)
# and does not interfere with repo-wide //... sweeps on standard Linux cloud runners.
genrule(
    name = "firmware",
    srcs = glob([
        "src/**",
        "include/**",
    ]) + [
        "platformio.ini",
        ".release-please-manifest.json",
    ],
    outs = [
        "firmware.bin",
        "bootloader.bin",
        "partitions.bin",
        "esp32-s3-mac-controller.zip",
    ],
    cmd = "$(location :builder) --project_dir iot/esp32-s3 --out_firmware $(location firmware.bin) --out_bootloader $(location bootloader.bin) --out_partitions $(location partitions.bin) --out_zip $(location esp32-s3-mac-controller.zip)",
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

# Convenience target to flash the firmware directly to an ESP32-S3 board over USB:
#   bazel run //iot/esp32-s3:flash
#   bazel run //iot/esp32-s3:flash -- /dev/cu.usbmodemXXXX
sh_binary(
    name = "flash",
    srcs = ["flash.sh"],
    data = [
        "platformio.ini",
        ":firmware",
    ],
    tags = [
        "local",
        "manual",
    ],
)
