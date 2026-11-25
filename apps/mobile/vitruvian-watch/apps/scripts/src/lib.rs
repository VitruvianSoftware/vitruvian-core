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

use std::path::PathBuf;
use std::process::Command;

pub mod install_all;
pub mod publish;

pub fn select_single_artifact_path(stdout: &str, suffix: &str) -> Result<PathBuf, String> {
    let matches: Vec<&str> = stdout
        .lines()
        .map(str::trim)
        .filter(|line| line.ends_with(suffix))
        .collect();
    if matches.len() != 1 {
        return Err(format!(
            "expected exactly one output ending with {suffix}, got {}:\n{}",
            matches.len(),
            if matches.is_empty() {
                "<none>".to_string()
            } else {
                matches.join("\n")
            }
        ));
    }
    Ok(PathBuf::from(matches[0]))
}

pub fn locate_apk(android_platforms_flag: &str, pkg: &str) -> Result<PathBuf, String> {
    let label = format!("//apps/mobile/vitruvian-watch/apps/{pkg}:app.apk");
    let suffix = format!("/apps/mobile/vitruvian-watch/apps/{pkg}/app.apk");
    let output = Command::new("bazel")
        .args(["cquery", android_platforms_flag, "--output=files", &label])
        .output()
        .map_err(|e| format!("failed to run bazel cquery for {label}: {e}"))?;
    if !output.status.success() {
        return Err(format!(
            "bazel cquery {label} failed:\n{}",
            String::from_utf8_lossy(&output.stderr)
        ));
    }
    let stdout = String::from_utf8_lossy(&output.stdout);
    let path = select_single_artifact_path(&stdout, &suffix)?;
    if !path.is_file() {
        return Err(format!(
            "Expected APK output at {} not found",
            path.display()
        ));
    }
    Ok(path)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn select_single_artifact_path_filters_and_validates() {
        let suffix = "/apps/mobile/vitruvian-watch/apps/remote/app.apk";
        let out = "\
bazel-out/k8-fastbuild-ST-111/bin/apps/mobile/vitruvian-watch/apps/remote/app_unsigned.apk
bazel-out/k8-fastbuild-ST-111/bin/apps/mobile/vitruvian-watch/apps/remote/app.apk
";
        assert_eq!(
            select_single_artifact_path(out, suffix).unwrap(),
            PathBuf::from(
                "bazel-out/k8-fastbuild-ST-111/bin/apps/mobile/vitruvian-watch/apps/remote/app.apk"
            )
        );

        let err = select_single_artifact_path(
            "bazel-out/k8-fastbuild-ST-111/bin/apps/mobile/vitruvian-watch/apps/remote/app_unsigned.apk\n",
            suffix,
        )
        .unwrap_err();
        assert!(err.contains("got 0"), "{err}");

        let dupes = "\
bazel-out/k8-fastbuild-ST-aaa/bin/apps/mobile/vitruvian-watch/apps/remote/app.apk
bazel-out/k8-fastbuild-ST-bbb/bin/apps/mobile/vitruvian-watch/apps/remote/app.apk
";
        let err = select_single_artifact_path(dupes, suffix).unwrap_err();
        assert!(
            err.contains("got 2") && err.contains("-ST-aaa") && err.contains("-ST-bbb"),
            "{err}"
        );
    }
}
