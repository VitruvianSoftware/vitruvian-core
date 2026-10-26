// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT
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

//! Backstage catalog component entity compliance, root catalog wiring,
//! document link resolution, and CODEOWNERS conformance.
//! Migrated from `tests/test_catalog.py`.

use std::collections::HashSet;
use std::fs;

use crate::{component_dir, read_component_file, repo_root};

#[derive(Clone, Debug, Default)]
pub struct CatalogLink {
    pub url: String,
    pub title: String,
    pub icon: String,
}

#[derive(Clone, Debug, Default)]
pub struct ParsedCatalog {
    pub api_version: String,
    pub kind: String,
    pub name: String,
    pub title: String,
    pub description: String,
    pub tags: Vec<String>,
    pub project_slug: String,
    pub techdocs_ref: String,
    pub release_model: String,
    pub spec_type: String,
    pub lifecycle: String,
    pub owner: String,
    pub system: String,
    pub links: Vec<CatalogLink>,
}

/// Parses `apps/embedded/esp32-s3/catalog-info.yaml` without external YAML dependencies.
pub fn parse_component_catalog(raw: &str) -> ParsedCatalog {
    let mut cat = ParsedCatalog::default();
    let mut section = "";
    let mut subsection = "";
    let mut current_link: Option<CatalogLink> = None;

    for line in raw.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let indent = line.len() - line.trim_start().len();

        if indent == 0 {
            if let Some(link) = current_link.take() {
                cat.links.push(link);
            }
            subsection = "";
            if let Some(v) = trimmed.strip_prefix("apiVersion:") {
                cat.api_version = v.trim().to_string();
            } else if let Some(v) = trimmed.strip_prefix("kind:") {
                cat.kind = v.trim().to_string();
            } else if trimmed == "metadata:" {
                section = "metadata";
            } else if trimmed == "spec:" {
                section = "spec";
            }
            continue;
        }

        if section == "metadata" {
            if indent == 2 {
                if let Some(link) = current_link.take() {
                    cat.links.push(link);
                }
                if let Some(v) = trimmed.strip_prefix("name:") {
                    cat.name = v.trim().to_string();
                    subsection = "";
                } else if let Some(v) = trimmed.strip_prefix("title:") {
                    cat.title = v.trim().to_string();
                    subsection = "";
                } else if let Some(v) = trimmed.strip_prefix("description:") {
                    cat.description = v.trim().to_string();
                    subsection = "";
                } else if trimmed == "tags:" {
                    subsection = "tags";
                } else if trimmed == "annotations:" {
                    subsection = "annotations";
                } else if trimmed == "links:" {
                    subsection = "links";
                }
            } else if subsection == "tags" {
                if let Some(tag) = trimmed.strip_prefix("- ") {
                    cat.tags.push(tag.trim().to_string());
                }
            } else if subsection == "annotations" {
                if let Some(v) = trimmed.strip_prefix("github.com/project-slug:") {
                    cat.project_slug = v.trim().to_string();
                } else if let Some(v) = trimmed.strip_prefix("backstage.io/techdocs-ref:") {
                    cat.techdocs_ref = v.trim().to_string();
                } else if let Some(v) = trimmed.strip_prefix("vitruvian.dev/release-model:") {
                    cat.release_model = v.trim().to_string();
                }
            } else if subsection == "links" {
                if let Some(rest) = trimmed.strip_prefix("- url:") {
                    if let Some(prev) = current_link.take() {
                        cat.links.push(prev);
                    }
                    current_link = Some(CatalogLink {
                        url: rest.trim().to_string(),
                        ..Default::default()
                    });
                } else if let Some(v) = trimmed.strip_prefix("title:") {
                    if let Some(ref mut l) = current_link {
                        l.title = v.trim().to_string();
                    }
                } else if let Some(v) = trimmed.strip_prefix("icon:") {
                    if let Some(ref mut l) = current_link {
                        l.icon = v.trim().to_string();
                    }
                }
            }
        } else if section == "spec" && indent == 2 {
            if let Some(v) = trimmed.strip_prefix("type:") {
                cat.spec_type = v.trim().to_string();
            } else if let Some(v) = trimmed.strip_prefix("lifecycle:") {
                cat.lifecycle = v.trim().to_string();
            } else if let Some(v) = trimmed.strip_prefix("owner:") {
                cat.owner = v.trim().to_string();
            } else if let Some(v) = trimmed.strip_prefix("system:") {
                cat.system = v.trim().to_string();
            }
        }
    }

    if let Some(link) = current_link.take() {
        cat.links.push(link);
    }

    cat
}

pub fn is_valid_tag(tag: &str) -> bool {
    !tag.is_empty()
        && tag
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
}

pub fn run_suite() -> usize {
    let mut checks = 0usize;

    let comp = component_dir();
    let catalog_path = comp.join("catalog-info.yaml");
    assert!(
        catalog_path.is_file(),
        "Missing Backstage catalog file at {}",
        catalog_path.display()
    );
    checks += 1;

    let raw = read_component_file("catalog-info.yaml");
    assert!(raw.contains("Copyright (c) 2026 VitruvianSoftware"));
    checks += 1;

    let cat = parse_component_catalog(&raw);
    assert_eq!(cat.api_version, "backstage.io/v1alpha1");
    assert_eq!(cat.kind, "Component");
    assert!(cat.name == "esp32-s3" || cat.name == "mac-controller");
    assert!(!cat.title.trim().is_empty());
    assert!(cat.description.trim().len() >= 20);
    assert!(cat.tags.len() >= 3);
    for t in &cat.tags {
        assert!(is_valid_tag(t), "invalid tag: {}", t);
    }
    let tag_set: HashSet<&str> = cat.tags.iter().map(|s| s.as_str()).collect();
    for req in ["esp32-s3", "embedded", "macos"] {
        assert!(tag_set.contains(req), "missing expected tag {}", req);
    }
    assert_eq!(cat.project_slug, "VitruvianSoftware/vitruvian-core");
    assert_eq!(cat.techdocs_ref, "dir:.");
    assert_eq!(cat.release_model, "monorepo-bazel");
    assert!(matches!(
        cat.spec_type.as_str(),
        "application" | "tool" | "device" | "hardware" | "service"
    ));
    assert!(matches!(
        cat.lifecycle.as_str(),
        "experimental" | "development" | "production"
    ));
    assert_eq!(cat.owner, "platform-team");
    assert_eq!(cat.system, "vitruvian-core");
    checks += 11;

    // Links structure & local resolution
    assert!(cat.links.len() >= 5);
    let mut checked_links = 0usize;
    let blob_prefix =
        "https://github.com/VitruvianSoftware/vitruvian-core/blob/main/apps/embedded/esp32-s3/";
    let tree_prefix =
        "https://github.com/VitruvianSoftware/vitruvian-core/tree/main/apps/embedded/esp32-s3";
    for link in &cat.links {
        assert!(!link.url.is_empty());
        assert!(!link.title.is_empty());
        assert!(!link.icon.is_empty());
        if let Some(rel) = link.url.strip_prefix(blob_prefix) {
            assert!(
                comp.join(rel).is_file(),
                "Link '{}' points to missing file {}",
                link.title,
                rel
            );
            checked_links += 1;
        } else if link.url == tree_prefix {
            assert!(comp.is_dir());
            checked_links += 1;
        }
    }
    assert!(checked_links >= 4);
    checks += 3;

    // Core documentation files
    for doc in [
        "README.md",
        "docs/architecture.md",
        "docs/protocol.md",
        "docs/hardware.md",
        "docs/flashing.md",
    ] {
        assert!(
            comp.join(doc).is_file(),
            "Missing required documentation file: {}",
            doc
        );
    }
    checks += 1;

    // OWNERS file
    let owners_raw = read_component_file("OWNERS");
    assert!(owners_raw.contains("@VitruvianSoftware/platform-team"));
    checks += 1;

    // Root catalog & CODEOWNERS when accessible
    let root = repo_root();
    let root_catalog = root.join("catalog-info.yaml");
    if let Ok(root_raw) = fs::read_to_string(&root_catalog) {
        assert!(
            root_raw.contains("./apps/embedded/esp32-s3/catalog-info.yaml")
                || root_raw.contains("./iot/esp32-s3/catalog-info.yaml")
                || root_raw.contains("./mac-controller/catalog-info.yaml")
        );
        checks += 1;
    }

    let codeowners = root.join(".github/CODEOWNERS");
    if let Ok(co_raw) = fs::read_to_string(&codeowners) {
        let mut matched_team = None;
        for line in co_raw.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() || trimmed.starts_with('#') {
                continue;
            }
            let parts: Vec<&str> = trimmed.split_whitespace().collect();
            if parts.len() >= 2
                && matches!(
                    parts[0],
                    "/apps/embedded/esp32-s3/" | "/iot/esp32-s3/" | "/iot/" | "/mac-controller/"
                )
            {
                assert!(parts[1..].contains(&"@VitruvianSoftware/platform-team"));
                matched_team = parts[1].rsplit('/').next().map(|s| s.to_string());
                break;
            }
        }
        assert_eq!(matched_team.as_deref(), Some(cat.owner.as_str()));
        checks += 1;
    }

    checks
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_catalog_file_integrity() {
        let comp = component_dir();
        let catalog_path = comp.join("catalog-info.yaml");
        assert!(catalog_path.is_file());
        let raw = read_component_file("catalog-info.yaml");
        assert!(raw.contains("Copyright (c) 2026 VitruvianSoftware"));
        let parsed = parse_component_catalog(&raw);
        assert!(!parsed.api_version.is_empty());
    }

    #[test]
    fn test_backstage_component_schema() {
        let raw = read_component_file("catalog-info.yaml");
        let cat = parse_component_catalog(&raw);

        assert_eq!(cat.api_version, "backstage.io/v1alpha1");
        assert_eq!(cat.kind, "Component");
        assert!(matches!(cat.name.as_str(), "esp32-s3" | "mac-controller"));
        assert!(!cat.title.trim().is_empty());
        assert!(cat.description.trim().len() >= 20);
        assert!(cat.tags.len() >= 3);
        for tag in &cat.tags {
            assert!(is_valid_tag(tag), "Tag '{}' invalid", tag);
        }
        let tags: HashSet<&str> = cat.tags.iter().map(|s| s.as_str()).collect();
        assert!(tags.contains("esp32-s3"));
        assert!(tags.contains("embedded"));
        assert!(tags.contains("macos"));

        assert_eq!(cat.project_slug, "VitruvianSoftware/vitruvian-core");
        assert_eq!(cat.techdocs_ref, "dir:.");
        assert_eq!(cat.release_model, "monorepo-bazel");

        assert!(matches!(
            cat.spec_type.as_str(),
            "application" | "tool" | "device" | "hardware" | "service"
        ));
        assert!(matches!(
            cat.lifecycle.as_str(),
            "experimental" | "development" | "production"
        ));
        assert_eq!(cat.owner, "platform-team");
        assert_eq!(cat.system, "vitruvian-core");
    }

    #[test]
    fn test_root_catalog_wiring() {
        let root_catalog = repo_root().join("catalog-info.yaml");
        if let Ok(root_raw) = fs::read_to_string(&root_catalog) {
            assert!(root_raw.contains("name: vitruvian-core-apps"));
            assert!(
                root_raw.contains("./apps/embedded/esp32-s3/catalog-info.yaml")
                    || root_raw.contains("./iot/esp32-s3/catalog-info.yaml")
                    || root_raw.contains("./mac-controller/catalog-info.yaml")
            );
        }
    }

    #[test]
    fn test_documentation_links_and_files_exist() {
        let comp = component_dir();
        let raw = read_component_file("catalog-info.yaml");
        let cat = parse_component_catalog(&raw);

        assert!(cat.links.len() >= 5);
        let blob_prefix =
            "https://github.com/VitruvianSoftware/vitruvian-core/blob/main/apps/embedded/esp32-s3/";
        let tree_prefix =
            "https://github.com/VitruvianSoftware/vitruvian-core/tree/main/apps/embedded/esp32-s3";
        let mut checked = 0usize;
        for link in &cat.links {
            assert!(!link.url.is_empty());
            assert!(!link.title.is_empty());
            assert!(!link.icon.is_empty());
            if let Some(rel) = link.url.strip_prefix(blob_prefix) {
                assert!(comp.join(rel).is_file());
                checked += 1;
            } else if link.url == tree_prefix {
                assert!(comp.is_dir());
                checked += 1;
            }
        }
        assert!(checked >= 4);

        for doc in [
            "README.md",
            "docs/architecture.md",
            "docs/protocol.md",
            "docs/hardware.md",
            "docs/flashing.md",
        ] {
            assert!(comp.join(doc).is_file(), "Missing {}", doc);
        }
    }

    #[test]
    fn test_codeowners_and_local_owners_conformance() {
        let owners = read_component_file("OWNERS");
        assert!(owners.contains("approvers:"));
        assert!(owners.contains("@VitruvianSoftware/platform-team"));

        let cat = parse_component_catalog(&read_component_file("catalog-info.yaml"));
        let codeowners = repo_root().join(".github/CODEOWNERS");
        if let Ok(co_raw) = fs::read_to_string(&codeowners) {
            let mut found = false;
            for line in co_raw.lines() {
                let parts: Vec<&str> = line.trim().split_whitespace().collect();
                if parts.len() >= 2 && parts[0] == "/apps/embedded/esp32-s3/" {
                    found = true;
                    assert!(parts[1..].contains(&"@VitruvianSoftware/platform-team"));
                    let coteam = parts[1].rsplit('/').next().unwrap();
                    assert_eq!(cat.owner, coteam);
                    break;
                }
            }
            assert!(found);
        }
    }
}
