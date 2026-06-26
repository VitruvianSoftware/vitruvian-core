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
"""
Starlark rule and macro for addlicense run targets.

Provides `addlicense_run_target`, a macro that generates a `bazel run`
target wrapping addlicense so that it operates on the workspace root
regardless of where Bazel's runfiles directory lives.
"""

def _addlicense_launcher_impl(ctx):
    """Create a launcher shell script that cd's to the workspace before running addlicense."""
    addlicense = ctx.executable.addlicense
    out = ctx.actions.declare_file(ctx.attr.name + ".sh")

    # Compute the rlocation-style runfiles key for the addlicense binary.
    # ctx.executable.addlicense.short_path for an external dep is "../<repo>/<path>".
    # rlocation() accepts the runfiles-root-relative path, i.e. without the leading "../".
    short_path = addlicense.short_path
    rlocation_key = short_path[3:] if short_path.startswith("../") else short_path

    # Build the addlicense args as individual bash-array elements so that values
    # containing spaces or special characters (e.g. an apostrophe in the copyright
    # holder name) are passed safely without word-splitting or glob expansion.
    #
    # Each element is emitted as a double-quoted bash string.  We escape any
    # literal double-quote or backslash that appears in the value so the generated
    # script is syntactically valid regardless of user input.
    def _bash_quote(s):
        # Escape backslashes first, then double-quotes.
        return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

    args_starlark = ctx.attr.addlicense_args  # list of strings
    array_lines = "\n".join(["  " + _bash_quote(a) for a in args_starlark])

    ctx.actions.write(
        output = out,
        is_executable = True,
        content = """\
#!/usr/bin/env bash
# --- begin runfiles.bash initialization v3 ---
set -uo pipefail; set +e
f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \\
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \\
  source "$0.runfiles/$f" 2>/dev/null || \\
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \\
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \\
  { echo>&2 "ERROR: cannot find runfiles.bash"; exit 1; }; f=; set -e
# --- end runfiles.bash initialization v3 ---

ADDLICENSE="$(rlocation %s)"

# Build args as an array so values with spaces/apostrophes are safe.
ADDLICENSE_ARGS=(
%s
)

# cd to the workspace root (bazel run sets BUILD_WORKSPACE_DIRECTORY).
cd "$BUILD_WORKSPACE_DIRECTORY"

exec "$ADDLICENSE" "${ADDLICENSE_ARGS[@]}" .
""" % (rlocation_key, array_lines),
    )

    # Merge in the runfiles for addlicense AND the standard bash runfiles library.
    runfiles = ctx.runfiles(files = [addlicense])
    runfiles = runfiles.merge(ctx.attr.addlicense[DefaultInfo].default_runfiles)
    runfiles = runfiles.merge(ctx.attr._runfiles_lib[DefaultInfo].default_runfiles)

    return [DefaultInfo(
        executable = out,
        runfiles = runfiles,
    )]

_addlicense_launcher = rule(
    implementation = _addlicense_launcher_impl,
    attrs = {
        "addlicense": attr.label(
            executable = True,
            cfg = "exec",
            mandatory = True,
            doc = "The addlicense binary label.",
        ),
        "addlicense_args": attr.string_list(
            mandatory = True,
            doc = "Flags to pass to addlicense as individual array elements (copyright, license, check, ignores).",
        ),
        "_runfiles_lib": attr.label(
            default = Label("@bazel_tools//tools/bash/runfiles"),
            doc = "Standard Bazel bash runfiles library.",
        ),
    },
    executable = True,
    doc = "Generates a workspace-scanning addlicense launcher for `bazel run`.",
)

def addlicense_run_target(name, copyright, license_flag, ignore_globs, check_mode, visibility = None):
    """Generate a `bazel run` target that invokes addlicense over the workspace.

    The generated target cd's to $BUILD_WORKSPACE_DIRECTORY (set by `bazel run`)
    before scanning, so it operates on the real source tree rather than the
    Bazel runfiles directory.

    Args:
        name: target name.
        copyright: copyright holder string (passed as addlicense -c flag).
            May contain spaces and apostrophes — handled safely via a bash array.
        license_flag: addlicense -l value (apache / mit / bsd / mpl).
        ignore_globs: list of glob pattern strings to ignore (each becomes a
            separate -ignore <pattern> pair of array elements).
        check_mode: if True, pass -check (verify only; don't modify files).
        visibility: standard Bazel visibility list.
    """

    # Build the args list as individual elements — no word-splitting at runtime.
    args = ["-c", copyright, "-l", license_flag]
    if check_mode:
        args.append("-check")
    for glob in ignore_globs:
        args.append("-ignore")
        args.append(glob)

    _addlicense_launcher(
        name = name,
        addlicense = "@multitool//tools/addlicense",
        addlicense_args = args,
        visibility = visibility,
    )
