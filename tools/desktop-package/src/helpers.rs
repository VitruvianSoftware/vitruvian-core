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

//! The pure helpers of package-desktop.sh: no process, no file. Each is the
//! shell function of the same name, down to the text stage it runs through
//! (sed, grep, tr), in the C locale.

/// clean_version: the first semantic version in a tag, as bash's
/// `[[ =~ ([0-9]+\.[0-9]+(\.[0-9]+)?(-[a-zA-Z0-9.-]+)?) ]]` finds it
/// (leftmost, then longest); else the text after the last "-v", less a
/// leading "v".
pub fn clean_version(raw: &str) -> String {
    let b = raw.as_bytes();
    for start in 0..b.len() {
        if let Some(end) = semver_match_at(b, start) {
            return raw[start..end].to_string();
        }
    }
    let ver = match raw.rfind("-v") {
        Some(i) => &raw[i + 2..],
        None => raw,
    };
    ver.strip_prefix('v').unwrap_or(ver).to_string()
}

fn digits(b: &[u8], mut i: usize) -> usize {
    while i < b.len() && b[i].is_ascii_digit() {
        i += 1;
    }
    i
}

/// The end of the longest version match starting at `start`, if any.
fn semver_match_at(b: &[u8], start: usize) -> Option<usize> {
    let d1 = digits(b, start);
    if d1 == start || d1 >= b.len() || b[d1] != b'.' {
        return None;
    }
    let d2 = digits(b, d1 + 1);
    if d2 == d1 + 1 {
        return None;
    }
    let mut end = d2;
    if end < b.len() && b[end] == b'.' {
        let d3 = digits(b, end + 1);
        if d3 > end + 1 {
            end = d3;
        }
    }
    if end < b.len() && b[end] == b'-' {
        let mut k = end + 1;
        while k < b.len() && (b[k].is_ascii_alphanumeric() || b[k] == b'.' || b[k] == b'-') {
            k += 1;
        }
        if k > end + 1 {
            end = k;
        }
    }
    Some(end)
}

/// cask_name_for_app: PascalCase to kebab-case, through the script's two
/// `sed -E` passes and `tr '[:upper:]' '[:lower:]'`:
/// HomeSpeaker -> home-speaker, HTTPServer -> http-server.
pub fn cask_name_for_app(name: &str) -> String {
    let b = name.as_bytes();
    // s/([A-Z]+)([A-Z][a-z])/\1-\2/g
    let mut pass1 = Vec::with_capacity(b.len() + 4);
    let mut i = 0;
    while i < b.len() {
        let mut j = i;
        while j < b.len() && b[j].is_ascii_uppercase() {
            j += 1;
        }
        if j - i >= 2 && j < b.len() && b[j].is_ascii_lowercase() {
            pass1.extend_from_slice(&b[i..j - 1]);
            pass1.push(b'-');
            pass1.extend_from_slice(&b[j - 1..=j]);
            i = j + 1;
        } else {
            pass1.push(b[i]);
            i += 1;
        }
    }
    // s/([a-z0-9])([A-Z])/\1-\2/g
    let mut pass2 = Vec::with_capacity(pass1.len() + 4);
    let mut i = 0;
    while i < pass1.len() {
        let c = pass1[i];
        if (c.is_ascii_lowercase() || c.is_ascii_digit())
            && i + 1 < pass1.len()
            && pass1[i + 1].is_ascii_uppercase()
        {
            pass2.push(c);
            pass2.push(b'-');
            pass2.push(pass1[i + 1]);
            i += 2;
        } else {
            pass2.push(c);
            i += 1;
        }
    }
    let lower: Vec<u8> = pass2.iter().map(|c| c.to_ascii_lowercase()).collect();
    String::from_utf8_lossy(&lower).into_owned()
}

/// generate_cask_ruby: the Homebrew Cask formula, without its final newline
/// (the script captures it with `$(...)`). Empty `desc` / `homepage` take the
/// script's defaults.
pub fn generate_cask_ruby(
    cask_name: &str,
    version: &str,
    sha256: &str,
    download_url: &str,
    app_name: &str,
    desc: &str,
    homepage: &str,
) -> String {
    let desc = if desc.is_empty() {
        "macOS desktop application"
    } else {
        desc
    };
    let homepage = if homepage.is_empty() {
        "https://github.com/VitruvianSoftware/vitruvian-core"
    } else {
        homepage
    };
    format!(
        "cask \"{cask_name}\" do\n  version \"{version}\"\n  sha256 \"{sha256}\"\n\n  url \"{download_url}\"\n  name \"{app_name}\"\n  desc \"{desc}\"\n  homepage \"{homepage}\"\n\n  app \"{app_name}.app\"\nend"
    )
}

/// expected_artifact_names: the five DMG/ZIP names of a release.
pub fn expected_artifact_names(app_name: &str, version: &str) -> Vec<String> {
    let base = format!("{app_name}-{version}");
    vec![
        format!("{base}-universal.dmg"),
        format!("{base}-arm64.dmg"),
        format!("{base}-x86_64.dmg"),
        format!("{base}-universal.zip"),
        format!("{base}.dmg"),
    ]
}

/// required_release_assets: every artifact a finished run must have made,
/// each followed by its checksum sidecar, honouring --skip-dmg /
/// --skip-thinning (the shell passes them as the words "true"/"false"), then
/// the extra names promised with --require-asset.
pub fn required_release_assets(
    app_name: &str,
    version: &str,
    skip_dmg: bool,
    skip_thinning: bool,
    extra: &[String],
) -> Vec<String> {
    let base = format!("{app_name}-{version}");
    let mut names = vec![format!("{base}-universal.zip"), format!("{base}-macOS.zip")];
    if !skip_dmg {
        names.push(format!("{base}-universal.dmg"));
        names.push(format!("{base}.dmg"));
        if !skip_thinning {
            names.push(format!("{base}-arm64.dmg"));
            names.push(format!("{base}-x86_64.dmg"));
        }
    }
    names.extend(extra.iter().cloned());
    let mut out = Vec::with_capacity(names.len() * 2);
    for n in names {
        let sidecar = format!("{n}.sha256");
        out.push(n);
        out.push(sidecar);
    }
    out
}

/// missing_assets: each non-empty line of `required` that is not a whole
/// line of `present` (`grep -Fx`), in order.
pub fn missing_assets(required: &str, present: &str) -> Vec<String> {
    let have: std::collections::HashSet<&str> = present.split('\n').collect();
    required
        .split('\n')
        .filter(|n| !n.is_empty() && !have.contains(n))
        .map(|n| n.to_string())
        .collect()
}

/// The identity `security find-identity -v -p codesigning | grep 'Developer
/// ID Application' | head -1 | sed -E 's/.*"(.*)".*/\1/'` yields: the first
/// matching line, cut down to what lies between its last two quotes (the
/// whole line when it has fewer than two).
pub fn developer_id_from(listing: &str) -> String {
    let Some(line) = listing
        .split('\n')
        .find(|l| l.contains("Developer ID Application"))
    else {
        return String::new();
    };
    let quotes: Vec<usize> = line.match_indices('"').map(|(i, _)| i).collect();
    if quotes.len() < 2 {
        return line.to_string();
    }
    let (a, b) = (quotes[quotes.len() - 2], quotes[quotes.len() - 1]);
    line[a + 1..b].to_string()
}

/// basename(1), and `basename path suffix`.
pub fn basename(path: &str, suffix: &str) -> String {
    let trimmed = path.trim_end_matches('/');
    if trimmed.is_empty() {
        return if path.is_empty() {
            String::new()
        } else {
            "/".to_string()
        };
    }
    let base = match trimmed.rfind('/') {
        Some(i) => &trimmed[i + 1..],
        None => trimmed,
    };
    if !suffix.is_empty() && base.len() > suffix.len() && base.ends_with(suffix) {
        base[..base.len() - suffix.len()].to_string()
    } else {
        base.to_string()
    }
}

/// dirname(1).
pub fn dirname(path: &str) -> String {
    let trimmed = path.trim_end_matches('/');
    if trimmed.is_empty() {
        return if path.starts_with('/') {
            "/".to_string()
        } else {
            ".".to_string()
        };
    }
    match trimmed.rfind('/') {
        None => ".".to_string(),
        Some(i) => {
            let parent = trimmed[..i].trim_end_matches('/');
            if parent.is_empty() {
                "/".to_string()
            } else {
                parent.to_string()
            }
        }
    }
}

/// The first field of each line (`cut -d' ' -f1`), captured by `$(...)`.
pub fn first_fields(text: &str) -> String {
    let body = text.strip_suffix('\n').unwrap_or(text);
    let mut out: Vec<&str> = Vec::new();
    if !text.is_empty() {
        for line in body.split('\n') {
            out.push(line.split(' ').next().unwrap_or(""));
        }
    }
    let mut joined = out.join("\n");
    while joined.ends_with('\n') {
        joined.pop();
    }
    joined
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clean_version_matches_the_script_cases() {
        for (tag, want) in [
            ("home-speaker-v1.11.0", "1.11.0"),
            ("vitruvian-v3.37.1", "3.37.1"),
            ("nexus-agent-v1.20.1", "1.20.1"),
            ("v2.0.4", "2.0.4"),
            ("4.5.6", "4.5.6"),
            ("nexus-agent-1.20.1", "1.20.1"),
            ("vitruvian-v3.38.0-beta.1", "3.38.0-beta.1"),
            ("x-v12.3", "12.3"),
            ("1.2.3.4", "1.2.3"),
            ("1.2.3-", "1.2.3"),
            ("1.2-rc", "1.2-rc"),
            ("app-v-latest", "-latest"),
            ("app-vnext", "next"),
            ("vnext", "next"),
            ("", ""),
            ("a.1.2", "1.2"),
        ] {
            assert_eq!(clean_version(tag), want, "{tag}");
        }
    }

    #[test]
    fn cask_names() {
        for (app, want) in [
            ("HomeSpeaker", "home-speaker"),
            ("NexusAgent", "nexus-agent"),
            ("Vitruvian", "vitruvian"),
            ("MyNewDesktopClient", "my-new-desktop-client"),
            ("HTTPServer", "http-server"),
            ("App2Go", "app2-go"),
            ("ABC", "abc"),
            ("aBCd", "a-b-cd"),
            ("Mock App", "mock app"),
        ] {
            assert_eq!(cask_name_for_app(app), want, "{app}");
        }
    }

    #[test]
    fn cask_formula() {
        let got = generate_cask_ruby("t", "1.0.0", "sha", "https://u", "TestApp", "", "");
        assert!(got.starts_with("cask \"t\" do\n  version \"1.0.0\"\n  sha256 \"sha\"\n\n"));
        assert!(got.contains("  desc \"macOS desktop application\"\n"));
        assert!(got.ends_with("  app \"TestApp.app\"\nend"));
    }

    #[test]
    fn release_assets_follow_the_flags() {
        let extra = vec!["TestApp-1.0.0-tool.zip".to_string()];
        let all = required_release_assets("TestApp", "1.0.0", false, false, &extra);
        assert_eq!(all.len(), 14);
        assert_eq!(all[0], "TestApp-1.0.0-universal.zip");
        assert_eq!(all[1], "TestApp-1.0.0-universal.zip.sha256");
        assert_eq!(all[13], "TestApp-1.0.0-tool.zip.sha256");
        assert_eq!(required_release_assets("A", "1", true, false, &[]).len(), 4);
        assert_eq!(required_release_assets("A", "1", false, true, &[]).len(), 8);
        assert_eq!(expected_artifact_names("A", "1").len(), 5);
    }

    #[test]
    fn missing_assets_is_exact() {
        assert!(missing_assets("a\nb", "b\na\nc").is_empty());
        assert_eq!(missing_assets("a\nb\nc", "b"), vec!["a", "c"]);
        assert_eq!(missing_assets("a.zip", "a.zip.sha256"), vec!["a.zip"]);
        assert!(missing_assets("", "").is_empty());
    }

    #[test]
    fn developer_id_extraction() {
        let listing = "  1) ABCD \"Apple Development: x\"\n  2) EF01 \"Developer ID Application: V (TEAM)\"\n     2 valid identities found\n";
        assert_eq!(
            developer_id_from(listing),
            "Developer ID Application: V (TEAM)"
        );
        assert_eq!(
            developer_id_from("x a\"b\"c\"d Developer ID Application"),
            "c"
        );
        assert_eq!(
            developer_id_from("Developer ID Application no quotes"),
            "Developer ID Application no quotes"
        );
        assert_eq!(developer_id_from(""), "");
    }

    #[test]
    fn path_parts_like_coreutils() {
        assert_eq!(basename("dist/X.app/", ".app"), "X");
        assert_eq!(basename(".app", ".app"), ".app");
        assert_eq!(basename("/", ""), "/");
        assert_eq!(dirname("a/b/c"), "a/b");
        assert_eq!(dirname("c"), ".");
        assert_eq!(dirname("/c"), "/");
        assert_eq!(dirname("a//b//"), "a");
        assert_eq!(first_fields("abc  x\n"), "abc");
    }
}
