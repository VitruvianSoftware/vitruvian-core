load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_library")

py_binary(
    name = "stream-hook",
    srcs = ["stream-hook.py"],
    visibility = ["//:__subpackages__"],
)

py_library(
    name = "hooks",
    srcs = ["stream-hook.py"],
    visibility = ["//:__subpackages__"],
)
