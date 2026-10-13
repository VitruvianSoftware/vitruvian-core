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
"""A tool that `vitruvian-tool init` has just written is one the app takes.

    init_test.py <the vitruvian-tool program>

The command is run as a person would run it. The tool it writes from the
Python template, the Python kit template and the TypeScript template must pass
`validate`, pass the conformance script, and run under `run`. The Swift
template is written and looked at here, not built:
`swift_template_test.py` builds it, against a checkout given with `--sdk`.
Without `--sdk` it must depend on the published SDK at the version the
command reports; that it resolves is checked after each release, in the
mirror's release.yml, because it needs the network. Every program started
here has thirty seconds at most.

The TypeScript tool is started by its own bin/tool, which looks for `node` on
the PATH: the folder of VITRUVIAN_NODE is put at its front. Its kit is the one
Bazel built, VITRUVIAN_TOOL_KIT_TYPESCRIPT, copied where `npm install` would
put it.
"""

import contextlib
import io
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PACKAGE = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(PACKAGE, "conformance"))

import conformance


def main(arguments):
    command = os.path.abspath(arguments[0])
    problems = []
    # The new tool's first line asks for `python3`: the one running this test.
    environment = dict(os.environ)
    environment["PATH"] = (
        os.path.dirname(sys.executable) + os.pathsep + environment.get("PATH", "")
    )
    if os.environ.get("VITRUVIAN_NODE"):
        node = os.path.dirname(os.path.abspath(os.environ["VITRUVIAN_NODE"]))
        environment["PATH"] = node + os.pathsep + environment["PATH"]
        # The conformance script starts the tool from this process.
        os.environ["PATH"] = node + os.pathsep + os.environ.get("PATH", "")

    def tool(*words):
        done = subprocess.run(
            [command, *words],
            capture_output=True,
            text=True,
            timeout=30,
            env=environment,
            check=False,
        )
        return done.returncode, done.stdout + done.stderr

    with tempfile.TemporaryDirectory(prefix="vitruvian-init-") as root:
        fresh = os.path.join(root, "fresh")
        named = [
            "--id",
            "com.example.fresh",
            "--name",
            "Fresh",
            "--publisher",
            "Example",
        ]
        status, printed = tool("init", fresh, *named)
        if status != 0 or "wrote    bin/tool.py" not in printed:
            problems.append(f"init did not write the Python template:\n{printed}")
        status, printed = tool("validate", fresh)
        if status != 0 or "ok       manifest: com.example.fresh 0.1.0" not in printed:
            problems.append(f"validate does not pass what init wrote:\n{printed}")
        said = io.StringIO()
        with contextlib.redirect_stdout(said):
            status = conformance.main(
                [fresh, "--via", sys.executable, "--expect-refusal"]
            )
        if status != 0:
            problems.append(
                f"what init wrote does not pass conformance:\n{said.getvalue()}"
            )
        status, printed = tool(
            "run", fresh, "--command", "hello", "--command", "copyTime"
        )
        if (
            status != 0
            or "ran      copyTime" not in printed
            or "run: OK" not in printed
        ):
            problems.append(f"what init wrote does not run:\n{printed}")
        status, printed = tool("init", fresh, *named)
        if status != 1 or "Nothing was written." not in printed:
            problems.append(f"init wrote over a folder that was there:\n{printed}")

        swift = os.path.join(root, "swift")
        status, printed = tool(
            "init", swift, *named, "--template", "swift", "--sdk", PACKAGE
        )
        wanted = [
            "Package.swift",
            "Sources/Tool/main.swift",
            "tool/vitruvian-tool.json",
            "build.sh",
        ]
        missing = [
            path for path in wanted if not os.path.isfile(os.path.join(swift, path))
        ]
        if status != 0 or missing:
            problems.append(
                f"init did not write the Swift template, missing {missing}:\n{printed}"
            )
        status, printed = tool("validate", os.path.join(swift, "tool"))
        if (
            status != 1
            or "the program `bin/tool` is not a file in the folder" not in printed
        ):
            problems.append(
                f"an unbuilt Swift tool is not told its program is missing:\n{printed}"
            )

        status, version = tool("--version")
        version = version.strip()
        if status != 0 or version.count(".") != 2:
            problems.append(f"--version did not print a version:\n{version}")
        published = os.path.join(root, "published")
        status, printed = tool("init", published, *named, "--template", "swift")
        wanted = (
            '.package(url: "https://github.com/VitruvianSoftware/vitruvian-sdk", '
            f'from: "{version}")'
        )
        package = os.path.join(published, "Package.swift")
        text = ""
        if os.path.isfile(package):
            with open(package, encoding="utf-8") as handle:
                text = handle.read()
        if status != 0 or wanted not in text:
            problems.append(
                f"init without --sdk does not depend on the published SDK {version}:\n{printed}\n{text}"
            )

        # The kit templates. The Python kit one from this checkout, with
        # --sdk, which puts the kit in lib/ as pip would; the TypeScript one
        # as from npm, with the kit Bazel built put where `npm install` puts
        # it. Neither needs the network.
        kits = [
            ("python-kit", ["--sdk", PACKAGE], None, ["--via", sys.executable]),
            ("typescript", [], os.environ.get("VITRUVIAN_TOOL_KIT_TYPESCRIPT"), []),
        ]
        for template, extra, kit, via in kits:
            folder = os.path.join(root, template)
            status, printed = tool(
                "init", folder, *named, "--template", template, *extra
            )
            if status != 0:
                problems.append(
                    f"init did not write the {template} template:\n{printed}"
                )
                continue
            if kit:
                shutil.copytree(
                    kit,
                    os.path.join(
                        folder, "node_modules", "@vitruviansoftware", "tool-kit"
                    ),
                )
            status, printed = tool("validate", folder)
            if status != 0:
                problems.append(
                    f"validate does not pass the {template} template:\n{printed}"
                )
            said = io.StringIO()
            with contextlib.redirect_stdout(said):
                status = conformance.main([folder, *via, "--expect-refusal"])
            if status != 0:
                problems.append(
                    f"the {template} template does not pass conformance:\n{said.getvalue()}"
                )
            status, printed = tool(
                "run", folder, "--command", "hello", "--command", "count"
            )
            if (
                status != 0
                or "ran      count" not in printed
                or "run: OK" not in printed
            ):
                problems.append(f"the {template} template does not run:\n{printed}")

    for problem in problems:
        print(problem, file=sys.stderr)
    print("init: " + ("FAILED" if problems else "OK"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
