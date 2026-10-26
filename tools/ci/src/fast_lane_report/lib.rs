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

//! fast-lane-report.sh — weekly numbers for the agent fast lane (#3418).

use shell_compat::{capture, cat, env_or, err, mktemp_dir, out, status, subst};
use std::process::Command;

fn parse_days(args: &[Vec<u8>]) -> Option<Vec<u8>> {
    let days = if args.is_empty() {
        b"7".to_vec()
    } else {
        args[0].clone()
    };
    if days.is_empty() || !days.iter().all(|&c| c.is_ascii_digit()) {
        return None;
    }
    Some(days)
}

fn compute_since(days: &[u8]) -> Vec<u8> {
    let r = capture(
        44,
        Command::new("date")
            .arg("-u")
            .arg(shell_compat::os(&cat(&[b"-v-", days, b"d"])))
            .arg("+%Y-%m-%dT%H:%M:%SZ"),
    );
    if r.ok() {
        return subst(r.stdout);
    }
    let r = capture(
        44,
        Command::new("date")
            .arg("-u")
            .arg("-d")
            .arg(shell_compat::os(&cat(&[days, b" days ago"])))
            .arg("+%Y-%m-%dT%H:%M:%SZ"),
    );
    subst(r.stdout)
}

const RUNS_JQ: &str = r#".workflow_runs[] | select(.name == "Presubmit" or .name == "CI")
          | {name, conclusion, branch: .head_branch,
             minutes: (((.updated_at | fromdate) - (.run_started_at | fromdate)) / 60)}"#;

const COMBINE_JQ: &str = r#"($queue[0] | map(select(.conclusion == "failure")
   | (.branch | capture("^gh-readonly-queue/main/pr-(?<n>[0-9]+)-").n | tonumber)) | unique) as $failed
| map(. + {
    fast: ([.labels[].name] | index("agent-fast-lane") != null),
    queue_failed: (.number as $n | $failed | index($n) != null),
    open_to_merged: (((.mergedAt | fromdate) - (.createdAt | fromdate)) / 60),
    pr_minutes: (.headRefName as $b | [$prruns[0][] | select(.branch == $b) | .minutes] | add // 0)
  })"#;

const REPORT_JQ: &str = r#"def pct(p): if length == 0 then "-" else (sort | .[((length - 1) * p | floor)] | floor | tostring) end;
. as $all
| (["group", "PRs", "queue-failed", "rate", "open->merged median (min)", "p90", "PR-lane CI min/PR"] | @tsv),
  ([true, false][] as $f
   | [$all[] | select(.fast == $f)] as $g
   | [ (if $f then "agent-fast-lane" else "all others" end),
       ($g | length),
       ([$g[] | select(.queue_failed)] | length),
       (if ($g | length) == 0 then "-" else "\(([$g[] | select(.queue_failed)] | length) * 1000 / ($g | length) | floor / 10)%" end),
       ([$g[].open_to_merged] | pct(0.5)),
       ([$g[].open_to_merged] | pct(0.9)),
       (if ($g | length) == 0 then "-" else ([$g[].pr_minutes] | add / length | floor | tostring) end)
     ] | @tsv)"#;

const FAILURES_JQ: &str = r#"[.[] | select(.fast and .queue_failed) | "  #\(.number)"] | if length == 0 then ["  none"] else . end | .[]"#;

fn fetch_runs(repo: &[u8], event: &str, since: &[u8], out_file: &[u8]) -> i32 {
    let url = cat(&[
        b"repos/",
        repo,
        b"/actions/runs?event=",
        event.as_bytes(),
        b"&created=>=",
        since,
        b"&per_page=100",
    ]);
    let rc = status(
        58,
        Command::new("gh")
            .arg("api")
            .arg("--paginate")
            .arg(shell_compat::os(&url))
            .arg("--jq")
            .arg(RUNS_JQ)
            .stdout(
                std::fs::File::create(shell_compat::path(out_file)).expect("create runs output"),
            ),
        false,
    );
    if rc != 0 {
        return rc;
    }
    let raw = std::fs::read(shell_compat::path(out_file)).unwrap_or_default();
    let rc = shell_compat::status_with_input(
        58,
        Command::new("jq")
            .arg("-s")
            .arg(".")
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::inherit()),
        &raw,
        false,
    );
    if rc == 0 {
        let r = capture(
            58,
            Command::new("jq").arg("-s").arg(".").stdin({
                let f = std::fs::File::open(shell_compat::path(out_file)).unwrap();
                std::process::Stdio::from(f)
            }),
        );
        let _ = shell_compat::write_file(out_file, &r.stdout, 0o644);
    }
    0
}

pub fn run(args: &[Vec<u8>]) -> i32 {
    let days = match parse_days(args) {
        Some(d) => d,
        None => {
            err(b"usage: fast-lane-report.sh [days]\n");
            return 2;
        }
    };
    let repo = env_or("REPO", b"VitruvianSoftware/vitruvian-core");
    let since = compute_since(&days);

    let tmp = match mktemp_dir() {
        Ok(t) => t,
        Err(_) => {
            err(b"could not create temp directory\n");
            return 1;
        }
    };

    let prs_json = cat(&[&tmp, b"/prs.json"]);
    let queue_json = cat(&[&tmp, b"/queue.json"]);
    let pr_runs_json = cat(&[&tmp, b"/pr-runs.json"]);
    let all_json = cat(&[&tmp, b"/all.json"]);

    let since_date = match since.iter().position(|&c| c == b'T') {
        Some(i) => &since[..i],
        None => &since,
    };

    let rc = status(
        49,
        Command::new("gh")
            .arg("pr")
            .arg("list")
            .arg("--repo")
            .arg(shell_compat::os(&repo))
            .arg("--state")
            .arg("merged")
            .arg("--limit")
            .arg("1000")
            .arg("--search")
            .arg(shell_compat::os(&cat(&[b"merged:>=", since_date])))
            .arg("--json")
            .arg("number,headRefName,labels,createdAt,mergedAt")
            .stdout(std::fs::File::create(shell_compat::path(&prs_json)).expect("create prs.json")),
        false,
    );
    if rc != 0 {
        err(b"gh pr list failed\n");
        let _ = std::fs::remove_dir_all(shell_compat::path(&tmp));
        return 1;
    }

    let rc = fetch_runs(&repo, "merge_group", &since, &queue_json);
    if rc != 0 {
        err(b"fetching merge_group runs failed\n");
        let _ = std::fs::remove_dir_all(shell_compat::path(&tmp));
        return 1;
    }
    let rc = fetch_runs(&repo, "pull_request", &since, &pr_runs_json);
    if rc != 0 {
        err(b"fetching pull_request runs failed\n");
        let _ = std::fs::remove_dir_all(shell_compat::path(&tmp));
        return 1;
    }

    let rc = status(
        70,
        Command::new("jq")
            .arg("--slurpfile")
            .arg("queue")
            .arg(shell_compat::os(&queue_json))
            .arg("--slurpfile")
            .arg("prruns")
            .arg(shell_compat::os(&pr_runs_json))
            .arg(COMBINE_JQ)
            .arg(shell_compat::os(&prs_json))
            .stdout(std::fs::File::create(shell_compat::path(&all_json)).expect("create all.json")),
        false,
    );
    if rc != 0 {
        err(b"jq combine step failed\n");
        let _ = std::fs::remove_dir_all(shell_compat::path(&tmp));
        return 1;
    }

    let r = capture(
        86,
        Command::new("jq")
            .arg("-r")
            .arg(REPORT_JQ)
            .arg(shell_compat::os(&all_json)),
    );
    if !r.ok() {
        err(b"jq report step failed\n");
        let _ = std::fs::remove_dir_all(shell_compat::path(&tmp));
        return 1;
    }

    let col = capture(
        86,
        Command::new("column")
            .arg("-t")
            .arg("-s")
            .arg("\t")
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped()),
    );
    let table = if col.status == 127 {
        r.stdout.clone()
    } else {
        let mut child = Command::new("column")
            .arg("-t")
            .arg("-s")
            .arg("\t")
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::null())
            .spawn()
            .unwrap();
        {
            use std::io::Write;
            let mut sin = child.stdin.take().unwrap();
            let _ = sin.write_all(&r.stdout);
        }
        match child.wait_with_output() {
            Ok(o) if o.status.success() => o.stdout,
            _ => r.stdout.clone(),
        }
    };
    out(&table);
    out(b"\n");

    out(b"fast-lane PRs that failed in the merge queue (note each on #3418):\n");
    let r = capture(
        89,
        Command::new("jq")
            .arg("-r")
            .arg(FAILURES_JQ)
            .arg(shell_compat::os(&all_json)),
    );
    out(&r.stdout);
    if !r.stdout.ends_with(b"\n") {
        out(b"\n");
    }

    out(b"\n");
    out(&cat(&[
        b"window: merged since ",
        &since,
        b" (",
        &days,
        b" days); CI minutes are wall-clock per run, not billed.\n",
    ]));

    let _ = std::fs::remove_dir_all(shell_compat::path(&tmp));
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_days_default_is_7() {
        let d = parse_days(&[]);
        assert_eq!(d, Some(b"7".to_vec()));
    }

    #[test]
    fn parse_days_valid_number() {
        let d = parse_days(&[b"14".to_vec()]);
        assert_eq!(d, Some(b"14".to_vec()));
    }

    #[test]
    fn parse_days_single_digit() {
        let d = parse_days(&[b"1".to_vec()]);
        assert_eq!(d, Some(b"1".to_vec()));
    }

    #[test]
    fn parse_days_rejects_non_numeric() {
        assert_eq!(parse_days(&[b"abc".to_vec()]), None);
    }

    #[test]
    fn parse_days_rejects_empty_string() {
        assert_eq!(parse_days(&[b"".to_vec()]), None);
    }

    #[test]
    fn parse_days_rejects_negative() {
        assert_eq!(parse_days(&[b"-7".to_vec()]), None);
    }

    #[test]
    fn parse_days_rejects_decimal() {
        assert_eq!(parse_days(&[b"7.5".to_vec()]), None);
    }

    #[test]
    fn parse_days_rejects_with_spaces() {
        assert_eq!(parse_days(&[b"7 ".to_vec()]), None);
    }

    #[test]
    fn combine_jq_is_syntactically_valid() {
        let r = std::process::Command::new("jq")
            .arg("--argjson")
            .arg("queue")
            .arg("[[]]")
            .arg("--argjson")
            .arg("prruns")
            .arg("[[]]")
            .arg(COMBINE_JQ)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::piped())
            .spawn();
        match r {
            Ok(mut child) => {
                use std::io::Write;
                if let Some(mut sin) = child.stdin.take() {
                    let _ = sin.write_all(b"[]");
                }
                let o = child.wait_with_output().unwrap();
                assert!(
                    o.status.success(),
                    "COMBINE_JQ is not valid jq: {}",
                    String::from_utf8_lossy(&o.stderr)
                );
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                // jq not on PATH, skip
            }
            Err(e) => panic!("unexpected error: {}", e),
        }
    }

    #[test]
    fn report_jq_is_syntactically_valid() {
        let r = std::process::Command::new("jq")
            .arg("-r")
            .arg(REPORT_JQ)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::piped())
            .spawn();
        match r {
            Ok(mut child) => {
                use std::io::Write;
                if let Some(mut sin) = child.stdin.take() {
                    let _ = sin.write_all(b"[]");
                }
                let o = child.wait_with_output().unwrap();
                assert!(
                    o.status.success(),
                    "REPORT_JQ is not valid jq: {}",
                    String::from_utf8_lossy(&o.stderr)
                );
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => panic!("unexpected error: {}", e),
        }
    }

    #[test]
    fn failures_jq_is_syntactically_valid() {
        let r = std::process::Command::new("jq")
            .arg("-r")
            .arg(FAILURES_JQ)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::piped())
            .spawn();
        match r {
            Ok(mut child) => {
                use std::io::Write;
                if let Some(mut sin) = child.stdin.take() {
                    let _ = sin.write_all(b"[]");
                }
                let o = child.wait_with_output().unwrap();
                assert!(
                    o.status.success(),
                    "FAILURES_JQ is not valid jq: {}",
                    String::from_utf8_lossy(&o.stderr)
                );
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => panic!("unexpected error: {}", e),
        }
    }
}
