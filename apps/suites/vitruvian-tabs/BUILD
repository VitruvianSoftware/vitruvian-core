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

# vitruvian-tabs is a JS/TS app suite with hand-authored BUILD files under its subdirs;
# the root //:BUILD keeps gazelle out of this subtree (gazelle:exclude vitruvian-tabs).
# This package-root BUILD hosts only the developer-environment check target.
# gazelle:ignore

load("@aspect_rules_js//js:defs.bzl", "js_library")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//tools/doctor:defs.bzl", "doctor")

# Inter-app boundary (#82): targets in this package default to vitruvian-tabs-internal
# visibility so other top-level apps can't depend on vitruvian-tabs internals -- the
# same firewall the other five app roots already declare. The subpackages
# (api/cli/extension/shared/web) each carry their own matching default.
package(default_visibility = ["//apps/suites/vitruvian-tabs:__subpackages__"])

# Shared jest resolver (jest 30 + rules_js symlink fix) consumed by every
# vitruvian-tabs jest_test via `resolver: "<rootDir>/../jest-resolver.cjs"`. Wrapped in
# a js_library (rules_jest requires jest_test data to be same-package or a
# js_library dep) and staged at its package-relative path vitruvian-tabs/jest-resolver.cjs.
js_library(
    name = "jest_resolver",
    srcs = ["jest-resolver.cjs"],
    visibility = ["//apps/suites/vitruvian-tabs:__subpackages__"],
)

# Developer-environment check: `bazel run //apps/suites/vitruvian-tabs:doctor`.
doctor(
    name = "doctor",
    label = "vitruvian-tabs",
    optional = [
        "docker",
        "gcloud",
    ],
    required = [
        "bazel",
        "node",
        "pnpm",
        "git",
    ],
)

sh_test(
    name = "agent_docs_test",
    size = "small",
    srcs = ["//tools/conformance:skill_docs_check.sh"],
    args = [
        "--root",
        "apps/suites/vitruvian-tabs",
        "apps/suites/vitruvian-tabs/.agent/rules/browser-subagent.md",
        "apps/suites/vitruvian-tabs/.agent/rules/standard-operating-procedure.md",
        "apps/suites/vitruvian-tabs/.agent/skills/README.md",
        "apps/suites/vitruvian-tabs/.agent/skills/backend-api-developer/SKILL.md",
        "apps/suites/vitruvian-tabs/.agent/skills/devops-cli-developer/SKILL.md",
        "apps/suites/vitruvian-tabs/.agent/skills/frontend-extension-developer/SKILL.md",
        "apps/suites/vitruvian-tabs/.agent/skills/infrastructure-engineer/SKILL.md",
        "apps/suites/vitruvian-tabs/.agent/skills/qa-engineer/SKILL.md",
        "apps/suites/vitruvian-tabs/.agent/skills/security-analyst/SKILL.md",
        "apps/suites/vitruvian-tabs/.agent/skills/technical-writer/SKILL.md",
        "apps/suites/vitruvian-tabs/.agent/workflows/browser-subagent-qa.md",
        "apps/suites/vitruvian-tabs/.agent/workflows/commit-readiness.md",
    ],
    data = [
        "AGENTS.md",
        "CONTRIBUTING.md",
        "README.md",
        "SECURITY.md",
        "infra/README.md",
        "mkdocs.yml",
        "//apps/suites/vitruvian-tabs/api:docs_files",
        "//apps/suites/vitruvian-tabs/cli:docs_files",
        "//apps/suites/vitruvian-tabs/extension:docs_files",
        "//apps/suites/vitruvian-tabs/infra/app:docs_files",
        "//apps/suites/vitruvian-tabs/infra/data:docs_files",
        "//apps/suites/vitruvian-tabs/infra/web:docs_files",
    ] + glob([
        ".agent/**/*.md",
        "docs/**/*.md",
    ]),
)
