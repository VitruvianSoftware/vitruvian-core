#!/usr/bin/env python3
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
"""check-version-maps, the Rust port, against check-version-maps.sh: same
exit code, stdout, stderr, and the same copy.bara.sky left behind (--fix),
on every case below.

    bazel test //tools/copybara:check_version_maps_rs_parity_test
"""

import json
import os
import shutil
import sys

sys.path.insert(
    0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shell-compat")
)
from parity_harness import Case, Harness, need_env, write  # noqa: E402

# The script runs python3 from PATH; the harness PATH is the system one plus
# wherever this test found python3.
_PY = shutil.which("python3") or sys.executable
BASE_PATH = os.path.dirname(_PY) + ":/usr/bin:/bin:/usr/sbin:/sbin"

# A crash (Python's traceback, the port's one line) is compared on its exit
# code and on what it printed to stdout; the message itself is free.
CRASH = [(rb"(?s)\A.*\Z", b"<crash>")]


def pkg(root, name, version, base="ts"):
    body = {"name": "@vitruviansoftware/foundation-" + name}
    if version is not None:
        body["version"] = version
    write("%s/%s/%s/package.json" % (root, base, name), json.dumps(body) + "\n")


def gomod(root, name, version, extra=None):
    d = {"pulumi/library/go/pkg/" + name: version}
    if extra:
        d.update(extra)
    write("%s/go/%s/.release-please-manifest.json" % (root, name), json.dumps(d))


def example(root, deps, rel="example/package.json", field="dependencies", raw=None):
    if raw is not None:
        write("%s/%s" % (root, rel), raw)
        return
    declared = {"@vitruviansoftware/foundation-" + d: spec for d, spec in deps.items()}
    write("%s/%s" % (root, rel), json.dumps({"name": "example", field: declared}))


def sky_text(ts, go):
    return (
        "_TS_EXAMPLE_LIB_VERSIONS = {\n%s\n}\n_GO_EXAMPLE_LIB_VERSIONS = {\n%s\n}\n"
        % (
            ts,
            go,
        )
    )


TS_OK = '    "bootstrap": "0.4.0",\n    "network": "0.5.0",'
GO_OK = '    "bootstrap/v2": "2.1.4",\n    "iam": "0.6.2",'


def base_tree(root):
    pkg(root, "bootstrap", "0.4.0")
    pkg(root, "network", "0.5.0")
    gomod(root, "bootstrap", "2.1.4")
    gomod(root, "iam", "0.6.2")
    example(root, {"bootstrap": "workspace:*", "network": "workspace:*"})


def tree(sky=None, extra=None):
    def setup(root):
        base_tree(root)
        if extra:
            extra(root)
        write(
            root + "/copy.bara.sky", sky if sky is not None else sky_text(TS_OK, GO_OK)
        )

    return setup


ENV = {
    "SKY": "{root}/copy.bara.sky",
    "TS_ROOT": "{root}/ts",
    "GO_ROOT": "{root}/go",
    "TS_EXAMPLE": "{root}/example",
    "BUILD_WORKSPACE_DIRECTORY": "{root}",
}


def case(name, setup, args=None, env=None, **kw):
    e = dict(ENV)
    e.update(env or {})
    # macOS's /usr/bin/python3 shim caches under $HOME/Library; the port
    # runs no python.
    return Case(
        name=name,
        args=args or [],
        env=e,
        setup=setup,
        ignore=[r"home/Library(/|$)"],
        **kw,
    )


def cases():
    yield case("in sync", tree())
    yield case(
        "ts drift",
        tree(sky_text('    "bootstrap": "0.2.1",\n    "network": "0.5.0",', GO_OK)),
    )
    yield case(
        "go drift through a /vN key",
        tree(sky_text(TS_OK, '    "bootstrap/v2": "2.1.2",\n    "iam": "0.6.2",')),
    )
    yield case(
        "a missing entry the example uses",
        tree(sky_text('    "bootstrap": "0.4.0",', GO_OK)),
    )
    yield case(
        "a package that does not exist and a module with no manifest",
        tree(
            sky_text(
                TS_OK + '\n    "ghost": "1.0.0",',
                GO_OK + '\n    "nowhere/v3": "3.0.0",',
            )
        ),
    )
    yield case("unparseable file", tree("nothing here\n"))
    yield case(
        "ts map without the go map",
        tree("_TS_EXAMPLE_LIB_VERSIONS = {\n" + TS_OK + "\n}\n"),
    )
    yield case(
        "go map unclosed",
        tree(sky_text(TS_OK, GO_OK).replace("\n}\n", "\n }\n", 2)[:-2]),
    )
    yield case(
        "an empty go map",
        tree(sky_text(TS_OK, "")),
    )
    yield case(
        "a name used before the map is defined",
        tree("x = _TS_EXAMPLE_LIB_VERSIONS.keys()\n" + sky_text(TS_OK, GO_OK)),
    )
    yield case(
        "repeated keys: first position, last value",
        tree(
            sky_text(
                '    "network": "0.0.1",\n    "bootstrap": "0.4.0",\n    "network": "0.5.0",',
                GO_OK,
            )
        ),
    )
    yield case(
        "odd spacing and pairs across lines",
        tree(
            sky_text(
                '    "bootstrap"\t:\t"0.4.0", "network"\n     :  "0.5.0"',
                '"bootstrap/v2":"2.1.4","iam"   :    "0.6.2"',
            )
        ),
    )
    yield case(
        "an empty key or value is no pair",
        tree(sky_text(TS_OK + '\n    "": "1",\n    "x": "",', GO_OK)),
    )

    def odd_versions(root):
        pkg(root, "num", 12)
        pkg(root, "flt", 1.5)
        pkg(root, "big", 1e20)
        pkg(root, "nil", None)
        pkg(root, "lst", [1, "a", None, True])
        pkg(root, "obj", {"b": 1, "a": "it's"})
        pkg(root, "boo", False)
        pkg(root, "uni", "é")

    yield case(
        "versions that are not strings",
        tree(
            sky_text(
                TS_OK
                + '\n    "num": "12",\n    "flt": "1.5",\n    "big": "1",\n    "nil": "0",'
                '\n    "lst": "1",\n    "obj": "1",\n    "boo": "0",\n    "uni": "e",',
                GO_OK,
            ),
            odd_versions,
        ),
    )
    yield case(
        "--fix leaves non-string and missing versions as Python does",
        tree(
            sky_text(
                TS_OK
                + '\n    "num": "1",\n    "flt": "1",\n    "nil": "0",\n    "boo": "0",\n    "lst": "1",',
                GO_OK,
            ),
            odd_versions,
        ),
        args=["--fix"],
    )

    def go_multi(root):
        gomod(root, "iam", "0.6.2", extra={"z-other": "9.9.9", "a-other": "1.1.1"})

    yield case("a manifest's FIRST value counts", tree(None, go_multi))

    def go_dup(root):
        write(
            root + "/go/iam/.release-please-manifest.json",
            '{"x": "0.0.1", "y": "5", "x": "0.6.2"}',
        )

    yield case("a repeated manifest key keeps its place", tree(None, go_dup))

    def example_variants(root):
        example(
            root,
            {"extra": "workspace:^"},
            rel="example/apps/a/package.json",
            field="devDependencies",
        )
        example(
            root, {"ghost1": "workspace:*"}, rel="example/node_modules/x/package.json"
        )
        example(root, {"ghost2": "workspace:*"}, rel="example/.hidden/package.json")
        example(root, {"ghost3": "workspace:*"}, rel="example/a/.cache/b/package.json")
        example(
            root, {"versioned": "^1.0.0", "numeric": 3}, rel="example/b/package.json"
        )
        example(
            root,
            {},
            rel="example/c/package.json",
            raw='{"dependencies": null, "devDependencies": []}',
        )
        example(root, {}, rel="example/d/package.json", raw='{"name": "no deps"}')
        os.makedirs(root + "/elsewhere/deep", exist_ok=True)
        example(root, {"linked": "workspace:*"}, rel="elsewhere/deep/package.json")
        os.symlink(root + "/elsewhere", root + "/example/link")

    yield case("what the example glob sees", tree(None, example_variants))

    def example_in_node_modules(root):
        os.makedirs(root + "/x/node_modules")
        os.rename(root + "/example", root + "/x/node_modules/example")

    yield case(
        "an example path holding node_modules is skipped whole",
        tree(sky_text('    "bootstrap": "0.4.0",', GO_OK), example_in_node_modules),
        env={"TS_EXAMPLE": "{root}/x/node_modules/example"},
    )
    yield case(
        "no example directory",
        tree(sky_text('    "bootstrap": "0.4.0",', GO_OK)),
        env={"TS_EXAMPLE": "{root}/missing"},
    )

    def unicode_tree(root):
        pkg(root, "ünï", "1.0.0")

    yield case(
        "non-ASCII keys pad by character",
        tree(sky_text(TS_OK + '\n    "ünï": "0.9.0",', GO_OK), unicode_tree),
    )
    yield case(
        "an absolute key replaces the root",
        tree(sky_text(TS_OK + '\n    "/nonexistent-abs": "1",', GO_OK)),
    )
    yield case(
        "a key with a newline before /vN",
        tree(sky_text(TS_OK, GO_OK + '\n    "bootstrap/v2\n": "2.1.4",')),
    )

    fix_sky = (
        "# header\n_TS_EXAMPLE_LIB_VERSIONS = {\n"
        '    "bootstrap": "0.2.1",  # keep this comment\n'
        '    "network"  :  "0.5.0",\n'
        '    "ghost": "1.0.0",\n'
        "}\n\n# between\n_GO_EXAMPLE_LIB_VERSIONS = {\n"
        '    "bootstrap/v2":"2.0.0",\n'
        '    "iam": "0.6.2",\n'
        "}\n# trailer\n"
    )
    yield case("--fix rewrites only stale entries", tree(fix_sky), args=["--fix"])
    yield case("--fix twice", tree(fix_sky), args=["--fix", "--fix"])
    yield case(
        "--fix with only a missing entry still rewrites",
        tree(sky_text('    "bootstrap": "0.4.0",', GO_OK)),
        args=["--fix"],
    )
    yield case("--fix on a clean map just checks", tree(), args=["--fix"])
    yield case(
        "--fix on CRLF text writes LF",
        tree(fix_sky.replace("\n", "\r\n")),
        args=["--fix"],
    )
    yield case(
        "CRLF text is read as LF", tree(sky_text(TS_OK, GO_OK).replace("\n", "\r\n"))
    )
    yield case("an empty argument is ignored", tree(), args=[""])
    yield case("an unknown argument", tree(), args=["--fix", "--check"])
    yield case("an unknown argument before --fix", tree(), args=["-x", "--fix"])
    yield case("no copy.bara.sky", tree(), env={"SKY": "{root}/nope.sky"})
    yield case(
        "the workspace does not exist",
        tree(),
        env={"BUILD_WORKSPACE_DIRECTORY": "{root}/gone"},
    )

    def defaults(root):
        base_tree(root)
        for src, dst in (
            ("ts", "packages/pulumi/library/ts/packages"),
            ("go", "packages/pulumi/library/go/pkg"),
            ("example", "packages/pulumi/examples/ts-foundation"),
        ):
            os.makedirs(os.path.dirname(os.path.join(root, dst)), exist_ok=True)
            os.rename(os.path.join(root, src), os.path.join(root, dst))
        write(
            root + "/tools/copybara/copy.bara.sky",
            sky_text(TS_OK, '    "iam": "0.6.1",'),
        )

    yield case(
        "default paths, workspace from the current directory",
        defaults,
        env={
            "SKY": None,
            "TS_ROOT": None,
            "GO_ROOT": None,
            "TS_EXAMPLE": None,
            "BUILD_WORKSPACE_DIRECTORY": None,
        },
    )
    yield case(
        "empty overrides fall back to the defaults",
        defaults,
        env={
            "SKY": "",
            "TS_ROOT": "",
            "GO_ROOT": "",
            "TS_EXAMPLE": "",
            "BUILD_WORKSPACE_DIRECTORY": "{root}",
        },
    )

    def broken_pkg(root):
        write(root + "/ts/network/package.json", "{not json")

    yield case(
        "a broken package.json stops the run", tree(None, broken_pkg), normalise=CRASH
    )

    def list_manifest(root):
        write(root + "/go/iam/.release-please-manifest.json", '["0.6.2"]')

    yield case(
        "a manifest that is a list stops the run",
        tree(None, list_manifest),
        normalise=CRASH,
    )

    def empty_manifest(root):
        write(root + "/go/iam/.release-please-manifest.json", "{}")

    yield case(
        "an empty manifest stops the run", tree(None, empty_manifest), normalise=CRASH
    )

    def bad_deps(root):
        example(root, {}, rel="example/z/package.json", raw='{"dependencies": ["x"]}')

    yield case(
        "dependencies that are a list stop the run",
        tree(None, bad_deps),
        normalise=CRASH,
    )


def main():
    h = Harness(
        "check-version-maps parity",
        need_env("CHECK_VERSION_MAPS_SH"),
        need_env("CHECK_VERSION_MAPS_RS"),
        base_path=BASE_PATH,
    )
    for c in cases():
        h.check(c)
    return h.finish()


if __name__ == "__main__":
    sys.exit(main())
