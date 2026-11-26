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

load("@aspect_rules_jest//jest:defs.bzl", "jest_test")
load("@aspect_rules_js//npm:defs.bzl", "npm_package")
load("@npm//:defs.bzl", "npm_link_all_packages")
load("//tools/pipeline:defs.bzl", "pipeline_unit")

# Inter-app boundary (#82): default targets to backstage-internal visibility.
package(default_visibility = ["//apps/web/backstage:__subpackages__"])

npm_link_all_packages(name = "node_modules")

# Minimal packaging target so aspect_rules_js can link this pnpm workspace
# package into the virtual store.
npm_package(
    name = "pkg",
    srcs = ["package.json"] + glob(
        [
            "src/**",
            "tsconfig.json",
            "config.d.ts",
            "config.schema.json",
        ],
        allow_empty = True,
    ),
    visibility = ["//visibility:public"],
)

# Every src/**/*.test.ts suite, run with the package's own jest.config.cjs
# (plain ts-jest; no ts_project, so there are no compiled .js siblings for
# jest 30's symlink-resolving resolver to wander into).
jest_test(
    name = "unit_tests",
    size = "medium",
    config = "jest.config.cjs",
    data = glob(["src/**"]) + [
        "jest.config.cjs",
        "package.json",
        "tsconfig.json",
        "tsconfig.test.json",
        # Repo files the drift-guard suites read through REPO_ROOT. Each is a
        # js_library in its own package: rules_js copies data to bin only for
        # this package, so a bare source file from elsewhere is refused.
        "//:backstage_backend_test_data",
        "//apps/cli/vitruvian-devx:catalog_info",
        "//apps/cli/vitruvian-homelab:catalog_info",
        "//apps/desktop/vitruvian-code:catalog_info",
        "//apps/mcp/vitruvian-slack-mcp:catalog_info",
        "//apps/suites/vitruvian-tabs:catalog_info",
        "//apps/web/backstage:backend_test_data",
        "//apps/web/backstage/packages/app:package_json",
        "//apps/web/oauth-user-inspector:catalog_info",
        "//gitops/argocd/platform/backstage:backstage_backend_test_data",
        "//gitops/argocd/platform/grafana:applicationset",
        "//gitops/argocd/platform/grafana-dashboards:backstage_backend_test_data",
        "//infrastructure/pulumi/foundation/gcp-bootstrap:production_stack_config",
        "//tools:initializer_config",
        ":node_modules/@backstage/backend-defaults",
        ":node_modules/@backstage/backend-plugin-api",
        ":node_modules/@backstage/catalog-client",
        ":node_modules/@backstage/catalog-model",
        ":node_modules/@backstage/integration",
        ":node_modules/@backstage/plugin-app-backend",
        ":node_modules/@backstage/plugin-auth-backend",
        ":node_modules/@backstage/plugin-auth-backend-module-github-provider",
        ":node_modules/@backstage/plugin-auth-node",
        ":node_modules/@backstage/plugin-catalog-backend",
        ":node_modules/@backstage/plugin-catalog-backend-module-github",
        ":node_modules/@backstage/plugin-catalog-backend-module-github-org",
        ":node_modules/@backstage/plugin-catalog-backend-module-scaffolder-entity-model",
        ":node_modules/@backstage/plugin-kubernetes-backend",
        ":node_modules/@backstage/plugin-mcp-actions-backend",
        ":node_modules/@backstage/plugin-permission-backend",
        ":node_modules/@backstage/plugin-permission-common",
        ":node_modules/@backstage/plugin-permission-node",
        ":node_modules/@backstage/plugin-proxy-backend",
        ":node_modules/@backstage/plugin-scaffolder-backend",
        ":node_modules/@backstage/plugin-scaffolder-backend-module-github",
        ":node_modules/@backstage/plugin-scaffolder-node",
        ":node_modules/@backstage/plugin-search-backend",
        ":node_modules/@backstage/plugin-search-backend-module-catalog",
        ":node_modules/@backstage/plugin-search-backend-module-techdocs",
        ":node_modules/@backstage/plugin-techdocs-backend",
        ":node_modules/@pagerduty/backstage-plugin-backend",
        ":node_modules/@sentry/node",
        ":node_modules/@types/jest",
        ":node_modules/@types/js-yaml",
        ":node_modules/@types/node",
        ":node_modules/better-sqlite3",
        ":node_modules/express-promise-router",
        ":node_modules/google-auth-library",
        ":node_modules/jest",
        ":node_modules/jest-cli",
        ":node_modules/jest-environment-node",
        ":node_modules/jest-junit",
        ":node_modules/js-yaml",
        ":node_modules/pg",
        ":node_modules/ts-jest",
        ":node_modules/typescript",
    ],
    node_modules = ":node_modules",
    # Node 22.12+ require(esm) makes jest's generated config throw
    # ERR_REQUIRE_ASYNC_MODULE; force the import() fallback.
    node_options = ["--no-experimental-require-module"],
)

pipeline_unit(
    name = "backstage-backend",
    persona = "backend",
    runner = "ubuntu-26.04",
    test_targets = [
        ":pkg",
        ":unit_tests",
    ],
    tier = "L1",
    timeout_minutes = 20,
)
