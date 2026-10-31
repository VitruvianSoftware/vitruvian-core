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

//! //tools/pulumi:resolve-identity against a gcp-identities.tsv-shaped map.
//! Ported 1:1 from the former resolve_identity_test.sh (cases 1, 1b, 2, 3, 4).

mod common;
use common::*;
use std::path::PathBuf;

const MAP: &str = "\
# comment line
infrastructure/pulumi/accounts/personal    james.nguyen@gmail.com   personal-llc   Personal Cloud Run + DNS
oauth-user-inspector/infra/app             sa-oauth-user-inspector-deploy-dev@prj-d-bu1-oss-floating-648a.iam.gserviceaccount.com   prj-d-bu1-oss-floating-648a     WIF: attribute.environment/oauth-user-inspector-development
-    james@abrial.ai   -   abrial future (reference only)
";

fn setup() -> (PathBuf, PathBuf) {
    let d = tempdir("resolve-identity");
    let map = d.join("ids.tsv");
    std::fs::write(&map, MAP).unwrap();
    (d, map)
}

fn resolve(map: &std::path::Path, dir: &str) -> (i32, String) {
    let mut c = cmd(&bin("RESOLVE_IDENTITY_BIN"), "/usr/bin:/bin");
    c.arg(map).arg(dir);
    let o = run(c);
    (code(&o), stdout(&o))
}

// 1. Known dir -> "account<TAB>project"; the free-text purpose column must not leak.
#[test]
fn known_dir_prints_account_tab_project() {
    let (_d, map) = setup();
    let (rc, out) = resolve(&map, "infrastructure/pulumi/accounts/personal");
    assert_eq!(rc, 0);
    assert_eq!(out, "james.nguyen@gmail.com\tpersonal-llc\n");
}

// 1b. A service-account row resolves the same way.
#[test]
fn service_account_dir() {
    let (_d, map) = setup();
    let (rc, out) = resolve(&map, "oauth-user-inspector/infra/app");
    assert_eq!(rc, 0);
    assert_eq!(
        out,
        "sa-oauth-user-inspector-deploy-dev@prj-d-bu1-oss-floating-648a.iam.gserviceaccount.com\tprj-d-bu1-oss-floating-648a\n"
    );
}

// 2. Unknown dir -> empty output, exit 0.
#[test]
fn unknown_dir_is_empty() {
    let (_d, map) = setup();
    let (rc, out) = resolve(&map, "infrastructure/pulumi/platform/repo-config");
    assert_eq!((rc, out.as_str()), (0, ""));
}

// 3. The "-" reference placeholder is never matched.
#[test]
fn placeholder_row_never_matches() {
    let (_d, map) = setup();
    let (rc, out) = resolve(&map, "-");
    assert_eq!((rc, out.as_str()), (0, ""));
}

// 4. Missing map file -> empty output, exit 0.
#[test]
fn missing_map_is_empty_exit_0() {
    let (d, _map) = setup();
    let (rc, out) = resolve(
        &d.join("nope.tsv"),
        "infrastructure/pulumi/accounts/personal",
    );
    assert_eq!((rc, out.as_str()), (0, ""));
}
