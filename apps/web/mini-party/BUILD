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
load("@npm//apps/web/mini-party:esbuild/package_json.bzl", esbuild = "bin")
load("@npm//apps/web/mini-party:tsx/package_json.bzl", tsx = "bin")
load("@npm//apps/web/mini-party:typescript/package_json.bzl", typescript = "bin")
load("@npm//apps/web/mini-party:vite/package_json.bzl", vite = "bin")
load("@npm//apps/web/mini-party:vitest/package_json.bzl", vitest = "bin")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
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

# The same client for GitHub Pages, built with --mode pages so it reads
# .env.pages (rooms server, analytics, Sentry), exactly as the mirror's
# .github/workflows/pages.yml builds it.
vite.vite(
    name = "build_static",
    srcs = glob(["src/**"]) + [
        ".env.pages",
        "index.html",
        "package.json",
        "tsconfig.json",
        "vite.config.ts",
        ":node_modules",
    ],
    args = [
        "build",
        "--mode",
        "pages",
    ],
    chdir = package_name(),
    env = {"OUT_DIR": "dist-static"},
    out_dirs = ["dist-static"],
)

sh_test(
    name = "static_build_test",
    srcs = ["scripts/static_build_test.sh"],
    args = [
        "$(rootpath :build)",
        "$(rootpath :build_static)",
    ],
    data = [
        ":build",
        ":build_static",
        ":server_bundle",
    ],
)

# The mirror's package.json gets concrete versions in place of `catalog:`;
# this keeps those in step with the root pnpm catalog.
sh_test(
    name = "mirror_catalog_test",
    srcs = ["scripts/mirror_catalog_test.sh"],
    args = [
        "$(rootpath package.json)",
        "$(rootpath //:pnpm-workspace.yaml)",
        "$(rootpath //tools/copybara:copy.bara.sky)",
    ],
    data = [
        "package.json",
        "//:pnpm-workspace.yaml",
        "//tools/copybara:copy.bara.sky",
    ],
)

# The rooms-only server as one ES module, exactly as the container image runs
# it (the Dockerfile runs the same build:server script).
esbuild.esbuild(
    name = "server_bundle",
    srcs = glob(["server/**"]) + [
        "package.json",
        "server.ts",
        ":node_modules",
    ],
    outs = ["dist-server/server.mjs"],
    args = [
        "server.ts",
        "--bundle",
        "--platform=node",
        "--format=esm",
        "--packages=external",
        "--outfile=dist-server/server.mjs",
    ],
    chdir = package_name(),
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

# Multiplayer room server (seating, the 4-player cap, seat reuse, holding a
# dropped player's seat, relaying, the internet-facing limits), the client's
# rejoin after a dropped connection, and the client's share-link parsing.
vitest.vitest_test(
    name = "server_test",
    args = ["run"],
    chdir = package_name(),
    data = glob([
        "server/**",
        "src/room.ts",
        "src/room.test.ts",
        "src/kit/logic.ts",
        "src/kit/logic.test.ts",
        "src/analytics.ts",
        "src/analytics.test.ts",
        "src/features.ts",
        "src/services/socketService.ts",
        "src/services/socketService.test.ts",
    ]) + [
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
        ":static_build_test",
        ":mirror_catalog_test",
        ":build",
        ":build_static",
    ],
    tier = "L1",
    timeout_minutes = 15,
)
