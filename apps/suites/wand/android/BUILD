# Copyright (c) 2026 VitruvianSoftware
# gazelle:ignore

load("@rules_android//android:rules.bzl", "android_binary")
load("@rules_kotlin//kotlin:android.bzl", "kt_android_library")
load("@rules_kotlin//kotlin:jvm.bzl", "kt_jvm_library", "kt_jvm_test")
load("//apps/suites/wand/android:defs.bzl", "wand_multi_abi_apk")

package(default_visibility = ["//apps/suites/wand/android:__subpackages__"])

kt_jvm_library(
    name = "core",
    srcs = glob(["src/main/kotlin/dev/vitruvian/wand/core/*.kt"]),
)

kt_jvm_test(
    name = "gesture_planner_test",
    size = "small",
    srcs = ["src/test/kotlin/dev/vitruvian/wand/core/GesturePlannerTest.kt"],
    test_class = "dev.vitruvian.wand.core.GesturePlannerTest",
    deps = [
        ":core",
        "@maven//:junit_junit",
    ],
)

kt_jvm_test(
    name = "actions_test",
    size = "small",
    srcs = ["src/test/kotlin/dev/vitruvian/wand/core/ActionsTest.kt"],
    test_class = "dev.vitruvian.wand.core.ActionsTest",
    deps = [
        ":core",
        "@maven//:junit_junit",
    ],
)

kt_jvm_test(
    name = "stroke_coordinator_test",
    size = "small",
    srcs = ["src/test/kotlin/dev/vitruvian/wand/core/StrokeCoordinatorTest.kt"],
    test_class = "dev.vitruvian.wand.core.StrokeCoordinatorTest",
    deps = [
        ":core",
        "@maven//:junit_junit",
    ],
)

kt_jvm_test(
    name = "native_engine_test",
    size = "small",
    srcs = ["src/test/kotlin/dev/vitruvian/wand/core/NativeEngineTest.kt"],
    test_class = "dev.vitruvian.wand.core.NativeEngineTest",
    deps = [
        ":core",
        "@maven//:junit_junit",
    ],
)

test_suite(
    name = "core_test",
    tests = [
        ":actions_test",
        ":gesture_planner_test",
        ":native_engine_test",
        ":stroke_coordinator_test",
    ],
)

kt_android_library(
    name = "lib",
    srcs = glob(
        ["src/main/kotlin/**/*.kt"],
        exclude = ["src/main/kotlin/dev/vitruvian/wand/core/*.kt"],
    ),
    custom_package = "dev.vitruvian.wand",
    manifest = "src/main/AndroidManifest.xml",
    plugins = ["//packages/design-system-android:compose_compiler"],
    resource_files = glob(["src/main/res/**"]),
    deps = [
        ":core",
        "//packages/design-system-android:lib",
        "@maven//:androidx_activity_activity_compose",
        "@maven//:androidx_compose_animation_animation",
        "@maven//:androidx_compose_foundation_foundation",
        "@maven//:androidx_compose_foundation_foundation_layout",
        "@maven//:androidx_compose_runtime_runtime",
        "@maven//:androidx_compose_ui_ui",
        "@maven//:androidx_compose_ui_ui_graphics",
        "@maven//:androidx_compose_ui_ui_text",
        "@maven//:androidx_compose_ui_ui_unit",
        "@maven//:androidx_core_core",
        "@maven//:androidx_core_core_ktx",
        "@maven//:org_jetbrains_kotlinx_kotlinx_coroutines_android",
        "@maven//:org_jetbrains_kotlinx_kotlinx_coroutines_core_jvm",
    ],
)

android_binary(
    name = "wand_apk_binary",
    custom_package = "dev.vitruvian.wand",
    manifest = "src/main/AndroidManifest.xml",
    manifest_values = {
        "applicationId": "dev.vitruvian.wand",
        "minSdkVersion": "26",
        "targetSdkVersion": "35",
        "versionCode": "1",
        "versionName": "0.1.0",
    },
    tags = ["manual"],
    deps = [
        ":lib",
        "//apps/suites/wand/android/jni:wand_jni_cc",
    ],
)

wand_multi_abi_apk(
    name = "wand_apk",
    apk = ":wand_apk_binary",
)
