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

//! //tools/ci:gitops_values_render — `helm template` over every remote chart that an
//! ArgoCD Application pairs with a values file kept in this repo, with the
//! chart's own values.schema.json enforced.

use shell_compat::{
    capture, cat, env, err, is_file, mktemp_dir, os, out, status, status_with_input, subst,
};
use std::process::Command;

const DISCOVER_PY: &[u8] = br#"import glob, sys, yaml

out = []


def specs_of(doc):
    kind = doc.get("kind")
    if kind == "Application":
        return [doc.get("spec", {})]
    if kind == "ApplicationSet":
        return [doc.get("spec", {}).get("template", {}).get("spec", {})]
    return []


for path in glob.glob("gitops/**/*.yaml", recursive=True):
    try:
        docs = list(yaml.safe_load_all(open(path)))
    except Exception:
        continue
    for doc in docs:
        if not isinstance(doc, dict):
            continue
        for spec in specs_of(doc):
            if not isinstance(spec, dict):
                continue
            sources = spec.get("sources") or (
                [spec["source"]] if spec.get("source") else []
            )
            chart = repo = rev = None
            value_files = []
            for src in sources:
                if not isinstance(src, dict):
                    continue
                if src.get("chart"):
                    chart = src["chart"]
                    repo = src.get("repoURL")
                    rev = src.get("targetRevision")
                for vf in (src.get("helm") or {}).get("valueFiles") or []:
                    value_files.append(vf.split("/", 1)[1] if vf.startswith("$values/") else vf)
            if chart and repo and rev and value_files:
                name = doc.get("metadata", {}).get("name", "?")
                for vf in value_files:
                    out.append("\t".join([name, repo, chart, str(rev), vf]))

with open(sys.argv[1], "w") as fh:
    fh.write("\n".join(sorted(set(out))) + ("\n" if out else ""))
"#;

fn fail(msg: &[u8]) -> i32 {
    err(&cat(&[b"gitops-values-render: ", msg, b"\n"]));
    1
}

fn is_http(repo: &[u8]) -> bool {
    repo.starts_with(b"http://") || repo.starts_with(b"https://")
}

fn host_of(repo: &[u8]) -> Vec<u8> {
    let s = if let Some(rest) = strip_prefix(repo, b"oci://") {
        rest
    } else {
        repo
    };
    match s.iter().position(|&c| c == b'/') {
        Some(i) => s[..i].to_vec(),
        None => s.to_vec(),
    }
}

fn strip_prefix<'a>(hay: &'a [u8], prefix: &[u8]) -> Option<&'a [u8]> {
    if hay.len() >= prefix.len() && &hay[..prefix.len()] == prefix {
        Some(&hay[prefix.len()..])
    } else {
        None
    }
}

fn oci_login(host: &[u8], work: &[u8]) -> bool {
    let marker = cat(&[work, b"/.logged-in-", host]);
    if is_file(&marker) {
        return true;
    }

    if let Some(token) = env("GITHUB_TOKEN") {
        if !token.is_empty() {
            let actor = shell_compat::env_or("GITHUB_ACTOR", b"x-access-token");
            let mut cmd = Command::new("helm");
            cmd.arg("registry")
                .arg("login")
                .arg(os(host))
                .arg("-u")
                .arg(os(&actor))
                .arg("--password-stdin")
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null());
            if status_with_input(0, &mut cmd, &token, true) == 0 {
                let _ = shell_compat::write_file(&marker, b"", 0o644);
                return true;
            }
        }
    }

    if shell_compat::which(b"gh").is_some() {
        let r = capture(0, Command::new("gh").arg("auth").arg("token"));
        if r.ok() {
            let gh_token = subst(r.stdout);
            if !gh_token.is_empty() {
                let user_r = capture(
                    0,
                    Command::new("gh")
                        .arg("api")
                        .arg("user")
                        .arg("--jq")
                        .arg(".login"),
                );
                let user = if user_r.ok() && !user_r.stdout.is_empty() {
                    subst(user_r.stdout)
                } else {
                    b"x-access-token".to_vec()
                };
                let mut cmd = Command::new("helm");
                cmd.arg("registry")
                    .arg("login")
                    .arg(os(host))
                    .arg("-u")
                    .arg(os(&user))
                    .arg("--password-stdin")
                    .stdout(std::process::Stdio::null())
                    .stderr(std::process::Stdio::null());
                if status_with_input(0, &mut cmd, &gh_token, true) == 0 {
                    let _ = shell_compat::write_file(&marker, b"", 0o644);
                    return true;
                }
            }
        }
    }

    err(&cat(&[
        b"gitops-values-render: no credential for ",
        host,
        b"; set GITHUB_TOKEN or run `gh auth login`\n",
    ]));
    false
}

fn pull_chart(repo: &[u8], chart: &[u8], rev: &[u8], dest: &[u8], work: &[u8]) -> bool {
    for attempt in 1..=3 {
        let _ = std::fs::remove_dir_all(shell_compat::path(dest));
        let _ = shell_compat::mkdir_p(dest);

        let rc = if is_http(repo) {
            status(
                0,
                Command::new("helm")
                    .arg("pull")
                    .arg(os(chart))
                    .arg("--repo")
                    .arg(os(repo))
                    .arg("--version")
                    .arg(os(rev))
                    .arg("--untar")
                    .arg("--untardir")
                    .arg(os(dest))
                    .stdout(std::process::Stdio::null())
                    .stderr(std::process::Stdio::null()),
                true,
            )
        } else {
            if !oci_login(&host_of(repo), work) {
                return false;
            }
            let oci_ref = cat(&[b"oci://", repo, b"/", chart]);
            status(
                0,
                Command::new("helm")
                    .arg("pull")
                    .arg(os(&oci_ref))
                    .arg("--version")
                    .arg(os(rev))
                    .arg("--untar")
                    .arg("--untardir")
                    .arg(os(dest))
                    .stdout(std::process::Stdio::null())
                    .stderr(std::process::Stdio::null()),
                true,
            )
        };

        if rc == 0 {
            return true;
        }

        err(&cat(&[
            b"gitops-values-render: pull of ",
            chart,
            b"@",
            rev,
            b" failed (attempt ",
            format!("{}", attempt).as_bytes(),
            b"/3), retrying...\n",
        ]));
        if attempt < 3 {
            std::thread::sleep(std::time::Duration::from_secs(5));
        }
    }
    false
}

fn find_chartdir(dest: &[u8], chart: &[u8]) -> Option<Vec<u8>> {
    let candidate = cat(&[dest, b"/", chart]);
    if shell_compat::is_dir(&candidate) {
        return Some(candidate);
    }
    let r = capture(
        0,
        Command::new("find")
            .arg(os(dest))
            .arg("-maxdepth")
            .arg("2")
            .arg("-name")
            .arg("Chart.yaml")
            .arg("-print")
            .arg("-quit"),
    );
    let found = subst(r.stdout);
    if found.is_empty() {
        return None;
    }
    let dir = shell_compat::dirname(&found);
    if shell_compat::is_dir(&dir) {
        Some(dir)
    } else {
        None
    }
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    // Under `bazel run` the working directory is the runfiles tree, where no
    // Application is; scan the workspace instead. CI runs it from the checkout.
    if let Some(ws) = shell_compat::env("BUILD_WORKSPACE_DIRECTORY") {
        if !ws.is_empty() && std::env::set_current_dir(shell_compat::path(&ws)).is_err() {
            return fail(b"cannot cd to BUILD_WORKSPACE_DIRECTORY");
        }
    }
    if shell_compat::which(b"helm").is_none() {
        return fail(b"helm not found on PATH");
    }
    if shell_compat::which(b"python3").is_none() {
        return fail(b"python3 not found on PATH");
    }
    if status(
        0,
        Command::new("python3")
            .arg("-c")
            .arg("import yaml")
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null()),
        true,
    ) != 0
    {
        return fail(
            b"PyYAML not importable -- `pip install pyyaml`. The discovery step below \
parses the gitops tree; without it this gate would find no pairs and pass vacuously.",
        );
    }

    let work = match mktemp_dir() {
        Ok(d) => d,
        Err(e) => {
            err(&cat(&[
                b"gitops-values-render: mktemp failed: ",
                e.to_string().as_bytes(),
                b"\n",
            ]));
            return 1;
        }
    };

    let pairs_file = cat(&[&work, b"/pairs.tsv"]);

    let rc = status_with_input(
        0,
        Command::new("python3").arg("-").arg(os(&pairs_file)),
        DISCOVER_PY,
        false,
    );
    if rc != 0 {
        err(b"gitops-values-render: python3 discovery script failed\n");
        let _ = std::fs::remove_dir_all(shell_compat::path(&work));
        return 1;
    }

    let pairs_data = match std::fs::read(shell_compat::path(&pairs_file)) {
        Ok(d) => d,
        Err(_) => Vec::new(),
    };
    if pairs_data.is_empty() {
        let _ = std::fs::remove_dir_all(shell_compat::path(&work));
        return fail(
            b"discovered no chart+values pairs -- the discovery query \
matched nothing, which means this gate is inert. Fix the query, do not delete it.",
        );
    }

    let pair_count = pairs_data
        .split(|&c| c == b'\n')
        .filter(|l| !l.is_empty())
        .count();
    out(&cat(&[
        b"gitops-values-render: ",
        format!("{}", pair_count).as_bytes(),
        b" chart+values pair(s) to render\n",
    ]));

    let mut rc = 0i32;

    for line in shell_compat::lines(&pairs_data) {
        if line.is_empty() {
            continue;
        }
        let fields = shell_compat::read_fields(&line, b"\t", 5);
        if fields.len() < 5 {
            continue;
        }
        let app = &fields[0];
        let repo = &fields[1];
        let chart = &fields[2];
        let rev = &fields[3];
        let values = &fields[4];

        if app.is_empty() {
            continue;
        }

        if !is_file(values) {
            let _ = std::fs::remove_dir_all(shell_compat::path(&work));
            return fail(&cat(&[app, b": values file ", values, b" does not exist"]));
        }

        let dest = cat(&[&work, b"/", app]);
        if !pull_chart(repo, chart, rev, &dest, &work) {
            let _ = std::fs::remove_dir_all(shell_compat::path(&work));
            return fail(&cat(&[
                app,
                b": could not pull ",
                chart,
                b" ",
                rev,
                b" from ",
                repo,
                b" after 3 attempts",
            ]));
        }

        let chartdir = match find_chartdir(&dest, chart) {
            Some(d) => d,
            None => {
                let _ = std::fs::remove_dir_all(shell_compat::path(&work));
                return fail(&cat(&[
                    app,
                    b": could not locate the unpacked chart under ",
                    &dest,
                ]));
            }
        };

        let err_file = cat(&[&work, b"/", app, b".err"]);
        let err_f = match std::fs::File::create(shell_compat::path(&err_file)) {
            Ok(f) => f,
            Err(_) => {
                let _ = std::fs::remove_dir_all(shell_compat::path(&work));
                return fail(b"could not create error capture file");
            }
        };

        let helm_rc = status(
            0,
            Command::new("helm")
                .arg("template")
                .arg(os(&chartdir))
                .arg("--name-template")
                .arg(os(app))
                .arg("--namespace")
                .arg(os(app))
                .arg("--kube-version")
                .arg("1.35.3")
                .arg("--values")
                .arg(os(values))
                .arg("--include-crds")
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::from(err_f)),
            false,
        );

        if helm_rc == 0 {
            out(&cat(&[b"  ok   ", app, b"  (", chart, b"@", rev, b")\n"]));
        } else {
            err(&cat(&[
                b"  FAIL ",
                app,
                b"  (",
                chart,
                b"@",
                rev,
                b") values=",
                values,
                b"\n",
            ]));
            if let Ok(errtxt) = std::fs::read(shell_compat::path(&err_file)) {
                let indented = shell_compat::indent(&errtxt);
                let prefixed: Vec<u8> = indented.iter().map(|&c| c).collect();
                let _ = prefixed;
                for eline in shell_compat::lines(&errtxt) {
                    err(&cat(&[b"       ", &eline, b"\n"]));
                }
            }
            rc = 1;
        }
    }

    if rc != 0 {
        let _ = std::fs::remove_dir_all(shell_compat::path(&work));
        return fail(
            b"at least one Application's values do not render against its chart. \
ArgoCD reports this as ComparisonError and STOPS DEPLOYING that app entirely -- \
including unrelated changes queued behind it.",
        );
    }

    out(b"gitops-values-render: all pairs render\n");
    let _ = std::fs::remove_dir_all(shell_compat::path(&work));
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn is_http_detects_schemes() {
        assert!(is_http(b"http://example.com/charts"));
        assert!(is_http(b"https://charts.example.com"));
        assert!(!is_http(b"ghcr.io/org/charts"));
        assert!(!is_http(b"oci://ghcr.io/org/charts"));
        assert!(!is_http(b""));
    }

    #[test]
    fn host_of_extracts_registry_host() {
        assert_eq!(host_of(b"ghcr.io/org/charts"), b"ghcr.io");
        assert_eq!(host_of(b"ghcr.io"), b"ghcr.io");
        assert_eq!(
            host_of(b"registry.example.com/foo/bar"),
            b"registry.example.com"
        );
    }

    #[test]
    fn strip_prefix_works() {
        assert_eq!(
            strip_prefix(b"oci://ghcr.io", b"oci://"),
            Some(&b"ghcr.io"[..])
        );
        assert_eq!(strip_prefix(b"http://x", b"oci://"), None);
        assert_eq!(strip_prefix(b"", b"oci://"), None);
    }

    #[test]
    fn tsv_parsing_five_fields() {
        let line = b"backstage\thttps://charts.example.com\tbackstage\t2.0.0\tgitops/argocd/platform/backstage/values.yaml";
        let fields = shell_compat::read_fields(line, b"\t", 5);
        assert_eq!(fields.len(), 5);
        assert_eq!(fields[0], b"backstage");
        assert_eq!(fields[1], b"https://charts.example.com");
        assert_eq!(fields[2], b"backstage");
        assert_eq!(fields[3], b"2.0.0");
        assert_eq!(fields[4], b"gitops/argocd/platform/backstage/values.yaml");
    }

    #[test]
    fn tsv_parsing_oci_repo() {
        let line = b"buzz\tghcr.io/block/buzz/charts\tbuzz\t1.2.3\tvalues.yaml";
        let fields = shell_compat::read_fields(line, b"\t", 5);
        assert_eq!(fields.len(), 5);
        assert_eq!(fields[0], b"buzz");
        assert_eq!(fields[1], b"ghcr.io/block/buzz/charts");
        assert!(!is_http(&fields[1]));
        assert_eq!(host_of(&fields[1]), b"ghcr.io");
    }

    #[test]
    fn tsv_parsing_short_line() {
        let line = b"only\ttwo";
        let fields = shell_compat::read_fields(line, b"\t", 5);
        assert_eq!(fields.len(), 5);
        assert_eq!(fields[0], b"only");
        assert_eq!(fields[1], b"two");
        assert!(fields[2].is_empty());
    }
}
