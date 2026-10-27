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

pub mod publish_dev_latest;

#[cfg(test)]
mod tests {
    use super::publish_dev_latest::*;

    #[test]
    fn default_tag() {
        assert_eq!(tag_from_env(None), "tabula-extension-dev-latest");
    }

    #[test]
    fn custom_tag() {
        assert_eq!(tag_from_env(Some("custom-tag".to_string())), "custom-tag");
    }

    #[test]
    fn build_info_json_format() {
        let json = build_info_json("abc123", "2026-10-25T12:00:00Z", "9.9.9");
        assert!(json.contains("\"commit\":\"abc123\""));
        assert!(json.contains("\"builtAt\":\"2026-10-25T12:00:00Z\""));
        assert!(json.contains("\"version\":\"9.9.9\""));
        assert!(json.starts_with('{'));
        assert!(json.trim_end().ends_with('}'));
    }

    #[test]
    fn build_info_json_no_trailing_garbage() {
        let json = build_info_json("deadbeef", "2026-01-01T00:00:00Z", "1.0.0");
        let trimmed = json.trim();
        assert_eq!(trimmed.matches('{').count(), 1);
        assert_eq!(trimmed.matches('}').count(), 1);
    }

    #[test]
    fn archive_src_path() {
        assert_eq!(
            chrome_zip_bazel_bin_path(),
            "bazel-bin/apps/suites/tabula/extension/tabula-extension-chrome.zip"
        );
    }

    #[test]
    fn bazel_target_path() {
        assert_eq!(
            chrome_zip_bazel_target(),
            "//apps/suites/tabula/extension:chrome_zip"
        );
    }

    #[test]
    fn end_to_end_publish_flow_with_stubs() {
        use std::env;
        use std::fs;
        #[cfg(unix)]
        use std::os::unix::fs::PermissionsExt;
        use std::time::{SystemTime, UNIX_EPOCH};

        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let tmp = env::temp_dir().join(format!("tabula-publish-test-{nanos}"));
        let fake_root = tmp.join("workspace");
        let stubs = tmp.join("stubs");
        let work = tmp.join("runner-temp");
        let gh_log = tmp.join("gh.log");

        fs::create_dir_all(fake_root.join("apps/suites/tabula/extension")).unwrap();
        fs::create_dir_all(fake_root.join("bazel-bin/apps/suites/tabula/extension")).unwrap();
        fs::create_dir_all(&stubs).unwrap();
        fs::create_dir_all(&work).unwrap();

        fs::write(
            fake_root.join("apps/suites/tabula/extension/package.json"),
            "{\"version\":\"9.9.9-test\"}\n",
        )
        .unwrap();
        fs::write(
            fake_root.join("bazel-bin/apps/suites/tabula/extension/tabula-extension-chrome.zip"),
            b"placeholder-zip",
        )
        .unwrap();

        let write_stub = |name: &str, body: &str| {
            let p = stubs.join(name);
            fs::write(&p, body).unwrap();
            #[cfg(unix)]
            fs::set_permissions(&p, fs::Permissions::from_mode(0o755)).unwrap();
        };

        write_stub("bazel", "#!/usr/bin/env bash\nexit 0\n");
        write_stub("node", "#!/usr/bin/env bash\necho \"9.9.9-test\"\n");
        write_stub(
            "zip",
            "#!/usr/bin/env bash\ncp build-info.json tabula-extension-chrome.zip\nexit 0\n",
        );
        write_stub(
            "gh",
            &format!(
                "#!/usr/bin/env bash\necho \"$PWD|$*\" >> \"{}\"\nexit 0\n",
                gh_log.display()
            ),
        );

        let old_path = env::var("PATH").unwrap_or_default();
        env::set_var("PATH", format!("{}:/usr/bin:/bin", stubs.display()));
        env::set_var("BUILD_WORKSPACE_DIRECTORY", &fake_root);
        env::set_var("RUNNER_TEMP", &work);
        env::set_var("GITHUB_SHA", "deadbeefcafe");
        env::remove_var("BUILDBUDDY_API_KEY");
        env::remove_var("TAG");

        let rc = run(&[]);
        env::set_var("PATH", old_path);
        assert_eq!(rc, 0);

        let logged = fs::read_to_string(&gh_log).unwrap();
        let canonical_root = fs::canonicalize(&fake_root).unwrap();
        for line in logged.lines() {
            let (cwd, _args) = line.split_once('|').unwrap();
            assert_eq!(fs::canonicalize(cwd).unwrap(), canonical_root);
        }
        assert!(logged.contains("release upload tabula-extension-dev-latest"));
        assert!(logged.contains("--clobber"));

        let stamped = fs::read_to_string(work.join("build-info.json")).unwrap();
        assert!(stamped.contains("deadbeefcafe"));
        assert!(stamped.contains("9.9.9-test"));

        let _ = fs::remove_dir_all(&tmp);
    }
}
