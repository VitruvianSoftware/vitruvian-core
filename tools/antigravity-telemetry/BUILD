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

"""Antigravity & AGY OTLP Telemetry Exporter, Hooks, and Developer Tooling."""

# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_library", "py_test")

py_library(
    name = "lib",
    srcs = [
        "antigravity_telemetry.py",
        "http_client.py",
        "otlp_builder.py",
        "session_exporter.py",
        "telemetry_hook.py",
        "telemetry_loader.py",
    ],
    imports = ["."],
    visibility = ["//visibility:public"],
)

py_binary(
    name = "antigravity-telemetry",
    srcs = ["antigravity_telemetry.py"],
    imports = ["."],
    main = "antigravity_telemetry.py",
    visibility = ["//visibility:public"],
    deps = [":lib"],
)

alias(
    name = "antigravity_telemetry",
    actual = ":antigravity-telemetry",
    visibility = ["//visibility:public"],
)

py_binary(
    name = "session-exporter",
    srcs = ["session_exporter.py"],
    imports = ["."],
    main = "session_exporter.py",
    visibility = ["//visibility:public"],
    deps = [":lib"],
)

alias(
    name = "session_exporter",
    actual = ":session-exporter",
    visibility = ["//visibility:public"],
)

py_binary(
    name = "telemetry-hook",
    srcs = ["telemetry_hook.py"],
    imports = ["."],
    main = "telemetry_hook.py",
    visibility = ["//visibility:public"],
    deps = [":lib"],
)

alias(
    name = "telemetry_hook",
    actual = ":telemetry-hook",
    visibility = ["//visibility:public"],
)

py_binary(
    name = "telemetry-loader",
    srcs = ["telemetry_loader.py"],
    imports = ["."],
    main = "telemetry_loader.py",
    visibility = ["//visibility:public"],
    deps = [":lib"],
)

alias(
    name = "telemetry_loader",
    actual = ":telemetry-loader",
    visibility = ["//visibility:public"],
)

py_test(
    name = "antigravity_telemetry_test",
    size = "small",
    srcs = ["antigravity_telemetry_test.py"],
    imports = ["."],
    main = "antigravity_telemetry_test.py",
    deps = [":lib"],
)

py_test(
    name = "session_exporter_test",
    size = "small",
    srcs = ["session_exporter_test.py"],
    imports = ["."],
    main = "session_exporter_test.py",
    deps = [":lib"],
)

py_test(
    name = "telemetry_hook_test",
    size = "small",
    srcs = ["telemetry_hook_test.py"],
    imports = ["."],
    main = "telemetry_hook_test.py",
    deps = [":lib"],
)

py_test(
    name = "telemetry_loader_test",
    size = "small",
    srcs = ["telemetry_loader_test.py"],
    imports = ["."],
    main = "telemetry_loader_test.py",
    deps = [":lib"],
)
