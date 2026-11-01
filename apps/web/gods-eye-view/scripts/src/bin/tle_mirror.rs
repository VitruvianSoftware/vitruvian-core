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

//! `bazel run //apps/web/gods-eye-view:tle_mirror -- <dir>`; see
//! scripts/src/tle_mirror.rs. Its tests are `:tle_mirror_test`.
//!
//! The module is included by path rather than through gev_scripts_lib so this
//! file builds alone, standard library only, with `rustc bin/tle_mirror.rs`:
//! that is how .github/workflows/gods-eye-view-tle-mirror.yaml builds it.

// The group-parity and URL checks are called only by the tests below.
#[cfg_attr(not(test), allow(dead_code))]
#[path = "../tle_mirror.rs"]
mod tle_mirror;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if let Err(code) = tle_mirror::run(&args) {
        std::process::exit(code);
    }
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;
    use std::time::Duration;
    use crate::tle_mirror::{
        celestrak_group_url, curl_args, has_tle, mirror_with_fetcher, server_group_url,
        verify_client_groups_mirrored, HttpResponse, CURL_ARGS, MIRRORED_GROUPS,
    };

    /// The app's files: the test's runfiles under `bazel test` (`data` in
    /// BUILD.bazel), else the source tree under `cargo test`.
    fn app_root() -> PathBuf {
        let root = match std::env::var("TEST_SRCDIR") {
            Ok(srcdir) => PathBuf::from(srcdir).join("_main/apps/web/gods-eye-view"),
            Err(_) => PathBuf::from(option_env!("CARGO_MANIFEST_DIR").expect("bazel or cargo"))
                .join(".."),
        };
        assert!(root.join("package.json").is_file(), "no package.json in {}", root.display());
        root
    }

    /// mirror.test.mjs: "the mirror carries every group the client requests".
    #[test]
    fn verify_tle_mirror_client_groups() {
        let groups = verify_client_groups_mirrored(&app_root())
            .expect("TLE mirror client group parity check failed");
        assert!(groups.contains(&"active".to_string()));
        assert!(groups.contains(&"stations".to_string()));
    }

    /// The scan fails when the client asks for a group the mirror lacks.
    #[test]
    fn verify_client_groups_reports_an_unmirrored_group() {
        let tmp = std::env::temp_dir().join(format!("gev_tle_scan_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&tmp);
        std::fs::create_dir_all(tmp.join("src/layers/satellites")).unwrap();
        std::fs::create_dir_all(tmp.join("src/tools/queries")).unwrap();
        std::fs::create_dir_all(tmp.join("src/layers/launches")).unwrap();
        std::fs::write(
            tmp.join("src/layers/satellites/policy.js"),
            "const CATALOG_GROUPS = [\n  { id: 'iss', path: 'stations' },\n];\n",
        )
        .unwrap();
        std::fs::write(
            tmp.join("src/tools/queries/space.js"),
            "const GROUPS = ['visual', 'weather'];\n",
        )
        .unwrap();
        std::fs::write(
            tmp.join("src/layers/launches/feed.js"),
            "fetch('/api/celestrak/active'); fetch(\"/api/celestrak/cubesat\");\n",
        )
        .unwrap();
        // A test file's literal is not a client request.
        std::fs::write(
            tmp.join("src/layers/launches/feed.test.mjs"),
            "fetch('/api/celestrak/amateur');\n",
        )
        .unwrap();
        let err = verify_client_groups_mirrored(&tmp).unwrap_err();
        let _ = std::fs::remove_dir_all(&tmp);
        assert_eq!(err, "requested by the client but not mirrored: cubesat, weather");
    }

    /// mirror.test.mjs: "the mirror fetches the URL the server would".
    #[test]
    fn fetches_the_url_the_server_would() {
        let source =
            std::fs::read_to_string(app_root().join("src/data/spaceProviderRequests.js"))
                .expect("read src/data/spaceProviderRequests.js");
        for group in MIRRORED_GROUPS {
            assert_eq!(
                celestrak_group_url(group),
                server_group_url(&source, group).unwrap(),
                "{group}"
            );
        }
        assert_eq!(
            celestrak_group_url("gps-ops"),
            "https://celestrak.org/NORAD/elements/gp.php?GROUP=gps-ops&FORMAT=tle"
        );
    }

    /// mirror.test.mjs: "a failed group keeps the file it had; good groups are
    /// refreshed; one retry".
    #[test]
    fn failed_group_keeps_its_file_good_groups_refresh_one_retry() {
        let tmp = std::env::temp_dir().join(format!("gev_tle_mirror_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&tmp);
        std::fs::create_dir_all(&tmp).unwrap();
        std::fs::write(tmp.join("visual.txt"), "previous visual\n").unwrap();

        let tle = "ISS (ZARYA)\n1 25544U 98067A   26280.50000000  .00010000  00000-0  18000-3 0  9990\n2 25544  51.6400 100.0000 0005000 100.0000 260.0000 15.50000000400000\n";
        let mut calls: Vec<String> = Vec::new();
        let ok = |body: &str| {
            Ok(HttpResponse {
                status: 200,
                body: body.to_string(),
            })
        };

        let failed = mirror_with_fetcher(
            &tmp,
            &["stations", "visual", "geo", "galileo"],
            Duration::ZERO,
            |url| {
                let group = url
                    .split("GROUP=")
                    .nth(1)
                    .and_then(|s| s.split('&').next())
                    .unwrap_or("")
                    .to_string();
                calls.push(group.clone());
                match group.as_str() {
                    "stations" => ok(tle),
                    "visual" => ok("<html>error</html>"),
                    "geo" => Ok(HttpResponse {
                        status: 403,
                        body: "nope".to_string(),
                    }),
                    // Fails once, then answers: the retry recovers it.
                    "galileo" if calls.iter().filter(|g| *g == "galileo").count() == 1 => {
                        Err("fetch failed".to_string())
                    }
                    "galileo" => ok(tle),
                    _ => Err("unknown".to_string()),
                }
            },
        )
        .unwrap();

        let read = |name: &str| std::fs::read_to_string(tmp.join(name)).unwrap();
        assert_eq!(
            failed,
            vec!["visual: no TLE lines in the response", "geo: HTTP 403"]
        );
        assert_eq!(read("stations.txt"), tle);
        assert_eq!(read("galileo.txt"), tle);
        assert_eq!(
            calls,
            vec!["stations", "visual", "visual", "geo", "geo", "galileo", "galileo"]
        );
        assert_eq!(read("visual.txt"), "previous visual\n");
        assert!(!tmp.join("geo.txt").exists());
        assert!(has_tle(tle) && !has_tle("<html>error</html>"));
        let _ = std::fs::remove_dir_all(&tmp);
    }

    /// curl never reads ~/.curlrc (`-q` first), stays on HTTPS with TLS 1.2+
    /// for every request and redirect, follows at most 5 redirects, and takes
    /// the URL after `--`, so it can never be read as an option.
    #[test]
    fn curl_is_hardened() {
        assert_eq!(CURL_ARGS[0], "-q");
        let pair = |flag: &str, value: &str| {
            CURL_ARGS.windows(2).any(|w| w[0] == flag && w[1] == value)
        };
        assert!(pair("--proto", "=https"), "{CURL_ARGS:?}");
        assert!(pair("--proto-redir", "=https"), "{CURL_ARGS:?}");
        assert!(pair("--max-redirs", "5"), "{CURL_ARGS:?}");
        assert!(CURL_ARGS.contains(&"--tlsv1.2"), "{CURL_ARGS:?}");
        assert!(!CURL_ARGS.contains(&"--"), "{CURL_ARGS:?}");

        let url = celestrak_group_url("stations");
        let args = curl_args(&url);
        assert_eq!(args[..CURL_ARGS.len()], CURL_ARGS[..]);
        assert_eq!(args[args.len() - 2..], ["--".to_string(), url]);
        // An option-shaped "URL" stays a positional argument.
        assert_eq!(curl_args("-K/etc/passwd").last().unwrap(), "-K/etc/passwd");
    }

    #[test]
    fn run_without_a_directory_is_a_usage_error() {
        assert_eq!(crate::tle_mirror::run(&[]), Err(2));
        assert_eq!(crate::tle_mirror::run(&[String::new()]), Err(2));
    }
}
