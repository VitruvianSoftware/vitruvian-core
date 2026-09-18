load("@build_bazel_rules_apple//apple:macos.bzl", "macos_application")
load("@build_bazel_rules_swift//swift:swift_library.bzl", "swift_library")
load("@build_bazel_rules_swift//swift:swift_test.bzl", "swift_test")

swift_library(
    name = "HomeSpeakerCore",
    srcs = glob(["Sources/HomeSpeakerCore/**/*.swift"]),
    module_name = "HomeSpeakerCore",
    target_compatible_with = ["@platforms//os:macos"],
)

swift_library(
    name = "HomeSpeakerLib",
    srcs = glob(["Sources/HomeSpeaker/**/*.swift"]),
    module_name = "HomeSpeaker",
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":HomeSpeakerCore"],
)

swift_test(
    name = "HomeSpeakerTests",
    srcs = glob(["Tests/**/*.swift"]),
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:macos"],
    deps = [":HomeSpeakerCore"],
)

macos_application(
    name = "HomeSpeaker",
    bundle_id = "com.vitruviansoftware.homespeaker",
    infoplists = ["Resources/Info.plist"],
    minimum_os_version = "14.0",
    resources = ["Resources/AppIcon.icns"],
    tags = ["manual"],
    visibility = ["//visibility:public"],
    deps = [":HomeSpeakerLib"],
)
