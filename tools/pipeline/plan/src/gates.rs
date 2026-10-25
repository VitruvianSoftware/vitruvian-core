// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//! The fast gates (docs-only, global impact), the persona/operation
//! classifier and the file-to-package resolver: gates.go, classifier.go and
//! packages.go. The regular expressions are spelled out as the prefix,
//! suffix and exact-name checks they amount to (Go's `$` is end of text).

use std::collections::BTreeSet;
use std::fs;

use unitfile::gocompat::path;

use crate::{Operation, Persona};

const DOCS_PREFIXES: &[&str] = &[
    "docs/",
    "gitops/",
    ".agents/agents/",
    ".agents/skills/",
    ".agents/rules/",
    "devx/docs/",
    "apps/cli/devx/docs/",
];
const DOCS_SUFFIXES: &[&str] = &[".md", ".png", ".jpg", ".jpeg", ".svg", ".txt"];
const DOCS_NAMES: &[&str] = &["catalog-info.yaml", "OWNERS", "CODEOWNERS"];

const GLOBAL_FILES: &[&str] = &[
    "MODULE.bazel",
    "MODULE.bazel.lock",
    ".bazelrc",
    ".bazelversion",
    "BUILD",
    "BUILD.bazel",
    "gazelle_python.yaml",
];

const INERT_TOOLS: &[&str] = &[
    "adb-connect/",
    "ci/",
    "cluster/",
    "conformance/",
    "copybara/",
    "deploy/",
    "doctor/",
    "format/",
    "gcp-secrets/",
    "gitops/",
    "license/",
    "lint/",
    "release/",
    "rotate-buildbuddy-key/",
    "saas-cli/",
    "scripts/",
    "sync-env-secrets/",
    "worktree/",
    "owners/",
    "boundaries/",
    "pipeline/",
];

fn is_docs_file(f: &str) -> bool {
    DOCS_PREFIXES.iter().any(|p| f.starts_with(p))
        || DOCS_SUFFIXES.iter().any(|s| f.ends_with(s))
        || DOCS_NAMES
            .iter()
            .any(|n| f == *n || f.ends_with(&format!("/{n}")))
}

/// Whether every file in the changeset is docs/gitops/markdown/inert
/// assets/metadata. An empty changeset is not.
pub fn is_docs_only(files: &[String]) -> bool {
    !files.is_empty() && files.iter().all(|f| is_docs_file(f))
}

fn is_inert_tool(f: &str) -> bool {
    let Some(rest) = f.strip_prefix("tools/") else {
        return false;
    };
    rest == "repin" || INERT_TOOLS.iter().any(|d| rest.starts_with(d))
}

/// Whether any file touches root toolchains or global build configs, and
/// why.
pub fn check_global_impact(files: &[String]) -> (bool, String) {
    for f in files {
        if GLOBAL_FILES.contains(&f.as_str()) {
            return (true, format!("root build/toolchain config changed: {f}"));
        }
        if f.starts_with("tools/") && !is_inert_tool(f) {
            return (true, format!("core toolchain directory changed: {f}"));
        }
    }
    (false, String::new())
}

const FRONTEND_PREFIXES: &[&str] = &[
    "packages/design-system/",
    "tabula/web/",
    "apps/suites/tabula/web/",
    "tabula/extension/",
    "apps/suites/tabula/extension/",
    "backstage/packages/app/",
    "apps/web/backstage/packages/app/",
];

const BACKEND_PREFIXES: &[&str] = &[
    "tabula/api/",
    "apps/suites/tabula/api/",
    "tabula/cli/",
    "apps/suites/tabula/cli/",
    "devx/",
    "apps/cli/devx/",
    "homelab/",
    "apps/cli/homelab/",
    "mcp-slack/",
    "apps/mcp/slack/",
    "oauth-user-inspector/",
    "apps/web/oauth-user-inspector/",
    "backstage/packages/backend/",
    "apps/web/backstage/packages/backend/",
];

const INFRA_PREFIXES: &[&str] = &[
    "infrastructure/",
    "packages/pulumi/",
    "pulumi/",
    "tools/pulumi/",
    "tools/cloud-bootstrap/",
];

/// Maps the changed files to a persona and an operation.
pub fn classify_persona_and_operation(
    files: &[String],
    is_docs_only: bool,
    is_global_impact: bool,
) -> (Persona, Operation) {
    if is_docs_only {
        return (Persona::DocsAuthor, Operation::DocsOnly);
    }
    if is_global_impact {
        return (Persona::PlatformAdmin, Operation::GlobalConfig);
    }
    let (mut frontend, mut backend, mut infra, mut migration, mut dep_update, mut platform) =
        (false, false, false, false, false, false);
    for f in files {
        let clean = f.strip_prefix("./").unwrap_or(f);
        let clean = clean.strip_prefix('/').unwrap_or(clean);
        let ext = path::ext(clean);
        if clean.contains("/migrations/")
            || clean.ends_with(".sql")
            || clean.contains("prisma/schema.prisma")
        {
            migration = true;
        }
        if matches!(
            clean,
            "pnpm-lock.yaml" | "go.mod" | "go.sum" | "requirements.txt" | "MODULE.bazel.lock"
        ) {
            dep_update = true;
        }
        if INFRA_PREFIXES.iter().any(|p| clean.starts_with(p))
            || clean.contains("/infra/")
            || ext == ".bu"
            || ext == ".tf"
        {
            infra = true;
        } else if FRONTEND_PREFIXES.iter().any(|p| clean.starts_with(p))
            || matches!(ext, ".tsx" | ".jsx" | ".css" | ".scss")
        {
            frontend = true;
        } else if clean.starts_with("tools/") || clean.starts_with(".github/") {
            platform = true;
        } else if BACKEND_PREFIXES.iter().any(|p| clean.starts_with(p))
            || matches!(ext, ".go" | ".py" | ".rs")
        {
            backend = true;
        }
    }
    let count = [frontend, backend, infra, platform]
        .iter()
        .filter(|b| **b)
        .count();
    let persona = if count > 1 {
        Persona::FullStackDev
    } else if frontend {
        Persona::FrontendDev
    } else if backend {
        Persona::BackendDev
    } else if infra {
        Persona::InfraEng
    } else if platform {
        Persona::PlatformAdmin
    } else {
        Persona::BackendDev
    };
    let operation = if migration {
        Operation::DatabaseMigration
    } else if dep_update {
        Operation::DepUpdate
    } else if count > 1 {
        Operation::MultiDiscipline
    } else if frontend {
        Operation::UiFeature
    } else if backend {
        Operation::BackendApi
    } else if infra {
        Operation::InfraProvision
    } else {
        Operation::BackendApi
    };
    (persona, operation)
}

fn file_exists(p: &str) -> bool {
    fs::metadata(p).map(|m| !m.is_dir()).unwrap_or(false)
}

/// Maps repository-relative changed files to their enclosing Bazel
/// packages ("//dir:all"), sorted.
pub fn resolve_packages(repo_root: &str, files: &[String]) -> Vec<String> {
    let mut set = BTreeSet::new();
    for rel in files {
        let clean = rel.strip_prefix("./").unwrap_or(rel);
        let clean = clean.strip_prefix('/').unwrap_or(clean);
        if clean.is_empty() {
            continue;
        }
        let mut dir = path::dir(clean);
        while dir != "." && dir != "/" && !dir.is_empty() {
            let build = path::join(&[repo_root, &dir, "BUILD"]);
            let build_bazel = path::join(&[repo_root, &dir, "BUILD.bazel"]);
            if file_exists(&build) || file_exists(&build_bazel) {
                set.insert(format!("//{dir}:all"));
                break;
            }
            let parent = path::dir(&dir);
            if parent == dir {
                break;
            }
            dir = parent;
        }
    }
    set.into_iter().collect()
}
