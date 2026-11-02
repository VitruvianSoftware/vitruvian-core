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

//! Black-box tests for //tools/ci:llvm_cache_key, the Actions cache key for
//! the extracted LLVM toolchain (the llvm-cache-restore composite). Runs the
//! REAL binary against os-release fixtures. Ported case for case from the
//! former llvm-cache-key_test.sh.
//!
//! The load-bearing case is the FIRST one: the two fixtures are the real
//! /etc/os-release from GitHub runner images 20260831.293 (Ubuntu 24.04.4) and
//! 20260907.300 (24.04.5). The old key -- keyed only on runner.os plus
//! hashFiles('MODULE.bazel') -- was IDENTICAL across that pair, so the point
//! release kept hitting a 2.2GB entry whose contents Bazel then rejected and
//! re-extracted, on every run, with no way to ever save the good one (#2242).
//! If this passes with a key that ignores /etc/os-release, it tests nothing.

use ci_testkit::{bin, write, Run, TempDir};

/// Verbatim shape of Ubuntu's /etc/os-release; VERSION/VERSION_ID/PRETTY_NAME
/// all move on a point release, which is why the digest moves.
const OS_RELEASE_24044: &str = r#"PRETTY_NAME="Ubuntu 24.04.4 LTS"
NAME="Ubuntu"
VERSION_ID="24.04"
VERSION="24.04.4 LTS (Noble Numbat)"
VERSION_CODENAME=noble
ID=ubuntu
ID_LIKE=debian
UBUNTU_CODENAME=noble
"#;

const MOD: &str = "aaaaaaaabbbbbbbbcccccccc";

struct Fixtures {
    dir: TempDir,
}

impl Fixtures {
    fn new() -> Fixtures {
        let dir = TempDir::new();
        write(dir.join("os-release-24044"), OS_RELEASE_24044);
        write(
            dir.join("os-release-24045"),
            OS_RELEASE_24044.replace("24.04.4", "24.04.5"),
        );
        Fixtures { dir }
    }

    fn path(&self, name: &str) -> String {
        self.dir.join(name).display().to_string()
    }

    /// The key, asserting the run succeeded.
    fn key(&self, os: &str, module: &str, release: &str) -> String {
        let o = Run::new(&bin("BIN"))
            .args([os, module, &self.path(release)])
            .go();
        assert_eq!(o.code, 0, "llvm_cache_key {os} {module} {release}: {o:?}");
        o.stdout.trim_end_matches('\n').to_string()
    }
}

#[test]
fn a_runner_image_point_release_changes_the_key() {
    let f = Fixtures::new();
    let k4 = f.key("Linux", MOD, "os-release-24044");
    let k5 = f.key("Linux", MOD, "os-release-24045");
    assert_ne!(
        k4, k5,
        "24.04.4 and 24.04.5 produced the SAME key; Bazel would reject the restored contents and re-extract on every run"
    );
}

#[test]
fn the_same_os_release_gives_a_stable_key() {
    let f = Fixtures::new();
    assert_eq!(
        f.key("Linux", MOD, "os-release-24044"),
        f.key("Linux", MOD, "os-release-24044"),
        "the key is not deterministic, so the cache would never hit"
    );
}

#[test]
fn a_module_bazel_change_still_changes_the_key() {
    let f = Fixtures::new();
    assert_ne!(
        f.key("Linux", MOD, "os-release-24044"),
        f.key("Linux", "ffffffff00000000", "os-release-24044"),
        "the MODULE.bazel hash is not part of the key (an llvm_versions bump would keep hitting)"
    );
}

#[test]
fn runner_os_is_part_of_the_key() {
    let f = Fixtures::new();
    assert_ne!(
        f.key("Linux", MOD, "os-release-24044"),
        f.key("macOS", MOD, "os-release-24044")
    );
}

#[test]
fn an_unreadable_os_release_degrades_to_a_stable_non_empty_key() {
    let f = Fixtures::new();
    let a = f.key("Linux", MOD, "absent");
    let b = f.key("Linux", MOD, "absent");
    assert!(!a.is_empty(), "a missing os-release gave an empty key");
    assert_eq!(a, b, "a missing os-release gave a different key each run");
}

#[test]
fn the_key_is_a_single_bare_token() {
    let k = Fixtures::new().key("Linux", MOD, "os-release-24044");
    assert!(
        !k.is_empty() && !k.contains(char::is_whitespace),
        "the key must be one bare token usable in a YAML cache key: {k:?}"
    );
}

/// The v1 prefix is burned: those entries hold candidates from more than one
/// image and Bazel validates none of them. A new scheme must not reuse it.
#[test]
fn the_key_uses_a_fresh_scheme_prefix_not_the_poisoned_v1() {
    let k = Fixtures::new().key("Linux", MOD, "os-release-24044");
    assert!(
        !k.starts_with("llvm-contents-v1-"),
        "the key still uses the poisoned v1 prefix: {k}"
    );
    assert!(
        k.starts_with("llvm-contents-v"),
        "unexpected key shape: {k}"
    );
}

#[test]
fn the_key_has_no_empty_segments() {
    let k = Fixtures::new().key("Linux", MOD, "os-release-24044");
    assert!(!k.contains("--"), "a digest is missing from the key: {k}");
}

/// Fail closed on a missing digest tool. The first cut of the shell script
/// used `local osrel="$(sha256sum ...)"`, where `local` masks the
/// substitution's exit status: on a box without coreutils it emitted
/// `...-Linux--<modhash>`, an EMPTY digest segment that collapses every
/// os-release back onto one key -- the original bug wearing the fix's clothes.
/// A key that cannot include its inputs must not be emitted at all.
#[test]
fn no_sha256_tool_on_path_fails_closed_rather_than_emitting_a_partial_key() {
    let f = Fixtures::new();
    let empty = TempDir::new();
    let o = Run::new(&bin("BIN"))
        .args(["Linux", MOD, &f.path("os-release-24044")])
        .env("PATH", empty.path())
        .go();
    assert_ne!(
        o.code, 0,
        "with no sha256 tool the binary emitted a key: {o:?}"
    );
    assert!(o.stdout.is_empty(), "printed a key anyway: {:?}", o.stdout);
    assert!(
        o.stderr.contains("::error::llvm-cache-key"),
        "the failure must be an ::error annotation: {:?}",
        o.stderr
    );
}

/// The llvm-cache-restore composite passes only two arguments, so the
/// default must be the runner's real /etc/os-release.
#[test]
fn with_two_arguments_it_keys_on_etc_os_release() {
    let two = Run::new(&bin("BIN")).args(["Linux", MOD]).go();
    let three = Run::new(&bin("BIN"))
        .args(["Linux", MOD, "/etc/os-release"])
        .go();
    assert_eq!(two.code, 0, "{two:?}");
    assert_eq!(
        two.stdout, three.stdout,
        "the default os-release path is not /etc/os-release"
    );
}
