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

"""A small repository, written into a temporary folder, for the tests.

It is made at run time and not kept as files: a `package.json`, `Cargo.toml`
or `release-please-config.json` checked in under testdata/ would be read as a
real one by this tool and by every other tool that looks for them.
"""

import json
import os
import textwrap

COPYBARA = """\
MONOREPO = "https://github.com/Example/core.git"
STANDALONE_SSH_PREFIX = "git@github.com:Example/"

COMPONENTS = [
    {
        "name": "sdk",
        "repo": "sdk-mirror",
        "subtree": "packages/sdk",
        "standalone_only": [],
    },
    {
        "name": "lib",
        "repo": "lib-mirror",
        "subtree": "packages/lib",
        "standalone_only": ["release-please-config.json"],
    },
    {
        # No "repo" and no "subtree": both are the name, as copy.bara.sky says.
        "name": "app",
        "standalone_only": [],
    },
]
"""

SDK_RELEASE = """\
name: release
on:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  detect:
    runs-on: ubuntu-latest
    steps:
      # The next job runs `npm publish`; this one only looks.
      - run: echo "looking"
  publish-npm-kit:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
    steps:
      - name: Publish
        working-directory: kits/ts
        run: npm publish --access public
  publish-pypi-kit:
    runs-on: ubuntu-latest
    environment:
      name: pypi
      url: https://pypi.org/project/example-kit/
    steps:
      - name: Publish
        run: uv publish --trusted-publishing always
  crates-publish:
    runs-on: ubuntu-latest
    steps:
      - name: Publish
        env:
          environment: not-this-one
        run: cargo publish
    environment: crates-io
"""

# The library's workflow publishes from a script, with deeper indentation.
LIB_RELEASE = """\
name: release
on:
    push:
        branches: [main]
jobs:
    release:
        runs-on: ubuntu-latest
        steps:
            - name: Publish what moved
              run: |
                  python3 - <<'PY'
                  import subprocess
                  subprocess.run(["npm", "publish", "--access", "public"], check=True)
                  PY
"""

APP_RELEASE = """\
name: release
on:
  push:
    branches: [main]
jobs:
  package:
    runs-on: ubuntu-latest
    steps:
      - run: npm run package
"""


def write(root, path, text):
    full = os.path.join(root, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w", encoding="utf-8") as handle:
        handle.write(textwrap.dedent(text) if text.startswith("\n") else text)


def node_package(root, path, name, version, private=False):
    """A package release-please releases as `node`, with its own config."""
    write(
        root,
        f"{path}/release-please-config.json",
        json.dumps({"release-type": "node", "packages": {path: {}}}),
    )
    write(root, f"{path}/.release-please-manifest.json", json.dumps({path: version}))
    manifest = {"name": name, "version": version}
    if private:
        manifest["private"] = True
    write(root, f"{path}/package.json", json.dumps(manifest))


def make(root):
    write(root, "tools/copybara/copy.bara.sky", COPYBARA)

    # One release-please package whose extra-files carry three kits.
    write(
        root,
        "packages/sdk/release-please-config.json",
        json.dumps(
            {
                "release-type": "simple",
                "packages": {
                    "packages/sdk": {
                        "extra-files": [
                            "Sources/Words.swift",
                            {
                                "type": "json",
                                "path": "kits/ts/package.json",
                                "jsonpath": "$.version",
                            },
                            {
                                "type": "toml",
                                "path": "kits/py/pyproject.toml",
                                "jsonpath": "$.project.version",
                            },
                            {
                                "type": "toml",
                                "path": "kits/rs/Cargo.toml",
                                "jsonpath": "$.package.version",
                            },
                            {
                                "type": "toml",
                                "path": "kits/internal/Cargo.toml",
                                "jsonpath": "$.package.version",
                            },
                            {
                                "type": "json",
                                "path": "samples/hello/package.json",
                                "jsonpath": "$.dependencies['@example/kit']",
                            },
                            {
                                "type": "toml",
                                "path": "samples/hello-rs/Cargo.toml",
                                "jsonpath": "$.dependencies['example-kit'].version",
                            },
                            {"type": "generic", "path": "go/version.go"},
                        ]
                    }
                },
            }
        ),
    )
    write(
        root,
        "packages/sdk/.release-please-manifest.json",
        json.dumps({"packages/sdk": "1.1.0"}),
    )
    write(
        root,
        "packages/sdk/kits/ts/package.json",
        json.dumps({"name": "@example/kit", "version": "1.1.0"}),
    )
    write(
        root,
        "packages/sdk/kits/py/pyproject.toml",
        '[project]\nname = "example-kit"\nversion = "1.1.0"\n',
    )
    write(
        root,
        "packages/sdk/kits/rs/Cargo.toml",
        '[package]\nname = "example-kit"\nversion = "1.1.0"\n',
    )
    write(
        root,
        "packages/sdk/kits/internal/Cargo.toml",
        '[package]\nname = "example-internal"\nversion = "1.1.0"\npublish = false\n',
    )
    write(
        root,
        "packages/sdk/samples/hello/package.json",
        json.dumps(
            {
                "name": "hello",
                "version": "0.0.1",
                "dependencies": {"@example/kit": "1.1.0"},
            }
        ),
    )
    write(
        root,
        "packages/sdk/samples/hello-rs/Cargo.toml",
        '[package]\nname = "hello-rs"\nversion = "0.0.1"\n',
    )
    write(root, "packages/sdk/.github/workflows/release.yml", SDK_RELEASE)
    write(root, "packages/sdk/.github/workflows/ci.yml", APP_RELEASE)

    # A library of node packages, one config each, published from a script.
    node_package(root, "packages/lib/ts/packages/a", "@example/a", "0.4.1")
    node_package(root, "packages/lib/ts/packages/b", "@example/b", "0.5.0")
    node_package(root, "packages/lib/ts/packages/priv", "@example/priv", "9.9.9", True)
    write(root, "packages/lib/.github/workflows/release.yml", LIB_RELEASE)

    # An app release-please releases as `node`, which no workflow publishes.
    node_package(root, "app", "some-app", "1.21.0")
    write(root, "app/.github/workflows/release.yml", APP_RELEASE)

    # A public package that no mirror carries.
    node_package(root, "apps/nomirror", "@example/nomirror", "0.1.0")

    # What a walk must not go into.
    node_package(root, "node_modules/dep", "@example/dep", "3.0.0")
    return root
