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

//! The rehearsal of Nexus Agent's release runs the steps the release runs.
//!
//! Two workflows hold the same steps:
//!
//! - apps/desktop/nexus-agent/.github/workflows/release.yml is exported to the
//!   public mirror and builds, packages and publishes a release there. It never
//!   runs in this repository, and the mirror tags a release before it builds.
//! - .github/workflows/nexus-agent-mirror-toolchain.yaml rehearses its build and
//!   packaging here, on pull requests.
//!
//! A rehearsal of different steps proves nothing about the release, and nothing
//! else would say they had drifted apart. So this compares, step by step, what
//! both run between `swift build` and the ZIP: the build command, what is
//! uploaded and where it is downloaded to, the `lipo` step, every bundle.sh call,
//! the DMGs and the ZIP. It reads the files as text; nothing is built.

use std::collections::HashMap;
use std::fs;
use std::process::ExitCode;

const DOC: &str = "The rehearsal of Nexus Agent's release runs the steps the release runs.\n\
\n\
Two workflows hold the same steps:\n\
\n\
- apps/desktop/nexus-agent/.github/workflows/release.yml is exported to the\n\
  public mirror and builds, packages and publishes a release there. It never\n\
  runs in this repository, and the mirror tags a release before it builds.\n\
- .github/workflows/nexus-agent-mirror-toolchain.yaml rehearses its build and\n\
  packaging here, on pull requests.\n\
\n\
A rehearsal of different steps proves nothing about the release, and nothing\n\
else would say they had drifted apart. So this compares, step by step, what\n\
both run between `swift build` and the ZIP: the build command, what is\n\
uploaded and where it is downloaded to, the `lipo` step, every bundle.sh call,\n\
the DMGs and the ZIP. It reads the files as text; nothing is built.\n\
\n\
Usage: nexus_agent_release_rehearsal_test.py <release.yml> <rehearsal.yaml>\n";

/// Release job -> the rehearsal job that stands in for it.
const JOBS: &[(&str, &str)] = &[("build-macos", "build"), ("package", "package")];

/// Steps only the release has: they publish, with the mirror's token.
const RELEASE_ONLY: &[&str] = &[
    "Upload release assets",
    "Say what the catalog entry pins",
    "Update Homebrew Cask",
];

/// Steps only the rehearsal has: what it prints and what it checks.
const REHEARSAL_ONLY: &[&str] = &[
    "Show the toolchain the mirror builds with",
    "Run the tests",
    "Show what was downloaded",
    "Check the three apps",
    // The rehearsal starts the app it packaged; a release starts nothing.
    "Start the packaged app",
    "Check the app inside the ZIP",
    // The rehearsal judges the tool's folder as the Vitruvian app would; a
    // release attaches its zip and judges nothing.
    "Check the tool's folder",
];

/// Where the package is in this repository. The mirror has it at its root.
const PACKAGE_PREFIX: &str = "apps/desktop/nexus-agent/";

/// Lines the rehearsal may add to a shared step: its artifacts are read once,
/// minutes later, so they are not kept for the default ninety days.
const REHEARSAL_EXTRA_LINES: &[&str] = &["retention-days: 1"];

const CHECKOUT: &str = "uses: actions/checkout";

/// Commands after which SwiftPM's checkouts of the package's dependencies
/// exist in a job's own copy of the repository.
const FETCHES: &[&str] = &["swift build", "swift test", "swift package resolve"];
const CHECKOUTS: &str = ".build/checkouts";

fn shared_steps(release_job: &str) -> &'static [&'static str] {
    match release_job {
        "build-macos" => &["Build for ${{ matrix.arch }}", "Upload arch binary"],
        "package" => &[
            "Download arm64 binary",
            "Download x86_64 binary",
            "Create universal binary",
            "Assemble .app bundles",
            "Install create-dmg",
            "Create DMGs",
            "Create ZIP for auto-updater",
            "Zip the tool's folder",
        ],
        _ => &[],
    }
}

/// The lines of one job, without the line that names it.
pub fn job_lines(text: &str, job: &str) -> Option<Vec<String>> {
    let lines: Vec<&str> = text.lines().collect();
    let target = format!("  {}:", job);
    let start = lines.iter().position(|&l| l == target)?;
    let mut end = lines.len();
    for (i, &line) in lines.iter().enumerate().skip(start + 1) {
        if let Some(rest) = line.strip_prefix("  ") {
            if rest.chars().next().is_some_and(|c| !c.is_whitespace()) {
                end = i;
                break;
            }
        }
    }
    Some(
        lines[start + 1..end]
            .iter()
            .map(|&s| s.to_string())
            .collect(),
    )
}

/// Stripped lines, without blank ones and comments.
pub fn significant<S: AsRef<str>>(lines: &[S]) -> Vec<String> {
    let mut out = Vec::new();
    for line in lines {
        let stripped = line.as_ref().trim();
        if !stripped.is_empty() && !stripped.starts_with('#') {
            out.push(stripped.to_string());
        }
    }
    out
}

/// A job's own settings, then its steps as (title, lines) in order.
pub fn split_job(lines: &[String]) -> (Vec<String>, Vec<(String, Vec<String>)>) {
    let mut header: Vec<String> = Vec::new();
    let mut steps: Vec<Vec<String>> = Vec::new();
    let mut in_steps = false;

    for line in lines {
        if line == "    steps:" {
            in_steps = true;
            continue;
        }
        if !in_steps {
            header.push(line.clone());
            continue;
        }
        if line.starts_with("      - ") {
            steps.push(vec![line.replacen("- ", "", 1)]);
        } else if let Some(current) = steps.last_mut() {
            current.push(line.clone());
        }
    }

    let mut titled = Vec::new();
    for step in &steps {
        let body = significant(step);
        let mut title = body.first().cloned().unwrap_or_default();
        for entry in &body {
            if let Some(rest) = entry.strip_prefix("name: ") {
                title = rest.to_string();
                break;
            }
        }
        titled.push((title, body));
    }
    (significant(&header), titled)
}

fn parse_version_digits_and_dots(s: &str) -> Option<&str> {
    let digits_len = s.bytes().take_while(|b| b.is_ascii_digit()).count();
    if digits_len == 0 {
        return None;
    }
    if s[digits_len..]
        .bytes()
        .all(|b| b.is_ascii_digit() || b == b'.')
    {
        Some(&s[..digits_len])
    } else {
        None
    }
}

fn normalise_uses_line(line: &str) -> String {
    let Some(after_uses) = line.strip_prefix("uses: ") else {
        return line.to_string();
    };
    let Some((action, rest)) = after_uses.split_once('@') else {
        return line.to_string();
    };
    if action.is_empty() || action.chars().any(|c| c.is_whitespace()) {
        return line.to_string();
    }

    // `^(uses: [^@\s]+)@v(\d+)[.\d]*$`
    if let Some(v_rest) = rest.strip_prefix('v') {
        if let Some(major) = parse_version_digits_and_dots(v_rest) {
            return format!("uses: {}@v{}", action, major);
        }
    }

    // `^(uses: [^@\s]+)@[0-9a-f]{40}\s+#\s*v(\d+)[.\d]*$`
    if rest.len() > 40 {
        let (sha, tail) = rest.split_at(40);
        if sha.bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f')) {
            let trimmed_ws = tail.trim_start_matches(char::is_whitespace);
            if trimmed_ws.len() < tail.len() {
                if let Some(after_hash) = trimmed_ws.strip_prefix('#') {
                    let after_hash_ws = after_hash.trim_start_matches(char::is_whitespace);
                    if let Some(v_rest) = after_hash_ws.strip_prefix('v') {
                        if let Some(major) = parse_version_digits_and_dots(v_rest) {
                            return format!("uses: {}@v{}", action, major);
                        }
                    }
                }
            }
        }
    }

    line.to_string()
}

/// A step's lines with what may differ between the two files taken out.
pub fn normalise(body: &[String], rehearsal: bool) -> Vec<String> {
    let mut out = Vec::new();
    for raw in body {
        let mut line = raw.clone();
        if rehearsal {
            if REHEARSAL_EXTRA_LINES.contains(&line.as_str()) {
                continue;
            }
            line = line.replace(PACKAGE_PREFIX, "");
        }
        line = normalise_uses_line(&line);
        if line.starts_with("VERSION=\"") && line.ends_with('"') && line.len() >= 10 {
            line = "VERSION=\"<version>\"".to_string();
        }
        out.push(line);
    }
    out
}

/// The lines of a job's settings that start with `key`.
pub fn setting(header: &[String], key: &str) -> Vec<String> {
    header
        .iter()
        .filter(|line| line.starts_with(key))
        .cloned()
        .collect()
}

fn py_str_repr(s: &str) -> String {
    if s.contains('\'') && !s.contains('"') {
        format!("\"{}\"", s)
    } else {
        format!("'{}'", s.replace('\\', "\\\\").replace('\'', "\\'"))
    }
}

fn py_list_repr<S: AsRef<str>>(items: &[S]) -> String {
    let inner: Vec<String> = items.iter().map(|s| py_str_repr(s.as_ref())).collect();
    format!("[{}]", inner.join(", "))
}

fn unified_diff(want: &[String], got: &[String], fromfile: &str, tofile: &str) -> String {
    // Simple LCS-based unified diff with context n=1 matching difflib.unified_diff(..., lineterm="", n=1)
    let n = want.len();
    let m = got.len();
    let mut dp = vec![vec![0usize; m + 1]; n + 1];
    for i in (0..n).rev() {
        for j in (0..m).rev() {
            if want[i] == got[j] {
                dp[i][j] = 1 + dp[i + 1][j + 1];
            } else {
                dp[i][j] = dp[i + 1][j].max(dp[i][j + 1]);
            }
        }
    }

    #[derive(Clone, Copy, PartialEq, Eq)]
    enum Op {
        Equal(usize, usize),
        Delete(usize),
        Insert(usize),
    }

    let mut ops = Vec::new();
    let (mut i, mut j) = (0, 0);
    while i < n && j < m {
        if want[i] == got[j] {
            ops.push(Op::Equal(i, j));
            i += 1;
            j += 1;
        } else if dp[i + 1][j] >= dp[i][j + 1] {
            ops.push(Op::Delete(i));
            i += 1;
        } else {
            ops.push(Op::Insert(j));
            j += 1;
        }
    }
    while i < n {
        ops.push(Op::Delete(i));
        i += 1;
    }
    while j < m {
        ops.push(Op::Insert(j));
        j += 1;
    }

    let mut out = vec![format!("--- {}", fromfile), format!("+++ {}", tofile)];
    let changed: Vec<bool> = ops
        .iter()
        .map(|op| !matches!(op, Op::Equal(_, _)))
        .collect();
    let mut idx = 0;
    while idx < ops.len() {
        if !changed[idx] {
            idx += 1;
            continue;
        }
        let start = idx.saturating_sub(1);
        let mut end = idx;
        while end + 1 < ops.len() {
            if changed[end + 1]
                || (end + 2 < ops.len() && changed[end + 2])
                || (end + 3 < ops.len() && changed[end + 3])
            {
                end += 1;
            } else {
                break;
            }
        }
        let end = (end + 2).min(ops.len());

        let mut a_start = None;
        let mut b_start = None;
        let mut a_count = 0usize;
        let mut b_count = 0usize;
        let mut hunk_lines = Vec::new();
        for op in &ops[start..end] {
            match *op {
                Op::Equal(ai, bi) => {
                    a_start.get_or_insert(ai + 1);
                    b_start.get_or_insert(bi + 1);
                    a_count += 1;
                    b_count += 1;
                    hunk_lines.push(format!(" {}", want[ai]));
                }
                Op::Delete(ai) => {
                    a_start.get_or_insert(ai + 1);
                    a_count += 1;
                    hunk_lines.push(format!("-{}", want[ai]));
                }
                Op::Insert(bi) => {
                    b_start.get_or_insert(bi + 1);
                    b_count += 1;
                    hunk_lines.push(format!("+{}", got[bi]));
                }
            }
        }
        let a_s = a_start.unwrap_or(1);
        let b_s = b_start.unwrap_or(1);
        let a_range = if a_count == 1 {
            format!("{}", a_s)
        } else {
            format!("{},{}", a_s, a_count)
        };
        let b_range = if b_count == 1 {
            format!("{}", b_s)
        } else {
            format!("{},{}", b_s, b_count)
        };
        out.push(format!("@@ -{} +{} @@", a_range, b_range));
        out.extend(hunk_lines);
        idx = end;
    }
    out.join("\n")
}

/// Every way the two files differ where they must not. Empty when in step.
pub fn compare(release_text: &str, rehearsal_text: &str) -> Vec<String> {
    let mut problems = Vec::new();
    for &(release_job, rehearsal_job) in JOBS {
        let mut sides: HashMap<&str, (Vec<String>, HashMap<String, Vec<String>>)> = HashMap::new();
        for (name, text, job, only) in [
            ("release.yml", release_text, release_job, RELEASE_ONLY),
            (
                "the rehearsal",
                rehearsal_text,
                rehearsal_job,
                REHEARSAL_ONLY,
            ),
        ] {
            let Some(lines) = job_lines(text, job) else {
                problems.push(format!("{} has no job `{}`", name, job));
                continue;
            };
            let (header, steps) = split_job(&lines);
            let kept: Vec<(String, Vec<String>)> = steps
                .into_iter()
                .filter(|(title, _)| {
                    !only.contains(&title.as_str()) && !title.starts_with(CHECKOUT)
                })
                .collect();
            let titles: Vec<String> = kept.iter().map(|(t, _)| t.clone()).collect();
            let expected = shared_steps(release_job);
            let expected_strings: Vec<String> = expected.iter().map(|s| (*s).to_string()).collect();
            if titles != expected_strings {
                problems.push(format!(
                    "{}, job `{}`: the steps are\n    {}\n  expected\n    {}\n  \
                    A step added to one file belongs in the other too, and in \
                    the lists at the top of this test.",
                    name,
                    job,
                    py_list_repr(&titles),
                    py_list_repr(&expected_strings)
                ));
            }
            sides.insert(name, (header, kept.into_iter().collect()));
        }
        if sides.len() != 2 {
            continue;
        }
        let (release_header, release_steps) = &sides["release.yml"];
        let (rehearsal_header, rehearsal_steps) = &sides["the rehearsal"];

        for key in ["runs-on:", "arch:"] {
            let ours = setting(rehearsal_header, key);
            let theirs = setting(release_header, key);
            if ours != theirs {
                problems.push(format!(
                    "job `{}`: release.yml has {}, the rehearsal's `{}` has {}",
                    release_job,
                    py_list_repr(&theirs),
                    rehearsal_job,
                    py_list_repr(&ours)
                ));
            }
        }

        for &title in shared_steps(release_job) {
            let (Some(rel_step), Some(reh_step)) =
                (release_steps.get(title), rehearsal_steps.get(title))
            else {
                continue;
            };
            let want = normalise(rel_step, false);
            let got = normalise(reh_step, true);
            if want != got {
                let diff = unified_diff(&want, &got, "release.yml", "the rehearsal");
                problems.push(format!("step `{}` differs:\n{}", title, diff));
            }
        }
    }
    problems
}

/// Problems when the lines this test exists for were not among those read.
pub fn looked_at_what_matters(release_text: &str) -> Vec<String> {
    let mut problems = Vec::new();
    let mut found: HashMap<String, Vec<String>> = HashMap::new();
    for &(job, _) in JOBS {
        if let Some(lines) = job_lines(release_text, job) {
            for (title, step_body) in split_job(&lines).1 {
                found.insert(title, step_body);
            }
        }
    }

    let body = |title: &str| -> &[String] { found.get(title).map_or(&[], Vec::as_slice) };
    let mut expect = |what: &str, ok: bool| {
        if !ok {
            problems.push(format!("release.yml: did not find {}", what));
        }
    };

    expect(
        "the `swift build` line",
        body("Build for ${{ matrix.arch }}")
            .iter()
            .any(|l| l == "swift build -c release --arch ${{ matrix.arch }}"),
    );

    let upload = body("Upload arch binary");
    let mut paths = Vec::new();
    if let Some(idx) = upload.iter().position(|l| l == "path: |") {
        for line in &upload[idx + 1..] {
            if line.contains(':') {
                break;
            }
            paths.push(line.as_str());
        }
    }
    expect(
        "three uploaded paths: the executable, the resource folder and the tool",
        paths.len() == 3,
    );
    expect(
        "`if-no-files-found: error` on the upload",
        upload.iter().any(|l| l == "if-no-files-found: error"),
    );
    for arch in ["arm64", "x86_64"] {
        let want_path = format!("path: /tmp/{}", arch);
        let step_name = format!("Download {} binary", arch);
        expect(
            &format!("where the {} artifact is downloaded to", arch),
            body(&step_name).iter().any(|l| l == &want_path),
        );
    }
    expect(
        "the `lipo -create` line",
        body("Create universal binary")
            .iter()
            .any(|l| l.starts_with("lipo -create")),
    );
    let calls = body("Assemble .app bundles")
        .iter()
        .filter(|l| l.starts_with("macos/scripts/bundle.sh "))
        .count();
    expect("three bundle.sh calls", calls == 3);
    expect(
        "the tool's zip, with the manifest at its top",
        body("Zip the tool's folder")
            .iter()
            .any(|l| l.starts_with("(cd \"$folder\" && zip -r -X")),
    );
    problems
}

/// Problems where a job reads SwiftPM's checkouts and never fetched them.
pub fn reads_only_what_it_fetched(text: &str, name: &str, jobs: &[&str]) -> Vec<String> {
    let mut problems = Vec::new();
    for &job in jobs {
        let Some(lines) = job_lines(text, job) else {
            continue;
        };
        let mut fetched = false;
        for (title, body) in split_job(&lines).1 {
            for line in body {
                if FETCHES.iter().any(|f| line.starts_with(f)) {
                    fetched = true;
                } else if line.contains(CHECKOUTS) && !fetched {
                    problems.push(format!(
                        "{}, job `{}`, step `{}` reads {}, which nothing in \
                        that job has fetched: run `swift package resolve` first",
                        name, job, title, CHECKOUTS
                    ));
                    break;
                }
            }
        }
    }
    problems
}

fn run_self_tests() {
    // 1. normalise strips package prefix, retention-days, action SHA pins, and VERSION
    let raw = vec![
        "uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2"
            .to_string(),
        "uses: actions/download-artifact@v8.1.0".to_string(),
        "retention-days: 1".to_string(),
        "cd apps/desktop/nexus-agent/macos".to_string(),
        "VERSION=\"0.0.0-rehearsal\"".to_string(),
    ];
    let norm = normalise(&raw, true);
    assert_eq!(
        norm,
        vec![
            "uses: actions/upload-artifact@v7",
            "uses: actions/download-artifact@v8",
            "cd macos",
            "VERSION=\"<version>\"",
        ]
    );

    // 2. reads_only_what_it_fetched catches reading .build/checkouts without swift build/resolve
    let bad_wf = "\
jobs:
  package:
    runs-on: macos-15
    steps:
      - name: Grab dependency
        run: |
          cp .build/checkouts/foo/bar /tmp/
";
    let errs = reads_only_what_it_fetched(bad_wf, "release.yml", &["package"]);
    assert_eq!(errs.len(), 1);
    assert!(errs[0].contains("reads .build/checkouts, which nothing in that job has fetched"));

    let good_wf = "\
jobs:
  package:
    runs-on: macos-15
    steps:
      - name: Resolve
        run: |
          swift package resolve
      - name: Grab dependency
        run: |
          cp .build/checkouts/foo/bar /tmp/
";
    assert!(reads_only_what_it_fetched(good_wf, "release.yml", &["package"]).is_empty());
}

fn main() -> ExitCode {
    run_self_tests();

    let argv: Vec<String> = std::env::args().collect();
    if argv.len() != 3 {
        print!("{}", DOC);
        return ExitCode::from(2);
    }
    let release_text = fs::read_to_string(&argv[1]).expect("read release workflow");
    let rehearsal_text = fs::read_to_string(&argv[2]).expect("read rehearsal workflow");

    let release_jobs: Vec<&str> = JOBS.iter().map(|&(rel, _)| rel).collect();
    let rehearsal_jobs: Vec<&str> = JOBS.iter().map(|&(_, reh)| reh).collect();

    let mut problems = Vec::new();
    problems.extend(looked_at_what_matters(&release_text));
    problems.extend(compare(&release_text, &rehearsal_text));
    problems.extend(reads_only_what_it_fetched(
        &release_text,
        "release.yml",
        &release_jobs,
    ));
    problems.extend(reads_only_what_it_fetched(
        &rehearsal_text,
        "the rehearsal",
        &rehearsal_jobs,
    ));

    if !problems.is_empty() {
        println!(
            "The release ({}) and its rehearsal ({}) are out of step:\n",
            argv[1], argv[2]
        );
        for problem in problems {
            println!("- {}\n", problem);
        }
        println!(
            "Make the same change in both files. The rehearsal may differ only \
            in the path to the package ({}), in pinning actions to commits, \
            and in the version it packages.",
            PACKAGE_PREFIX
        );
        return ExitCode::from(1);
    }

    let shared: usize = JOBS.iter().map(|&(rel, _)| shared_steps(rel).len()).sum();
    println!("in step: {} shared steps in {} jobs", shared, JOBS.len());
    ExitCode::SUCCESS
}
