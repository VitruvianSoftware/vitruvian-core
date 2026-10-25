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

//! OWNERS discovery, inheritance, CODEOWNERS compilation and the coverage
//! audit, as the Go tool's engine.go and coverage.go.

use crate::gostr;
use crate::schema::{parse_config, Config};
use crate::validate::validate_config;
use std::collections::BTreeMap;
use std::os::unix::ffi::OsStrExt;

pub struct OwnersNode {
    pub config: Config,
    pub effective: Vec<String>,
}

pub struct Engine {
    pub root_dir: String,
    pub nodes: BTreeMap<String, OwnersNode>,
}

/// Directory names never searched for OWNERS files.
pub const IGNORED_DIRS: &[&str] = &[
    ".git",
    ".aspect",
    ".agents",
    ".claude",
    ".worktrees",
    ".pytest_cache",
    ".ruff_cache",
    "node_modules",
    "bazel-bin",
    "bazel-out",
    "bazel-testlogs",
    "dist",
    "bin",
];

/// The subtrees that must declare OWNERS when they exist.
pub const REQUIRED_SUBTREES: &[&str] = &[
    "apps",
    "apps/cli/devx",
    "apps/cli/homelab",
    "apps/desktop/nexus-agent",
    "apps/embedded/esp32-s3",
    "apps/mcp/slack",
    "apps/mobile/android-remote",
    "apps/web/backstage",
    "apps/web/gods-eye-view",
    "apps/web/oauth-user-inspector",
    "packages",
    "packages/design-system",
    "packages/design-system-android",
    "packages/pulumi",
    "infrastructure",
    "gitops",
    "tools",
    "apps/suites/tabula",
];

pub fn is_ignored(name: &str) -> bool {
    IGNORED_DIRS.contains(&name) || name.starts_with("bazel-")
}

fn is_owners_file(name: &str) -> bool {
    matches!(name, "OWNERS" | "OWNERS.yaml" | "OWNERS.yml")
}

fn depth(p: &str) -> usize {
    p.bytes().filter(|&b| b == b'/').count()
}

fn base_name(path: &str) -> &str {
    let t = path.trim_end_matches('/');
    if t.is_empty() {
        return "/";
    }
    match t.rfind('/') {
        Some(i) => &t[i + 1..],
        None => t,
    }
}

fn format_handles(handles: &[String]) -> Vec<String> {
    handles
        .iter()
        .map(|h| {
            if h.contains('@') {
                h.clone()
            } else {
                format!("@{h}")
            }
        })
        .collect()
}

impl Engine {
    pub fn new(root_dir: &str) -> Self {
        Engine {
            root_dir: root_dir.to_string(),
            nodes: BTreeMap::new(),
        }
    }

    /// Walks the tree in `filepath.WalkDir` order (each directory's entries
    /// sorted by name, depth first), reading and validating every OWNERS file.
    pub fn discover(&mut self) -> Result<(), String> {
        self.walk_root()
            .map_err(|e| format!("discovering OWNERS: {e}"))?;
        self.resolve_inheritance();
        Ok(())
    }

    fn walk_root(&mut self) -> Result<(), String> {
        let root = self.root_dir.clone();
        let meta =
            std::fs::symlink_metadata(&root).map_err(|e| gostr::path_error("lstat", &root, &e))?;
        let name = base_name(&root).to_string();
        if meta.is_dir() {
            if is_ignored(&name) {
                return Ok(());
            }
            self.walk_dir(&root)
        } else {
            self.visit_file(&root, &name)
        }
    }

    fn walk_dir(&mut self, path: &str) -> Result<(), String> {
        let rd = std::fs::read_dir(path).map_err(|e| gostr::path_error("open", path, &e))?;
        let mut entries: Vec<(Vec<u8>, bool)> = Vec::new();
        for ent in rd {
            let ent = ent.map_err(|e| gostr::path_error("readdirent", path, &e))?;
            let is_dir = ent.file_type().map(|t| t.is_dir()).unwrap_or(false);
            entries.push((ent.file_name().as_bytes().to_vec(), is_dir));
        }
        entries.sort();
        for (raw, is_dir) in entries {
            let name = String::from_utf8_lossy(&raw).into_owned();
            let child = gostr::join(path, &name);
            if is_dir {
                if is_ignored(&name) {
                    continue;
                }
                self.walk_dir(&child)?;
            } else {
                self.visit_file(&child, &name)?;
            }
        }
        Ok(())
    }

    fn visit_file(&mut self, path: &str, name: &str) -> Result<(), String> {
        if !is_owners_file(name) {
            return Ok(());
        }
        let dir = gostr::dir(path);
        let rel = if dir == self.root_dir {
            String::new()
        } else if self.root_dir == "/" {
            dir[1..].to_string()
        } else if let Some(r) = dir.strip_prefix(&format!("{}/", self.root_dir)) {
            r.to_string()
        } else {
            dir.clone()
        };
        let data = gostr::read_file(path).map_err(|e| format!("reading {path}: {e}"))?;
        let cfg = parse_config(&data).map_err(|e| format!("parsing {path}: {e}"))?;
        validate_config(path, &cfg)?;
        self.nodes.insert(
            rel,
            OwnersNode {
                config: cfg,
                effective: Vec::new(),
            },
        );
        Ok(())
    }

    fn sorted_paths(&self, include_root: bool) -> Vec<String> {
        let mut paths: Vec<String> = self
            .nodes
            .keys()
            .filter(|p| include_root || !p.is_empty())
            .cloned()
            .collect();
        paths.sort_by(|a, b| {
            if a.is_empty() != b.is_empty() {
                return b.is_empty().cmp(&a.is_empty());
            }
            depth(a).cmp(&depth(b)).then_with(|| a.cmp(b))
        });
        paths
    }

    fn resolve_inheritance(&mut self) {
        for p in self.sorted_paths(true) {
            let node = &self.nodes[&p];
            let current = node.config.effective_approvers();
            if p.is_empty() || node.config.options.no_parent_owners {
                self.nodes.get_mut(&p).unwrap().effective = current;
                continue;
            }
            let mut parent_path = p.as_str();
            let parent = loop {
                match parent_path.rfind('/') {
                    None => break self.nodes.get(""),
                    Some(i) => {
                        parent_path = &parent_path[..i];
                        if let Some(pn) = self.nodes.get(parent_path) {
                            break Some(pn);
                        }
                    }
                }
            };
            let effective = match parent {
                Some(pn) => {
                    let mut merged: Vec<String> = Vec::new();
                    for a in current.iter().chain(pn.effective.iter()) {
                        if !merged.contains(a) {
                            merged.push(a.clone());
                        }
                    }
                    merged
                }
                None => current,
            };
            self.nodes.get_mut(&p).unwrap().effective = effective;
        }
    }

    /// The GitHub CODEOWNERS text.
    pub fn compile(&self) -> String {
        let mut b = String::new();
        b.push_str("# VitruvianSoftware Monorepo CODEOWNERS\n");
        b.push_str("#\n");
        b.push_str("# Code generated by //tools/owners. DO NOT EDIT.\n");
        b.push_str("# To update ownership, edit per-directory OWNERS files and run:\n");
        b.push_str("#   bazel run //tools/owners -- --out .github/CODEOWNERS\n");
        b.push_str("#\n");
        b.push_str("# NOTE: CODEOWNERS uses \"last matching pattern wins\" ordering.\n\n");

        let root_owners = match self.nodes.get("") {
            Some(r) if !r.effective.is_empty() => format_handles(&r.effective).join(" "),
            _ => "@VitruvianSoftware/platform-team".to_string(),
        };
        b.push_str("# Catch-all root default\n");
        b.push_str(&format!("* {root_owners}\n\n"));

        b.push_str("# Root configuration files\n");
        for anchor in [
            "/.bazelrc",
            "/.bazelversion",
            "/MODULE.bazel",
            "/MODULE.bazel.lock",
            "/BUILD",
            "/.github/",
            "/tools/githooks/",
        ] {
            b.push_str(&format!("{anchor} {root_owners}\n"));
        }
        b.push('\n');

        b.push_str("# Subtree Directory Ownership Rules\n");
        for p in self.sorted_paths(false) {
            let node = &self.nodes[&p];
            b.push_str(&format!(
                "/{p}/ {}\n",
                format_handles(&node.effective).join(" ")
            ));
            for pf in &node.config.per_file {
                let approvers = if pf.approvers.is_empty() {
                    &pf.owners
                } else {
                    &pf.approvers
                };
                if !approvers.is_empty() {
                    b.push_str(&format!(
                        "/{p}/{} {}\n",
                        pf.pattern,
                        format_handles(approvers).join(" ")
                    ));
                }
            }
        }
        b
    }

    /// The required subtrees with no OWNERS declaration.
    pub fn check_coverage(&self) -> Vec<String> {
        let mut missing = Vec::new();
        for req in REQUIRED_SUBTREES {
            let dir = gostr::join(&self.root_dir, req);
            match std::fs::metadata(&dir) {
                Ok(m) if m.is_dir() => {}
                _ => continue,
            }
            if !self.nodes.contains_key(*req)
                && !["OWNERS", "OWNERS.yaml", "OWNERS.yml"]
                    .iter()
                    .any(|f| gostr::exists(&gostr::join(&dir, f)))
            {
                missing.push(req.to_string());
            }
        }
        if !self.nodes.contains_key("")
            && !["OWNERS", "OWNERS.yaml"]
                .iter()
                .any(|f| gostr::exists(&gostr::join(&self.root_dir, f)))
        {
            missing.push("(root)".to_string());
        }
        missing
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn tmp(name: &str) -> String {
        let d = std::env::temp_dir().join(format!("owners-rs-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d.to_string_lossy().into_owned()
    }

    #[test]
    fn inheritance_and_compilation() {
        let root = tmp("inherit");
        fs::write(
            format!("{root}/OWNERS"),
            "approvers:\n  - @VitruvianSoftware/platform-team\n",
        )
        .unwrap();
        fs::create_dir_all(format!("{root}/devx")).unwrap();
        fs::write(
            format!("{root}/devx/OWNERS"),
            "approvers:\n  - @VitruvianSoftware/devx-team\nper_file:\n  - pattern: \"*.md\"\n    approvers:\n      - @VitruvianSoftware/docs-team\n",
        )
        .unwrap();
        fs::create_dir_all(format!("{root}/tabula")).unwrap();
        fs::write(
            format!("{root}/tabula/OWNERS"),
            "approvers:\n  - @VitruvianSoftware/tabula-team\noptions:\n  no_parent_owners: true\n",
        )
        .unwrap();
        let mut e = Engine::new(&root);
        e.discover().unwrap();
        assert_eq!(e.nodes["devx"].effective.len(), 2);
        assert_eq!(
            e.nodes["tabula"].effective,
            vec!["@VitruvianSoftware/tabula-team"]
        );
        let c = e.compile();
        assert!(c.contains("* @VitruvianSoftware/platform-team"));
        assert!(c.contains("/devx/ @VitruvianSoftware/devx-team @VitruvianSoftware/platform-team"));
        assert!(c.contains("/devx/*.md @VitruvianSoftware/docs-team"));
        assert!(c.contains("/tabula/ @VitruvianSoftware/tabula-team"));
        fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn coverage() {
        let root = tmp("coverage");
        fs::create_dir_all(format!("{root}/tools")).unwrap();
        let mut e = Engine::new(&root);
        e.discover().unwrap();
        assert_eq!(e.check_coverage(), vec!["tools", "(root)"]);
        fs::write(format!("{root}/OWNERS"), "approvers:\n  - @a\n").unwrap();
        fs::write(format!("{root}/tools/OWNERS"), "approvers:\n  - @b\n").unwrap();
        let mut e = Engine::new(&root);
        e.discover().unwrap();
        assert!(e.check_coverage().is_empty());
        fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn ignored_directories() {
        for d in [
            ".claude",
            ".worktrees",
            ".agents",
            ".pytest_cache",
            ".ruff_cache",
            "node_modules",
            "bazel-bin",
            "dist",
            "bazel-anything",
        ] {
            assert!(is_ignored(d), "{d}");
        }
        assert!(!is_ignored("apps"));
    }
}
