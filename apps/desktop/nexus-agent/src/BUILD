load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# ─── Native Rust port of the Nexus Agent bridge & Telegram bot engine ────────

alias(
    name = "bot",
    actual = ":bot-engine",
    visibility = ["//apps/desktop/nexus-agent:__subpackages__"],
)

test_suite(
    name = "typecheck_typecheck_test",
    tests = [":nexus_agent_src_lib_test"],
)

rust_library(
    name = "nexus_agent_src_lib",
    srcs = [
        "rs/agy.rs",
        "rs/annotations.rs",
        "rs/bot.rs",
        "rs/formatter.rs",
        "rs/lib.rs",
        "rs/sessions.rs",
    ],
    crate_name = "nexus_agent_src_lib",
    crate_root = "rs/lib.rs",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/desktop/nexus-agent:__subpackages__"],
)

rust_binary(
    name = "bot-engine",
    srcs = ["rs/main.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    visibility = ["//apps/desktop/nexus-agent:__subpackages__"],
    deps = [":nexus_agent_src_lib"],
)

rust_test(
    name = "nexus_agent_src_lib_test",
    size = "small",
    crate = ":nexus_agent_src_lib",
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
)

rust_test(
    name = "annotations_test",
    size = "small",
    srcs = ["rs/annotations_test.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":nexus_agent_src_lib"],
)

rust_test(
    name = "formatter_test",
    size = "small",
    srcs = ["rs/formatter_test.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":nexus_agent_src_lib"],
)

rust_test(
    name = "sessions_test",
    size = "small",
    srcs = ["rs/sessions_test.rs"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":nexus_agent_src_lib"],
)

rust_test(
    name = "shared_cases_test",
    size = "small",
    srcs = ["rs/shared_cases_test.rs"],
    data = ["//apps/desktop/nexus-agent:testdata_files"],
    edition = "2021",
    rustc_flags = ["-Copt-level=3"],
    deps = [":nexus_agent_src_lib"],
)

pipeline_unit(
    name = "nexus-agent-src",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [
        ":annotations_test",
        ":annotations_test",
        ":formatter_test",
        ":formatter_test",
        ":nexus_agent_src_lib_test",
        ":sessions_test",
        ":sessions_test",
        ":shared_cases_test",
        ":shared_cases_test",
        ":typecheck_typecheck_test",
    ],
    tier = "L1",
    timeout_minutes = 15,
)

exports_files(
    [
        "bot_lib.rs",
        "bot_main.rs",
    ],
    visibility = ["//apps/desktop/nexus-agent:__pkg__"],
)
