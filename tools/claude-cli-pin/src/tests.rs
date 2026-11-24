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

use super::*;

const PIN: &str = include_str!("../../testinfra/claude_cli.bzl");

fn fixtures() -> std::path::PathBuf {
    let base = std::env::var("TEST_SRCDIR")
        .map(|s| Path::new(&s).join(std::env::var("TEST_WORKSPACE").unwrap_or("_main".into())))
        .unwrap_or_else(|_| Path::new(env!("CARGO_MANIFEST_DIR")).join("../.."));
    base.join("tools/claude-cli-pin/testdata/2.1.331")
}

fn fixture(name: &str) -> String {
    std::fs::read_to_string(fixtures().join(name)).unwrap()
}

fn fake_pin(version: &str, fill: char) -> Pin {
    let hash = format!("sha512-{}==", fill.to_string().repeat(86));
    Pin {
        version: version.into(),
        integrity: PLATFORMS
            .iter()
            .map(|p| (p.to_string(), hash.clone()))
            .collect(),
    }
}

#[test]
fn committed_pin_parses_and_covers_every_platform() {
    let pin = parse_pin(PIN).unwrap();
    let platforms: Vec<&str> = pin.integrity.keys().map(String::as_str).collect();
    assert_eq!(platforms, PLATFORMS);
}

/// The npm registry's `dist.integrity` for 2.1.331, copied by hand from
/// `registry.npmjs.org`. The fixtures were recorded from the same answers.
const KNOWN_2_1_331: [(&str, &str); 4] = [
    ("darwin-arm64", "sha512-SVQmG05M7G/Lrbr3qUXDQXaV6+jEHudR9rSdsGjM0/zBjbZJh/mC812DwT3rHCA8rGlPC+HLfTwbvqmNQWNJZw=="),
    ("darwin-x64", "sha512-9UUbpdtrFXfQWXACwblqvPfKz5ZdtOtbiiwbRY3h1pzrqGcimLbUJUZty/SsHOXaTqSJQzFTuO6iSqZITyFKXQ=="),
    ("linux-arm64", "sha512-zy+OOB7i1J7rCjNoPB2ZBD7EAtT0Eus1wH+toklZGL2XpwHyw+POGUGOpEBBE6xe5EkAYWXzFSTQ3uD8UtWlRg=="),
    ("linux-x64", "sha512-IpvZ9c/NopO/sr8ThWLVAUDXVAFT3auLWrhbR6wq1dgkuJfZYdTtoXf6GajE5KL9R58iTt/86OPXrJAsM4+l8g=="),
];

#[test]
fn bumping_to_2_1_331_writes_the_known_hashes_and_nothing_else() {
    // Wind the committed file back to an older version with dummy hashes,
    // then bump it from the recorded registry answers for 2.1.331.
    let older = render_pin(PIN, &fake_pin("2.1.300", 'A')).unwrap();
    let target = resolve(&offline_fetcher(&fixtures()), "2.1.331").unwrap();
    let current = parse_pin(&older).unwrap();
    assert_eq!(
        plan(&current, &target, false).unwrap(),
        Plan::Update {
            from: "2.1.300".into(),
            to: "2.1.331".into()
        }
    );
    let bumped = render_pin(&older, &target).unwrap();

    let written = parse_pin(&bumped).unwrap();
    assert_eq!(written.version, "2.1.331");
    for (platform, hash) in KNOWN_2_1_331 {
        assert_eq!(written.integrity[platform], hash, "{platform}");
    }
    // Every line other than the version and the four hashes is untouched.
    let pin_line = |l: &&str| l.starts_with("_VERSION = ") || l.contains("\": \"sha512-");
    let rest = |t: &str| {
        t.lines()
            .filter(|l| !pin_line(l))
            .map(String::from)
            .collect::<Vec<_>>()
    };
    assert_eq!(rest(&bumped), rest(PIN));
    assert_eq!(bumped.lines().count(), PIN.lines().count());
}

#[test]
fn same_version_with_different_hashes_is_refused() {
    let current = parse_pin(PIN).unwrap();
    let mut target = current.clone();
    target.integrity.insert(
        "linux-x64".into(),
        fake_pin("x", 'B').integrity["linux-x64"].clone(),
    );
    let err = plan(&current, &target, false).unwrap_err();
    assert!(err.contains("differ"), "{err}");
}

#[test]
fn moving_back_needs_an_explicit_version() {
    let current = fake_pin("2.1.331", 'A');
    let older = fake_pin("2.1.40", 'B');
    assert!(plan(&current, &older, false).unwrap_err().contains("older"));
    assert!(matches!(
        plan(&current, &older, true),
        Ok(Plan::Update { .. })
    ));
    // Numeric, not string, order: 2.1.40 < 2.1.331.
    assert_eq!(compare_versions("2.1.40", "2.1.331"), Ordering::Less);
}

#[test]
fn main_package_must_list_every_platform_at_its_own_version() {
    let good = fixture("claude-code.json");
    assert_eq!(parse_main(&good, "2.1.331").unwrap(), "2.1.331");
    assert!(parse_main(&good, "2.1.330")
        .unwrap_err()
        .contains("asked for"));
    let wrong_dep = good.replace(
        "\"@anthropic-ai/claude-code-linux-x64\": \"2.1.331\"",
        "\"@anthropic-ai/claude-code-linux-x64\": \"2.1.330\"",
    );
    assert_ne!(wrong_dep, good);
    assert!(parse_main(&wrong_dep, "latest").is_err());
    let renamed = good.replace(
        "\"@anthropic-ai/claude-code-darwin-x64\"",
        "\"@anthropic-ai/other\"",
    );
    assert_ne!(renamed, good);
    assert!(parse_main(&renamed, "latest").is_err());
}

#[test]
fn platform_package_answers_are_checked() {
    let good = fixture("claude-code-linux-x64.json");
    assert!(parse_platform(&good, "linux-x64", "2.1.331").is_ok());
    assert!(parse_platform(&good, "linux-arm64", "2.1.331").is_err());
    assert!(parse_platform(&good, "linux-x64", "2.1.332").is_err());
    let sha1 = good.replace("sha512-", "sha1-");
    assert!(parse_platform(&sha1, "linux-x64", "2.1.331").is_err());
}

#[test]
fn malformed_inputs_are_rejected() {
    assert!(validate_request("latest").is_ok());
    for bad in ["2.1", "2.1.x", "2.1.3-beta", "", "../x"] {
        assert!(validate_request(bad).is_err(), "{bad}");
    }
    assert!(parse_pin(&PIN.replace("\"linux-arm64\":", "\"linux-arm\":")).is_err());
    assert!(render_pin("no pin here\n", &fake_pin("1.2.3", 'A')).is_err());
    let doubled = format!("{PIN}_VERSION = \"9.9.9\"\n");
    assert!(parse_pin(&doubled).is_err());
}
