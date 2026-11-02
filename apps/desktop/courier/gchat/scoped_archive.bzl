# Copyright 2026 VitruvianSoftware
# SPDX-License-Identifier: AGPL-3.0-or-later

"""The command that turns a Rust static library into one relocatable object exporting only `_gchat_*`."""

# The relocatable link below runs the system clang, which links for the
# machine it runs on unless told otherwise. Name the CPU the archive is being
# built for, so an x86_64 build (the release's universal engine) gets an x86_64
# object and not an arm64 one.
def _scoped_archive_cmd(arch, check_leaks, tmp_prefix, src):
    """The genrule command for one CPU."""
    leak_check = """
        if /usr/bin/nm -g $(location {src}) 2>/dev/null | /usr/bin/grep -Eq 'gchat_test_only|manual_clock|fuzz_'; then
            echo "ERROR: test-loopback, manual_clock, or fuzz symbol leaked into production gchat_static" >&2
            exit 1
        fi""".format(src = src) if check_leaks else ""
    return """
        set -eu{leak_check}
        REL_OBJ="$$(mktemp -t {tmp_prefix}).o"
        trap 'rm -f "$$REL_OBJ"' EXIT
        /usr/bin/clang -arch {arch} -nostdlib -r -Wl,-exported_symbol,'_gchat_*' -Wl,-all_load $(location {src}) -o "$$REL_OBJ"
        /usr/bin/ar rcs $@ "$$REL_OBJ"
    """.format(arch = arch, leak_check = leak_check, tmp_prefix = tmp_prefix, src = src)

def scoped_archive_cmds(check_leaks, tmp_prefix, src):
    """The genrule command, for whichever CPU the archive is built for.

    Args:
      check_leaks: refuse an archive holding test-only symbols.
      tmp_prefix: mktemp prefix for the relocatable object.
      src: the rust_static_library label.

    Returns:
      A select() of commands.
    """
    return select({
        "@platforms//cpu:x86_64": _scoped_archive_cmd("x86_64", check_leaks, tmp_prefix, src),
        "//conditions:default": _scoped_archive_cmd("arm64", check_leaks, tmp_prefix, src),
    })
