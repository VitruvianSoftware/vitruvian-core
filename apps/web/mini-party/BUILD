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

load("@npm//:defs.bzl", "npm_link_all_packages")
load("@npm//apps/web/mini-party:tsx/package_json.bzl", tsx = "bin")
load("@npm//apps/web/mini-party:typescript/package_json.bzl", typescript = "bin")
load("@npm//apps/web/mini-party:vite/package_json.bzl", vite = "bin")
load("@npm//apps/web/mini-party:vitest/package_json.bzl", vitest = "bin")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

package(default_visibility = ["//apps/web/mini-party:__subpackages__"])

npm_link_all_packages(name = "node_modules")

# The browser client, bundled by Vite into dist/.
vite.vite(
    name = "build",
    srcs = glob(["src/**"]) + [
        "index.html",
        "package.json",
        "tsconfig.json",
        "vite.config.ts",
        ":node_modules",
    ],
    args = ["build"],
    chdir = package_name(),
    out_dirs = ["dist"],
)

# Runs the game: the built client plus the multiplayer server, on $PORT (3000).
#   bazel run //apps/web/mini-party:serve
tsx.tsx_binary(
    name = "serve",
    args = ["server.ts"],
    chdir = package_name(),
    data = glob(["server/**"]) + [
        "package.json",
        "server.ts",
        ":build",
        ":node_modules",
    ],
    env = {"NODE_ENV": "production"},
)

# Type-checks the client, the server and the configs together.
typescript.tsc_test(
    name = "typecheck",
    args = [
        "--noEmit",
        "-p",
        "tsconfig.json",
    ],
    chdir = package_name(),
    data = glob([
        "src/**",
        "server/**",
    ]) + [
        "package.json",
        "server.ts",
        "tsconfig.json",
        "vite.config.ts",
        "vitest.config.ts",
        ":node_modules",
    ],
)

# Multiplayer room server: seating, the 4-player cap, seat reuse, relaying.
vitest.vitest_test(
    name = "server_test",
    args = ["run"],
    chdir = package_name(),
    data = glob(["server/**"]) + [
        "package.json",
        "vitest.config.ts",
        ":node_modules",
    ],
)

pipeline_unit(
    name = "mini-party",
    persona = "frontend",
    runner = "ubuntu-26.04",
    test_targets = [
        ":typecheck",
        ":server_test",
        ":build",
    ],
    tier = "L1",
    timeout_minutes = 15,
)
