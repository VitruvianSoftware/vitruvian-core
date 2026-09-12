load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_library")

py_binary(
    name = "stream_hook",
    srcs = ["stream_hook.py"],
    visibility = ["//:__subpackages__"],
)

alias(
    name = "stream-hook",
    actual = ":stream_hook",
    visibility = ["//:__subpackages__"],
)

py_library(
    name = "hooks",
    srcs = ["stream_hook.py"],
    visibility = ["//:__subpackages__"],
)
