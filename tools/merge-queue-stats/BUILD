"""How main's merge queue did over a window: speed, ejections, breakage.

  bazel run //tools/merge-queue-stats -- --since 2026-10-05 --until 2026-10-19

Written to judge the switch to HEADGREEN grouping: run it on the window
before a queue change and the window after, and compare. See the docstring
in merge_queue_stats.py.
"""

load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_test")
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

# Hand-written: Gazelle would add a py_library named after the package, which
# the py_binary already is, so `bazel run //tools/merge-queue-stats` works.
# gazelle:ignore

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

# The same tool in Rust, standard library only: it carries what it needs of
# Python by hand (src/json.rs, src/pytime.rs for datetime.fromisoformat,
# src/argparse.rs). http:// (GITHUB_API_URL pointing at a test server or an
# Enterprise host) goes over a plain socket; https:// runs curl, since std
# has no TLS.
rust_library(
    name = "merge_queue_stats_lib",
    srcs = glob(
        ["src/**/*.rs"],
        exclude = ["src/main.rs"],
    ),
    crate_name = "merge_queue_stats",
    crate_root = "src/lib.rs",
    edition = "2021",
)

rust_binary(
    name = "merge-queue-stats-rs",
    srcs = ["src/main.rs"],
    edition = "2021",
    deps = [":merge_queue_stats_lib"],
)

alias(
    name = "merge_queue_stats_rs",
    actual = ":merge-queue-stats-rs",
)

rust_test(
    name = "merge_queue_stats_lib_test",
    size = "small",
    crate = ":merge_queue_stats_lib",
    edition = "2021",
)

# Holds the Rust binary to the Python script: both run as programs against
# one fake GitHub API on localhost, comparing exit codes, stdout, stderr and
# the requests made, on every timeline in merge_queue_stats_test.py and on
# command lines, API failures and data built to break them.
py_test(
    name = "merge_queue_stats_rs_parity_test",
    size = "small",
    srcs = [
        "merge_queue_stats.py",
        "merge_queue_stats_rs_parity_test.py",
        "merge_queue_stats_test.py",
    ],
    data = [":merge-queue-stats-rs"],
    env = {"MERGE_QUEUE_STATS_RS": "$(rootpath :merge-queue-stats-rs)"},
    imports = ["."],
    main = "merge_queue_stats_rs_parity_test.py",
)
