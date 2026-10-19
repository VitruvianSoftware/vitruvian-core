"""How main's merge queue did over a window: speed, ejections, breakage.

  bazel run //tools/merge-queue-stats -- --since 2026-10-05 --until 2026-10-19

Written to judge the switch to HEADGREEN grouping: run it on the window
before a queue change and the window after, and compare. See the docstring
in merge_queue_stats.py.
"""

load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_test")

py_binary(
    name = "merge-queue-stats",
    srcs = ["merge_queue_stats.py"],
    imports = ["."],
    main = "merge_queue_stats.py",
)

# The counting, on hand-made timelines: no network.
py_test(
    name = "merge_queue_stats_test",
    size = "small",
    srcs = [
        "merge_queue_stats.py",
        "merge_queue_stats_test.py",
    ],
    # The folder name has a hyphen, so it cannot be a package: import by path.
    imports = ["."],
    main = "merge_queue_stats_test.py",
)
