// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

use std::path::Path;
use std::process::Command;

pub fn check_beta_publish(repo_dir: &Path, tag: &str, new_sha: &str) -> i32 {
    if tag.is_empty() || new_sha.is_empty() {
        eprintln!("usage: beta-publish-guard.sh <tag> <new-sha>");
        return 2;
    }

    if !git_ok(
        repo_dir,
        &[
            "rev-parse",
            "-q",
            "--verify",
            &format!("{}^{{commit}}", new_sha),
        ],
    ) {
        eprintln!(
            "beta-publish-guard: {} is not a commit in this clone",
            new_sha
        );
        return 2;
    }

    let existing = resolve_existing_tag_sha(repo_dir, tag);
    if existing.is_empty() {
        println!(
            "beta-publish-guard: {} does not exist yet; publishing {}",
            tag, new_sha
        );
        return 0;
    }

    if !git_ok(
        repo_dir,
        &["cat-file", "-e", &format!("{}^{{commit}}", existing)],
    ) {
        let _ = Command::new("git")
            .current_dir(repo_dir)
            .args([
                "fetch",
                "--no-tags",
                "--depth=200",
                "origin",
                &format!("+refs/tags/{}:refs/tags/{}", tag, tag),
                "main",
            ])
            .output();
    }

    if !git_ok(
        repo_dir,
        &["cat-file", "-e", &format!("{}^{{commit}}", existing)],
    ) {
        println!(
            "beta-publish-guard: {} ({}) not reachable in shallow clone; publishing {}",
            tag, existing, new_sha
        );
        return 0;
    }

    if git_ok(
        repo_dir,
        &["merge-base", "--is-ancestor", new_sha, &existing],
    ) {
        println!(
            "beta-publish-guard: {} is already at {} (at or ahead of {}); skipping",
            tag, existing, new_sha
        );
        return 10;
    }

    println!(
        "beta-publish-guard: advancing {} from {} to {}",
        tag, existing, new_sha
    );
    0
}

fn resolve_existing_tag_sha(repo_dir: &Path, tag: &str) -> String {
    if let Some(out) = git_stdout(
        repo_dir,
        &[
            "rev-parse",
            "-q",
            "--verify",
            &format!("refs/tags/{}^{{commit}}", tag),
        ],
    ) {
        let trimmed = out.trim();
        if !trimmed.is_empty() {
            return trimmed.to_string();
        }
    }

    if let Some(out) = git_stdout(
        repo_dir,
        &[
            "ls-remote",
            "--tags",
            "origin",
            &format!("refs/tags/{}^{{}}", tag),
            &format!("refs/tags/{}", tag),
        ],
    ) {
        if let Some(last_line) = out.lines().last() {
            if let Some(first_field) = last_line.split_whitespace().next() {
                return first_field.to_string();
            }
        }
    }

    String::new()
}

fn git_ok(repo_dir: &Path, args: &[&str]) -> bool {
    Command::new("git")
        .current_dir(repo_dir)
        .args(args)
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

fn git_stdout(repo_dir: &Path, args: &[&str]) -> Option<String> {
    let out = Command::new("git")
        .current_dir(repo_dir)
        .args(args)
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&out.stdout).to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;
    use std::fs;

    fn run_git(dir: &Path, args: &[&str]) -> String {
        let out = Command::new("git")
            .current_dir(dir)
            .args(args)
            .output()
            .expect("git");
        assert!(
            out.status.success(),
            "git {:?} failed: {}",
            args,
            String::from_utf8_lossy(&out.stderr)
        );
        String::from_utf8_lossy(&out.stdout).trim().to_string()
    }

    #[test]
    fn test_all_beta_publish_guard_cases() {
        let tmp = env::temp_dir().join("test_beta_publish_guard_rs");
        let _ = fs::remove_dir_all(&tmp);
        let origin = tmp.join("origin.git");
        let work = tmp.join("work");
        fs::create_dir_all(&tmp).unwrap();

        run_git(&tmp, &["init", "--bare", "-q", origin.to_str().unwrap()]);
        run_git(
            &tmp,
            &[
                "clone",
                "-q",
                origin.to_str().unwrap(),
                work.to_str().unwrap(),
            ],
        );
        run_git(&work, &["config", "user.email", "test@vitruvian.local"]);
        run_git(&work, &["config", "user.name", "Test"]);
        run_git(&work, &["checkout", "-q", "-b", "main"]);

        let commit = |n: u32| -> String {
            fs::write(work.join("f"), format!("{}\n", n)).unwrap();
            run_git(&work, &["add", "f"]);
            run_git(&work, &["commit", "-q", "-m", &format!("c{}", n)]);
            run_git(&work, &["rev-parse", "HEAD"])
        };

        let c1 = commit(1);
        let c2 = commit(2);
        let c3 = commit(3);
        run_git(&work, &["push", "-q", "origin", "main"]);

        // 1. Tag does not exist yet -> exit 0
        assert_eq!(check_beta_publish(&work, "vitruvian-beta-latest", &c2), 0);

        // 2. Tag at c1, publishing c2 (newer descendant) -> exit 0
        run_git(&work, &["tag", "-f", "vitruvian-beta-latest", &c1]);
        run_git(
            &work,
            &["push", "-q", "-f", "origin", "vitruvian-beta-latest"],
        );
        assert_eq!(check_beta_publish(&work, "vitruvian-beta-latest", &c2), 0);

        // 3. Tag at c3, publishing c2 (older ancestor) -> exit 10
        run_git(&work, &["tag", "-f", "vitruvian-beta-latest", &c3]);
        run_git(
            &work,
            &["push", "-q", "-f", "origin", "vitruvian-beta-latest"],
        );
        assert_eq!(check_beta_publish(&work, "vitruvian-beta-latest", &c2), 10);

        // 4. Tag already at c2, publishing c2 -> exit 10
        run_git(&work, &["tag", "-f", "vitruvian-beta-latest", &c2]);
        run_git(
            &work,
            &["push", "-q", "-f", "origin", "vitruvian-beta-latest"],
        );
        assert_eq!(check_beta_publish(&work, "vitruvian-beta-latest", &c2), 10);

        // 5. Annotated tag on origin only -> still refuses older commit (exit 10)
        run_git(
            &work,
            &[
                "tag",
                "-a",
                "-f",
                "-m",
                "beta",
                "vitruvian-beta-latest",
                &c3,
            ],
        );
        run_git(
            &work,
            &["push", "-q", "-f", "origin", "vitruvian-beta-latest"],
        );
        run_git(&work, &["tag", "-d", "vitruvian-beta-latest"]);
        assert_eq!(check_beta_publish(&work, "vitruvian-beta-latest", &c1), 10);

        // 6. Missing argument -> exit 2
        assert_eq!(check_beta_publish(&work, "vitruvian-beta-latest", ""), 2);

        // 7. Unknown SHA -> exit 2
        assert_eq!(
            check_beta_publish(
                &work,
                "vitruvian-beta-latest",
                "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
            ),
            2
        );

        let _ = fs::remove_dir_all(&tmp);
    }
}
