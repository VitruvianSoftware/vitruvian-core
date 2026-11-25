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

//! foundation-leaf-guard: refuse a foundation deploy whose inputs name
//! anything other than a real leaf of its own stage (#4279).
//!
//! foundation-proj-deploy.yaml and foundation-app-deploy.yaml take
//! `working-directory`, `business-unit` and `environment` as free strings
//! (`environment` is a choice only on a dispatch, not on a workflow_call).
//! Their development and nonproduction Environments have no required
//! reviewer, so a dispatch made straight through the API, past the checks in
//! `//tools/agent-app workflow-run`, could point an apply at another Pulumi
//! project while holding that stage's deploy identity. This runs as the first
//! job of each workflow, so the checks hold whoever starts the run.

use shell_compat::{cat, out};

/// The stages this guard knows, by the name the workflow passes. Each one's
/// only accepted working directory is `infrastructure/pulumi/foundation/<stage>`.
pub const STAGES: &[&str] = &["gcp-projects", "gcp-app-infra"];

/// Every leaf name either stage has. A name outside this list is refused
/// before the disk is looked at; a listed name the stage does not have (the
/// app-infra stage has no `shared`) is refused by the leaf check.
pub const ENVIRONMENTS: &[&str] = &["shared", "development", "nonproduction", "production"];

/// `business_unit_<n>`, with `n` a positive decimal number and no leading
/// zero: `business_unit_1`, `business_unit_12`, never `business_unit_01`,
/// `business_unit_`, `business_unit_1/..` or `../business_unit_1`.
pub fn business_unit_ok(bu: &[u8]) -> bool {
    match bu.strip_prefix(b"business_unit_") {
        Some(n) => !n.is_empty() && n[0] != b'0' && n.iter().all(u8::is_ascii_digit),
        None => false,
    }
}

/// The working directory a stage accepts, the only one.
pub fn stage_root(stage: &[u8]) -> Vec<u8> {
    cat(&[b"infrastructure/pulumi/foundation/", stage])
}

/// Why the inputs are refused, or None when they name a real leaf. `root` is
/// the checkout the leaf is looked for in (the workflow passes `.`).
pub fn refusal(
    root: &std::path::Path,
    stage: &[u8],
    working_directory: &[u8],
    business_unit: &[u8],
    environment: &[u8],
) -> Option<Vec<u8>> {
    if !STAGES.iter().any(|s| s.as_bytes() == stage) {
        return Some(cat(&[
            b"unknown stage '",
            stage,
            b"' (known: ",
            STAGES.join(", ").as_bytes(),
            b")",
        ]));
    }
    let expected = stage_root(stage);
    if working_directory != expected.as_slice() {
        return Some(cat(&[
            b"working-directory must be ",
            &expected,
            b", got '",
            working_directory,
            b"'",
        ]));
    }
    if !business_unit_ok(business_unit) {
        return Some(cat(&[
            b"business-unit must be business_unit_<n>, got '",
            business_unit,
            b"'",
        ]));
    }
    if !ENVIRONMENTS.iter().any(|e| e.as_bytes() == environment) {
        return Some(cat(&[
            b"environment must be one of ",
            ENVIRONMENTS.join(", ").as_bytes(),
            b", got '",
            environment,
            b"'",
        ]));
    }
    // Every piece is now a fixed string or matched a pattern with no `/` or
    // `.`, so this path cannot leave the stage root. The leaf must still
    // exist as a Pulumi project, or the business unit names nothing real.
    let leaf = cat(&[&expected, b"/", business_unit, b"/", environment]);
    let project = root.join(shell_compat::path(&leaf)).join("Pulumi.yaml");
    match std::fs::symlink_metadata(&project) {
        Ok(m) if m.file_type().is_file() => None,
        _ => Some(cat(&[b"no Pulumi project at ", &leaf, b"/Pulumi.yaml"])),
    }
}

/// `foundation-leaf-guard <stage> <working-directory> <business-unit> <environment>`,
/// run from the checkout root.
pub fn run(args: &[Vec<u8>]) -> i32 {
    if args.len() != 4 {
        out(b"::error::foundation-leaf-guard: usage: foundation-leaf-guard <stage> <working-directory> <business-unit> <environment>\n");
        return 1;
    }
    let root = std::path::Path::new(".");
    match refusal(root, &args[0], &args[1], &args[2], &args[3]) {
        Some(why) => {
            // stdout: the runner reads ::error:: there and makes it an annotation.
            out(&cat(&[
                b"::error::foundation leaf guard: refusing this deploy: ",
                &why,
                b". Only the stage's own leaves can be deployed from this workflow (#4279).\n",
            ]));
            1
        }
        None => {
            out(&cat(&[
                b"foundation leaf guard: OK (",
                &args[1],
                b"/",
                &args[2],
                b"/",
                &args[3],
                b")\n",
            ]));
            0
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn business_units() {
        for ok in [
            &b"business_unit_1"[..],
            b"business_unit_2",
            b"business_unit_10",
        ] {
            assert!(business_unit_ok(ok), "{ok:?}");
        }
        for bad in [
            &b""[..],
            b"business_unit_",
            b"business_unit_0",
            b"business_unit_01",
            b"business_unit_1/..",
            b"../business_unit_1",
            b"business_unit_1 ",
            b"business_unit_x",
            b"Business_unit_1",
            b"business_unit_1\n",
        ] {
            assert!(!business_unit_ok(bad), "{bad:?}");
        }
    }

    #[test]
    fn stage_roots() {
        assert_eq!(
            stage_root(b"gcp-projects"),
            b"infrastructure/pulumi/foundation/gcp-projects"
        );
    }
}
