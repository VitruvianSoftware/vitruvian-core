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

//! sync.py, catalogue.py and registry.py in Rust: the same files, byte for
//! byte, the same output, and the same exit status. It takes only std.
//!
//! Python is modelled where the scripts lean on it: `pystr` is a `str`
//! (code points, lone surrogates and all), `json` is CPython's scanner and
//! encoder with the values they return, and `pyfs` is `os.path`, `pathlib`
//! and `open()` with the exceptions Python 3.12 raises. When Python would
//! stop with a traceback the port writes its last line, which is Python's.

pub mod catalogue;
pub mod json;
pub mod pyerr;
pub mod pyfs;
pub mod pystr;
pub mod registry;
pub mod sync;
pub mod unicode_tables;

/// sync_test.py's tests that read the repository, against the committed
/// files: run by `bazel test`, whose runfiles hold them.
#[cfg(test)]
mod in_sync_tests {
    use crate::json::{self, Value};
    use crate::pystr::PyStr;
    use crate::{pyfs, registry, sync};

    fn under_bazel() -> bool {
        std::env::var_os("TEST_SRCDIR").is_some()
    }

    fn root() -> PyStr {
        PyStr::from(".")
    }

    /// test_the_committed_files_are_what_sync_writes.
    #[test]
    fn the_committed_files_are_what_sync_writes() {
        if !under_bazel() {
            return;
        }
        assert_eq!(
            sync::stale(&root()).map_err(|e| e.last_line()),
            Ok(Vec::new()),
            "run: bazel run //tools/sync-site-tools:sync"
        );
    }

    /// test_no_copied_file_is_bumped_by_a_release.
    #[test]
    fn no_copied_file_is_bumped_by_a_release() {
        if !under_bazel() {
            return;
        }
        let config = json::loads(
            &pyfs::read_text(&PyStr::from(
                "packages/vitruvian-sdk/release-please-config.json",
            ))
            .unwrap(),
        )
        .unwrap();
        let extra = config
            .subscript("packages")
            .and_then(|p| p.subscript("packages/vitruvian-sdk"))
            .and_then(|p| p.subscript("extra-files"))
            .unwrap()
            .iterate()
            .unwrap();
        assert!(!extra.is_empty());
        let bumped: Vec<String> = extra
            .iter()
            .map(|entry| match entry {
                Value::Str(path) => path.to_string_lossy(),
                other => other.subscript("path").unwrap().py_str().to_string_lossy(),
            })
            .collect();
        let copied = sync::sources();
        let both: Vec<&String> = bumped.iter().filter(|b| copied.contains(b)).collect();
        assert!(
            both.is_empty(),
            "a release bumps a file the site copies: {:?}",
            both
        );
    }

    /// test_registry_discovers_all_plugins_and_renders_marketplaces.
    #[test]
    fn registry_discovers_all_plugins_and_renders_marketplaces() {
        if !under_bazel() {
            return;
        }
        let extensions = registry::discover_all(&root()).unwrap();
        let ids: Vec<String> = extensions
            .iter()
            .map(|e| e.id.py_str().to_string_lossy())
            .collect();
        for expected in [
            "ext-marketplace",
            "gh-watch",
            "worktree-band",
            "ralph-loop",
            "hookify",
            "security-guidance",
            "receipts-report",
            "live-context",
            "savvy-fleet",
            "mcp-roborock",
            "nexus-agent",
            "mcp-slack",
            "devx",
        ] {
            assert!(ids.iter().any(|id| id == expected), "{}", expected);
        }
        let claude = registry::render_claude_marketplace_json(&extensions).unwrap();
        let claude = json::loads(&crate::pystr::decode_utf8(&claude).unwrap()).unwrap();
        let names: Vec<String> = claude
            .subscript("plugins")
            .unwrap()
            .iterate()
            .unwrap()
            .iter()
            .map(|p| p.subscript("name").unwrap().py_str().to_string_lossy())
            .collect();
        for expected in ["ext-marketplace", "gh-watch", "mcp-roborock"] {
            assert!(names.iter().any(|n| n == expected), "{}", expected);
        }
        let ai = registry::render_ai_catalog_json(&extensions).unwrap();
        let ai = json::loads(&crate::pystr::decode_utf8(&ai).unwrap()).unwrap();
        assert_eq!(
            ai.subscript("extensions").unwrap().iterate().unwrap().len(),
            extensions.len()
        );
    }

    /// test_every_service_has_its_words.
    #[test]
    fn every_service_has_its_words() {
        if !under_bazel() {
            return;
        }
        let schema =
            json::loads(&pyfs::read_text(&PyStr::from("catalog/catalog.schema.json")).unwrap())
                .unwrap();
        let services = schema
            .subscript("$defs")
            .and_then(|d| d.subscript("tool"))
            .and_then(|d| d.subscript("properties"))
            .and_then(|d| d.subscript("uses"))
            .and_then(|d| d.subscript("items"))
            .and_then(|d| d.subscript("enum"))
            .unwrap()
            .iterate()
            .unwrap();
        let mut want: Vec<String> = services
            .iter()
            .map(|v| v.py_str().to_string_lossy())
            .collect();
        let mut have: Vec<String> = crate::catalogue::USES
            .iter()
            .map(|(k, _)| k.to_string())
            .collect();
        want.sort();
        have.sort();
        assert_eq!(have, want);
    }
}
