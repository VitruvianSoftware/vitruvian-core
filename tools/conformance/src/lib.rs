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

//! Rust port of `tools/conformance/check.sh`: the monorepo version-conformance
//! checker. Produces byte-for-byte identical output, exit codes and environment
//! variable behaviour as the bash original, but runs in a fraction of the time
//! by doing file walks, pattern matching, YAML/JSON/Go/Starlark scraping, and
//! reporting natively instead of spawning hundreds of subprocesses.

pub mod canonical;
pub mod checks;
pub mod discover;
pub mod emit;
pub mod registry;

use std::cell::{Cell, RefCell};
use std::process::Command;

use discover::FileCache;
use emit::{Colors, RowBuffers};
use registry::Registry;

pub struct Context {
    pub root: String,
    pub start_pwd: String,
    pub today: String,
    pub registry: Registry,
    pub files: FileCache,
    pub catalog_names: Vec<String>,
    pub colors: Colors,
    pub rows: RowBuffers,
    pub workflows_dir: String,
    pub workspace_yaml: String,
    pub catalog_exempt: Vec<String>,
    pub ok_count: Cell<u32>,
    pub fail_count: Cell<u32>,
    pub pin_count: Cell<u32>,
    pub warn_count: Cell<u32>,
    pub overall_fail: Cell<bool>,
    fatal: RefCell<Option<String>>,
}

impl Context {
    pub fn new() -> Result<Self, String> {
        let root = std::env::var("BUILD_WORKSPACE_DIRECTORY").unwrap_or_else(|_| {
            std::env::current_dir()
                .map(|p| p.to_string_lossy().to_string())
                .unwrap_or_else(|_| ".".to_string())
        });
        let start_pwd = std::env::current_dir()
            .map(|p| p.to_string_lossy().to_string())
            .unwrap_or_else(|_| ".".to_string());

        let today = {
            let out = Command::new("date")
                .arg("+%Y-%m-%d")
                .output()
                .map_err(|e| format!("failed to run date: {e}"))?;
            String::from_utf8_lossy(&out.stdout).trim().to_string()
        };

        let registry_path = format!("{root}/tools/conformance/version-pins.tsv");
        let registry = Registry::parse(&registry_path)?;

        let colors = Colors::detect();

        let files = FileCache::new(&root);

        let workspace_yaml = format!("{root}/pnpm-workspace.yaml");
        let catalog_names = canonical::catalog_names(&workspace_yaml);

        let catalog_exempt: Vec<String> = [
            "apps/mcp/slack",
            "apps/web/oauth-user-inspector",
            "packages/pulumi/examples/go-foundation/policy-library",
            "packages/pulumi/examples/ts-foundation",
            "packages/vitruvian-sdk",
        ]
        .iter()
        .map(|s| s.to_string())
        .collect();

        let workflows_dir = format!("{root}/.github/workflows");

        Ok(Context {
            root,
            start_pwd,
            today,
            registry,
            files,
            catalog_names,
            colors,
            rows: RowBuffers::new(),
            workflows_dir,
            workspace_yaml,
            catalog_exempt,
            ok_count: Cell::new(0),
            fail_count: Cell::new(0),
            pin_count: Cell::new(0),
            warn_count: Cell::new(0),
            overall_fail: Cell::new(false),
            fatal: RefCell::new(None),
        })
    }

    pub fn inc_ok(&self) {
        self.ok_count.set(self.ok_count.get() + 1);
    }

    pub fn inc_fail(&self) {
        self.fail_count.set(self.fail_count.get() + 1);
    }

    pub fn inc_pin(&self) {
        self.pin_count.set(self.pin_count.get() + 1);
    }

    pub fn inc_warn(&self) {
        self.warn_count.set(self.warn_count.get() + 1);
    }

    pub fn set_overall_fail(&self) {
        self.overall_fail.set(true);
    }

    pub fn die(&self, msg: &str) {
        eprintln!(
            "{}\u{2717} conformance{} \u{2014} {}",
            self.colors.red, self.colors.reset, msg
        );
        *self.fatal.borrow_mut() = Some(msg.to_string());
    }

    pub fn is_dead(&self) -> bool {
        self.fatal.borrow().is_some()
    }

    pub fn emit_ok(&self, group: &str, file: &str, found: &str, canon: &str, note: &str) {
        self.rows.emit(
            group,
            emit::GLYPH_OK,
            &self.colors.green,
            file,
            found,
            canon,
            note,
            "",
        );
        self.inc_ok();
    }

    pub fn emit_ok_uncounted(&self, group: &str, file: &str, found: &str, canon: &str, note: &str) {
        self.rows.emit(
            group,
            emit::GLYPH_OK,
            &self.colors.green,
            file,
            found,
            canon,
            note,
            "",
        );
    }

    pub fn emit_fail(
        &self,
        group: &str,
        file: &str,
        found: &str,
        canon: &str,
        note: &str,
        fix: &str,
    ) {
        self.rows.emit(
            group,
            emit::GLYPH_FAIL,
            &self.colors.red,
            file,
            found,
            canon,
            note,
            fix,
        );
        self.set_overall_fail();
        self.inc_fail();
    }

    pub fn emit_pin(&self, group: &str, file: &str, found: &str, canon: &str, note: &str) {
        self.rows.emit(
            group,
            emit::GLYPH_PIN,
            &self.colors.yellow,
            file,
            found,
            canon,
            note,
            "",
        );
        self.inc_pin();
    }

    pub fn emit_warn(&self, group: &str, file: &str, found: &str, canon: &str, note: &str) {
        self.rows.emit(
            group,
            emit::GLYPH_WARN,
            &self.colors.yellow,
            file,
            found,
            canon,
            note,
            "",
        );
        self.inc_warn();
    }

    pub fn rel(&self, path: &str) -> String {
        discover::rel(&self.root, path)
    }

    pub fn run(&self) -> i32 {
        checks::run_all(self);

        if self.is_dead() {
            return 2;
        }

        emit::print_banner(
            &self.colors,
            &canonical::canonical_go(&self.root).unwrap_or_default(),
            &canonical::canonical_node(&self.root).unwrap_or_default(),
            &canonical::canonical_pnpm(&self.root).unwrap_or_default(),
        );

        let group_order: &[(&str, &str)] = &[
            ("GO", "Go (go.mod → go.work)"),
            ("NODE", "Node (Dockerfile FROM node → .nvmrc major)"),
            ("PNPM", "pnpm (package.json packageManager → root)"),
            ("CATALOG", "Catalog (package.json → pnpm-workspace.yaml catalog)"),
            ("VIS", "App visibility firewall (#82: app-scoped defaults + public allowlist)"),
            ("META", "App metadata catalog (#500: catalog-info.yaml ↔ CODEOWNERS)"),
            ("TECHDOCS", "TechDocs documentation parity (catalog-info.yaml techdocs-ref → valid mkdocs.yml)"),
            ("OWNERS", "OWNERS governance (per-directory OWNERS → .github/CODEOWNERS)"),
            ("ROOT", "Root directory taxonomy (strict 4-layer monorepo boundary)"),
            ("MERGEQ", "Merge-queue required checks (repo-config → workflow merge_group jobs)"),
            ("CONCUR", "Postsubmit concurrency (main-gating lanes must key non-PR runs per commit)"),
            ("TIMEOUT", "Job timeouts (#209: every job bounded — no 6h default-timeout runners)"),
            ("SWEEP", "Full-sweep backstop (affected-scoped lanes → scheduled //... sweep)"),
            ("CACHESAVE", "Actions cache saves (only GitHub-hosted jobs on main save; queue/PR refs and self-hosted runners restore only)"),
            ("LABELS", "Workflow Bazel labels (every //pkg:target a workflow or action runs resolves)"),
            ("IAC", "IaC destructive-import guard (zitadel-apps must create, never import)"),
            ("PULUMI", "Pulumi program identity (unique project names · customDomain under its zone)"),
            ("COPYBARA", "Copybara infra-leak guard (<app>/infra/ is monorepo-only, never mirrored)"),
            ("RELEASE", "Release-unit guard (co-located <app>/infra/ must not bump the app version)"),
            ("LOCALPATH", "Leaked local-path guard (no committed file may embed a machine path)"),
            ("GATE", "CI gate guard (deploy + test gates must share one global-impact list)"),
            ("DURABLE", "Deploy durable-base guard (#1351: coalescing deploy lanes must not diff from github.event.before directly)"),
            ("DELIVERY", "Delivery orchestrator (unique units · resolvable run targets · side-effect firewall · §6.1 kill switch)"),
            ("PREVIEW", "Ephemeral preview governance (auto-teardown on PR close · hourly ghost reaper · non-cancellable)"),
            ("LABHOST", "Lab hostnames (every published *.lab.ipv1337.dev name has a Gateway HTTPS listener)"),
            ("CHECKOUT", "Checkout credentials firewall (#1040: persist-credentials: false on read-only checkouts)"),
            ("DEPENDABOT_ACTIONS", "Dependabot actions coverage (#814: exported mirror workflows in dependabot.yml)"),
            ("ACTION_PINS", "GitHub Actions SHA pins (#814: third-party actions pinned to commit SHA)"),
            ("GITLEAKS", "Secret-scan allowlist (every .gitleaks.toml path exemption still matches a file)"),
            ("GUARDREVIEW", "agent-guard review paths (every path that needs James's approval still names a file)"),
            ("OCIBASE", "Container base images (no oci.pull from Docker Hub, which rate-limits shared runners)"),
            ("PROMGRAPH", "Backstage Prometheus graphs (every prometheus.io/rule names a recording rule)"),
            ("PROMALERT", "Backstage Prometheus alerts (each component lists only its own namespace's alerts)"),
            ("STANDALONE_DEPS", "Standalone workspace: deps (CATALOG_EXEMPT packages must not use workspace: — breaks Docker build)"),
            ("RENOVATE", "Renovate cadence (config must carry no schedule window — the workflow cron is the only control)"),
            ("CRDOWN", "Chart-owned CRDs (turning a chart's CRD install off lets Argo CD prune them, deleting every object)"),
            ("PROJKIND", "AppProject kinds (every synced manifest's kind is in its app's AppProject allowlist)"),
            ("NAMING", "Monorepo naming conventions (tools/lint-naming → docs/standards/naming-conventions.md)"),
            ("PNPM_PIN", "pnpm build pin (Dockerfile → a reachable pnpm version)"),
            ("CAT_ADVISORY", "Advisory — shared deps not in the catalog (drift candidates)"),
        ];

        for (key, title) in group_order {
            let rows = self.rows.get(key);
            emit::print_group(&self.colors, title, &rows);
        }

        emit::print_summary(
            &self.colors,
            self.ok_count.get(),
            self.pin_count.get(),
            self.warn_count.get(),
            self.fail_count.get(),
            self.registry.active_count(),
            self.overall_fail.get(),
        );

        if self.overall_fail.get() {
            1
        } else {
            0
        }
    }
}
