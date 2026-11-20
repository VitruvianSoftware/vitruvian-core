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

//! Renders `applicationset.yaml`'s Helm chart via `helm template` and validates
//! the rendered Kubernetes `Deployment` (never silently skipping).

use std::path::{Path, PathBuf};
use std::process::{self, Command};
use std::time::Duration;

use headscale_values::{check_rendered_headscale_deployment, single_doc_of_kind, yaml, PKG_DIR};
use serde_json::Value;

struct TempDir(PathBuf);

impl TempDir {
    fn new() -> Self {
        let dir = std::env::temp_dir().join(format!("headscale-render-check-{}", process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("create temp dir");
        Self(dir)
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn resolve_applicationset() -> PathBuf {
    if let Ok(ws) = std::env::var("BUILD_WORKSPACE_DIRECTORY") {
        if !ws.is_empty() {
            let p = Path::new(&ws).join(PKG_DIR).join("applicationset.yaml");
            if p.is_file() {
                return p;
            }
        }
    }
    yaml::resolve_data_path(PKG_DIR, "applicationset.yaml")
}

fn find_chart_dir(dest: &Path, chart: &str) -> Result<PathBuf, String> {
    let direct = dest.join(chart);
    if direct.join("Chart.yaml").is_file() {
        return Ok(direct);
    }
    let entries =
        std::fs::read_dir(dest).map_err(|e| format!("failed to scan {}: {e}", dest.display()))?;
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() && path.join("Chart.yaml").is_file() {
            return Ok(path);
        }
    }
    Err(format!(
        "could not locate unpacked Chart.yaml under {}",
        dest.display()
    ))
}

fn pull_chart(repo: &str, chart: &str, rev: &str, dest: &Path) -> Result<PathBuf, String> {
    let mut last_err = String::new();
    for attempt in 1..=3 {
        let _ = std::fs::remove_dir_all(dest);
        std::fs::create_dir_all(dest)
            .map_err(|e| format!("failed to create {}: {e}", dest.display()))?;
        let out = Command::new("helm")
            .arg("pull")
            .arg(chart)
            .arg("--repo")
            .arg(repo)
            .arg("--version")
            .arg(rev)
            .arg("--untar")
            .arg("--untardir")
            .arg(dest)
            .output()
            .map_err(|e| format!("failed to execute helm pull: {e}"))?;
        if out.status.success() {
            return find_chart_dir(dest, chart);
        }
        last_err = String::from_utf8_lossy(&out.stderr).trim().to_string();
        if attempt < 3 {
            eprintln!(
                "render-check: helm pull {chart}@{rev} failed (attempt {attempt}/3): {last_err}; retrying..."
            );
            std::thread::sleep(Duration::from_secs(3));
        }
    }
    Err(format!(
        "helm pull {chart}@{rev} from {repo} failed after 3 attempts: {last_err}"
    ))
}

fn run() -> Result<(), String> {
    let mut chart_dir_arg: Option<PathBuf> = None;
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--chart-dir" => {
                let p = args
                    .next()
                    .ok_or_else(|| "missing path after --chart-dir".to_string())?;
                chart_dir_arg = Some(PathBuf::from(p));
            }
            other => return Err(format!("unknown argument '{other}'")),
        }
    }

    let helm_check = Command::new("helm")
        .arg("version")
        .arg("--short")
        .output()
        .map_err(|e| format!("helm not runnable ({e}) — render-check never skips without helm"))?;
    if !helm_check.status.success() {
        return Err(format!(
            "helm version failed: {}",
            String::from_utf8_lossy(&helm_check.stderr)
        ));
    }

    let appset_path = resolve_applicationset();
    let appset_raw = std::fs::read_to_string(&appset_path)
        .map_err(|e| format!("failed to read {}: {e}", appset_path.display()))?;
    let docs = yaml::parse_all(&appset_raw)
        .map_err(|e| format!("failed to parse {}: {e}", appset_path.display()))?;
    let appset = single_doc_of_kind(&docs, "ApplicationSet");
    let src = appset
        .pointer("/spec/template/spec/source")
        .ok_or_else(|| "missing spec.template.spec.source".to_string())?;
    let repo = src
        .get("repoURL")
        .and_then(Value::as_str)
        .ok_or_else(|| "missing source.repoURL".to_string())?;
    let chart = src
        .get("chart")
        .and_then(Value::as_str)
        .ok_or_else(|| "missing source.chart".to_string())?;
    let rev = src
        .get("targetRevision")
        .and_then(Value::as_str)
        .ok_or_else(|| "missing source.targetRevision".to_string())?;
    let raw_values = src
        .pointer("/helm/values")
        .and_then(Value::as_str)
        .ok_or_else(|| "missing source.helm.values".to_string())?;

    let tmp = TempDir::new();
    let values_path = tmp.0.join("values.yaml");
    std::fs::write(&values_path, raw_values)
        .map_err(|e| format!("failed to write {}: {e}", values_path.display()))?;

    let chart_dir = match chart_dir_arg {
        Some(p) => p,
        None => pull_chart(repo, chart, rev, &tmp.0.join("chart"))?,
    };

    let tmpl = Command::new("helm")
        .arg("template")
        .arg("headscale")
        .arg(&chart_dir)
        .arg("--namespace")
        .arg("headscale")
        .arg("--kube-version")
        .arg("1.35.3")
        .arg("--values")
        .arg(&values_path)
        .output()
        .map_err(|e| format!("failed to execute helm template: {e}"))?;
    if !tmpl.status.success() {
        return Err(format!(
            "helm template failed:\n{}",
            String::from_utf8_lossy(&tmpl.stderr)
        ));
    }

    let rendered = String::from_utf8(tmpl.stdout)
        .map_err(|e| format!("helm template output was not valid UTF-8: {e}"))?;
    check_rendered_headscale_deployment(&rendered)?;
    println!("headscale render-check: OK ({chart}@{rev})");
    Ok(())
}

fn main() {
    if let Err(e) = run() {
        eprintln!("headscale render-check: FAIL: {e}");
        process::exit(1);
    }
}
