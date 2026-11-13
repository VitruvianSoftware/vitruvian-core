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

//! Where an Atrium extension may live: the path says what kind of thing it is.
//!
//! A `vitruvian-tool.json` marks an extension that plugs into Vitruvian Atrium.
//! It may sit in exactly two places:
//!
//! - `apps/extensions/atrium/<name>/`: a product that lives only inside
//!   Atrium (Vitruvian GitHub, Vitruvian TV);
//! - an `atrium-extension/` folder: a standalone app that also ships an
//!   Atrium extension keeps it there, next to the code that builds it
//!   (`apps/desktop/vitruvian-speaker/atrium-extension/`).
//!
//! The SDK's samples and conformance tools (`packages/vitruvian-sdk/`) are
//! teaching material and test fixtures, not products, so they are exempt.
//! Anywhere else, the manifest is misplaced and this fails.

use crate::Context;

const MANIFEST: &str = "vitruvian-tool.json";
const EXTENSIONS_PREFIX: &str = "apps/extensions/atrium/";
const EXTENSION_FOLDER: &str = "atrium-extension";
const EXEMPT_PREFIXES: &[&str] = &[
    "packages/vitruvian-sdk/samples/",
    "packages/vitruvian-sdk/conformance/",
];

/// Whether a manifest at this workspace-relative path is where it belongs.
pub fn placed_correctly(rel: &str) -> bool {
    if EXEMPT_PREFIXES.iter().any(|p| rel.starts_with(p)) {
        return true;
    }
    let Some(dir) = rel.strip_suffix(MANIFEST).and_then(|d| d.strip_suffix('/')) else {
        // The file is the manifest at the repository root, or not a manifest.
        return false;
    };
    // apps/extensions/atrium/<name>/vitruvian-tool.json, exactly one level in.
    if let Some(name) = dir.strip_prefix(EXTENSIONS_PREFIX) {
        if !name.is_empty() && !name.contains('/') {
            return true;
        }
    }
    // <anything>/atrium-extension/vitruvian-tool.json
    dir.rsplit('/').next() == Some(EXTENSION_FOLDER)
}

/// The manifests (of the given workspace-relative paths) that are misplaced.
pub fn misplaced<'a>(paths: impl IntoIterator<Item = &'a str>) -> Vec<&'a str> {
    paths
        .into_iter()
        .filter(|p| p.rsplit('/').next() == Some(MANIFEST) && !placed_correctly(p))
        .collect()
}

pub fn check_extension_layout(ctx: &Context) {
    let mut files = ctx.files.discover(&ctx.root, MANIFEST);
    files.sort();
    let rels: Vec<String> = files.iter().map(|abs| ctx.rel(abs)).collect();
    let bad = misplaced(rels.iter().map(String::as_str));
    for rel in &rels {
        if !bad.contains(&rel.as_str()) {
            ctx.emit_ok(
                "layout",
                rel,
                "extension manifest",
                "apps/extensions/atrium/<name>/ or atrium-extension/",
                "the manifest is where the layout rule puts it",
            );
        } else {
            ctx.emit_fail(
                "layout",
                rel,
                "extension manifest",
                "apps/extensions/atrium/<name>/ or atrium-extension/",
                "a vitruvian-tool.json outside the two places an Atrium extension may live",
                "move it to apps/extensions/atrium/<name>/ (an extension with no app of its own) or <app>/atrium-extension/ (an app that also plugs into Atrium); see apps/extensions/README.md",
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Every manifest in the repository when this rule was written. The real
    /// check (`bazel run //tools/conformance:check`) walks the live tree; this
    /// list is what the rule must keep accepting.
    const REAL_TREE: &[&str] = &[
        "apps/desktop/vitruvian-code/macos/atrium-extension/vitruvian-tool.json",
        "apps/desktop/vitruvian-speaker/atrium-extension/vitruvian-tool.json",
        "apps/extensions/atrium/vitruvian-github/vitruvian-tool.json",
        "apps/extensions/atrium/vitruvian-tv/vitruvian-tool.json",
        "apps/mobile/vitruvian-remote/macmenu/atrium-extension/vitruvian-tool.json",
        "packages/vitruvian-sdk/conformance/reference-tool-2/vitruvian-tool.json",
        "packages/vitruvian-sdk/conformance/reference-tool/vitruvian-tool.json",
        "packages/vitruvian-sdk/samples/front-window/vitruvian-tool.json",
        "packages/vitruvian-sdk/samples/hello-panel-swift/vitruvian-tool.json",
    ];

    #[test]
    fn the_real_tree_passes() {
        assert!(misplaced(REAL_TREE.iter().copied()).is_empty());
    }

    #[test]
    fn a_misplaced_manifest_fails() {
        let bad = [
            // the old homes
            "apps/desktop/vitruvian-github/vitruvian-tool.json",
            "apps/desktop/vitruvian-speaker/tool/vitruvian-tool.json",
            "apps/mobile/vitruvian-remote/macmenu/tool/vitruvian-tool.json",
            // not one level inside apps/extensions/atrium
            "apps/extensions/atrium/vitruvian-tv/nested/vitruvian-tool.json",
            "apps/extensions/vitruvian-tv/vitruvian-tool.json",
            // the wrong folder name, a root manifest, and a lookalike file
            "apps/desktop/vitruvian-code/extension/vitruvian-tool.json",
            "vitruvian-tool.json",
            "packages/other/samples/vitruvian-tool.json",
        ];
        assert_eq!(misplaced(bad.iter().copied()), bad.to_vec());
    }

    #[test]
    fn other_files_are_not_manifests() {
        assert!(misplaced(["apps/desktop/x/not-vitruvian-tool.json.bak", "README.md"]).is_empty());
    }
}
