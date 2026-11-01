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

//! //tools/ci:backstage_boot_smoke — boots the built backstage container against a
//! throwaway Postgres and asserts that every backend plugin initializes and
//! the service reports READY.

use shell_compat::{capture, cat, err, out, status, subst};
use std::process::Command;

struct Cleanup {
    app: Vec<u8>,
    pg: Vec<u8>,
    net: Vec<u8>,
    cfg: Vec<u8>,
}

impl Drop for Cleanup {
    fn drop(&mut self) {
        let _ = Command::new("docker")
            .arg("rm")
            .arg("-f")
            .arg(shell_compat::os(&self.app))
            .arg(shell_compat::os(&self.pg))
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status();
        let _ = Command::new("docker")
            .arg("network")
            .arg("rm")
            .arg(shell_compat::os(&self.net))
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status();
        let _ = std::fs::remove_file(shell_compat::path(&self.cfg));
    }
}

fn base64_encode(input: &[u8]) -> Vec<u8> {
    const CHARS: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = Vec::with_capacity((input.len() + 2) / 3 * 4);
    for chunk in input.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = if chunk.len() > 1 { chunk[1] as u32 } else { 0 };
        let b2 = if chunk.len() > 2 { chunk[2] as u32 } else { 0 };
        let n = (b0 << 16) | (b1 << 8) | b2;
        out.push(CHARS[((n >> 18) & 63) as usize]);
        out.push(CHARS[((n >> 12) & 63) as usize]);
        if chunk.len() > 1 {
            out.push(CHARS[((n >> 6) & 63) as usize]);
        } else {
            out.push(b'=');
        }
        if chunk.len() > 2 {
            out.push(CHARS[(n & 63) as usize]);
        } else {
            out.push(b'=');
        }
    }
    out
}

/// The smoke config, exactly as the script's heredoc wrote it. One raw
/// literal on purpose: a `\` line continuation in a Rust string also eats the
/// next line's leading spaces, which flattened this YAML into duplicate
/// top-level keys and Backstage refused to boot (DUPLICATE_KEY).
const CONFIG_TEMPLATE: &str = r#"backend:
  baseUrl: http://localhost:7007
  listen: { host: 0.0.0.0, port: 7007 }
  database:
    client: pg
    connection:
      host: {PG}
      port: 5432
      user: postgres
      password: smoke
  auth:
    keys:
      - secret: {SMOKE_KEY}
app:
  baseUrl: http://localhost:7007
auth:
  environment: development
  providers:
    github:
      development:
        clientId: smoke-client-id
        clientSecret: smoke-client-secret
permission:
  enabled: true
kubernetes:
  serviceLocatorMethod: { type: multiTenant }
  clusterLocatorMethods:
    - type: config
      clusters:
        - name: smoke
          url: https://kubernetes.default.svc
          authProvider: serviceAccount
          skipTLSVerify: true
          serviceAccountToken: smoke-token
catalog:
  locations: []
techdocs:
  builder: local
  generator: { runIn: local }
  publisher: { type: local }
# REQUIRED, not decorative: @backstage-community/plugin-grafana declares
# "required": ["grafana"] at the root of its config.schema.json, and the app
# bundle's frontend schema is validated against whatever config the backend
# boots with. Since this file is passed as the ONLY --config, omitting this key
# fails app-backend startup with "Invalid app bundle schema" -- which is exactly
# how this smoke test caught the plugin landing without it.
grafana:
  domain: https://grafana.invalid
"#;

fn generate_config(pg_name: &[u8], smoke_key: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    let mut rest = CONFIG_TEMPLATE.as_bytes();
    while let Some(i) = rest.iter().position(|&c| c == b'{') {
        out.extend_from_slice(&rest[..i]);
        let tail = &rest[i..];
        if let Some(t) = tail.strip_prefix(b"{PG}".as_slice()) {
            out.extend_from_slice(pg_name);
            rest = t;
        } else if let Some(t) = tail.strip_prefix(b"{SMOKE_KEY}".as_slice()) {
            out.extend_from_slice(smoke_key);
            rest = t;
        } else {
            out.push(b'{');
            rest = &tail[1..];
        }
    }
    out.extend_from_slice(rest);
    out
}

fn extract_errors(logs: &[u8]) -> Vec<u8> {
    let mut errors = Vec::new();
    let mut count = 0;
    for line in logs.split(|&c| c == b'\n') {
        if count >= 4 {
            break;
        }
        if !shell_compat::contains(line, b"\"level\":\"error\"") {
            continue;
        }
        // Extract "message":"..." up to 200 chars
        if let Some(pos) = line.windows(11).position(|w| w == b"\"message\":\"") {
            let start = pos + 11;
            let rest = &line[start..];
            let end = rest
                .iter()
                .position(|&c| c == b'"')
                .unwrap_or(rest.len())
                .min(200);
            errors.extend_from_slice(b"  ");
            errors.extend_from_slice(&rest[..end]);
            errors.push(b'\n');
            count += 1;
        }
    }
    errors
}

/// `docker logs <app> 2>&1`: the container's stdout and stderr in the order
/// it wrote them, as the script read them (the first errors and the last 50
/// lines are only meaningful in that order).
fn docker_logs(app: &[u8]) -> Vec<u8> {
    let r = capture(
        0,
        Command::new("bash")
            .arg("-c")
            .arg("exec docker logs \"$1\" 2>&1")
            .arg("docker-logs")
            .arg(shell_compat::os(app)),
    );
    cat(&[&r.stdout, &r.stderr])
}

fn show_errors(app: &[u8]) {
    let logs = docker_logs(app);
    let errs = extract_errors(&logs);
    if !errs.is_empty() {
        err(&errs);
    } else {
        err(b"  Container logs (last 50 lines):\n");
        // `tail -50`: the final newline ends the last line, it does not start
        // an empty one.
        let trimmed = logs.strip_suffix(b"\n").unwrap_or(&logs);
        let all_lines: Vec<&[u8]> = trimmed.split(|&c| c == b'\n').collect();
        let start = if all_lines.len() > 50 {
            all_lines.len() - 50
        } else {
            0
        };
        for line in &all_lines[start..] {
            err(&cat(&[b"  ", *line, b"\n"]));
        }
    }
}

#[derive(PartialEq)]
enum Status {
    Ok,
    StartupError,
    Died,
    Timeout,
}

pub fn run(args: &[Vec<u8>]) -> i32 {
    if args.is_empty() {
        err(b"usage: backstage-boot-smoke <image-ref>\n");
        return 1;
    }
    let image = &args[0];

    let sfx = std::process::id().to_string();
    let net = cat(&[b"backstage-smoke-net-", sfx.as_bytes()]);
    let pg = cat(&[b"backstage-smoke-pg-", sfx.as_bytes()]);
    let app = cat(&[b"backstage-smoke-app-", sfx.as_bytes()]);

    let cfg_template = cat(&[&shell_compat::tmpdir(), b"/bs-smoke-XXXXXX.yaml"]);
    let cfg = match shell_compat::mktemp_file(&cfg_template) {
        Ok(p) => p,
        Err(e) => {
            err(&cat(&[
                b"boot-smoke: failed to create temp config: ",
                e.to_string().as_bytes(),
                b"\n",
            ]));
            return 1;
        }
    };

    let _cleanup = Cleanup {
        app: app.clone(),
        pg: pg.clone(),
        net: net.clone(),
        cfg: cfg.clone(),
    };

    // Create network
    let rc = status(
        0,
        Command::new("docker")
            .arg("network")
            .arg("create")
            .arg(shell_compat::os(&net))
            .stdout(std::process::Stdio::null()),
        false,
    );
    if rc != 0 {
        err(b"boot-smoke: failed to create docker network\n");
        return 1;
    }

    // Start postgres
    out(b"boot-smoke: starting postgres ...\n");
    let rc = status(
        0,
        Command::new("docker")
            .arg("run")
            .arg("-d")
            .arg("--name")
            .arg(shell_compat::os(&pg))
            .arg("--network")
            .arg(shell_compat::os(&net))
            .arg("-e")
            .arg("POSTGRES_PASSWORD=smoke")
            .arg("-e")
            .arg("POSTGRES_USER=postgres")
            .arg("postgres:16-alpine")
            .stdout(std::process::Stdio::null()),
        false,
    );
    if rc != 0 {
        err(b"boot-smoke: failed to start postgres container\n");
        return 1;
    }

    // Wait for postgres readiness
    let mut pg_ready = false;
    for _ in 0..60 {
        let rc = status(
            0,
            Command::new("docker")
                .arg("exec")
                .arg(shell_compat::os(&pg))
                .arg("pg_isready")
                .arg("-h")
                .arg("127.0.0.1")
                .arg("-U")
                .arg("postgres")
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null()),
            true,
        );
        if rc == 0 {
            pg_ready = true;
            break;
        }
        std::thread::sleep(std::time::Duration::from_secs(1));
    }
    if !pg_ready {
        err(b"boot-smoke: \xe2\x9c\x97 postgres never became ready\n");
        return 1;
    }

    // Generate config
    let smoke_key = base64_encode(b"boot-smoke-ephemeral-key");
    let config_data = generate_config(&pg, &smoke_key);
    if let Err(e) = shell_compat::write_file(&cfg, &config_data, 0o644) {
        err(&cat(&[
            b"boot-smoke: failed to write config: ",
            e.to_string().as_bytes(),
            b"\n",
        ]));
        return 1;
    }

    // Start backstage
    out(&cat(&[b"boot-smoke: starting ", image, b" ...\n"]));

    // chmod 0644 on the cfg (mktemp creates 0600, image runs as non-root)
    let _ = std::fs::set_permissions(
        shell_compat::path(&cfg),
        std::os::unix::fs::PermissionsExt::from_mode(0o644),
    );

    // docker create
    let rc = status(
        0,
        Command::new("docker")
            .arg("create")
            .arg("--name")
            .arg(shell_compat::os(&app))
            .arg("--network")
            .arg(shell_compat::os(&net))
            .arg("-p")
            .arg("17007:7007")
            .arg(shell_compat::os(image))
            .arg("node")
            .arg("packages/backend/dist/index.cjs.js")
            .arg("--config")
            .arg("/app/app-config.smoke.yaml")
            .stdout(std::process::Stdio::null()),
        false,
    );
    if rc != 0 {
        err(b"boot-smoke: failed to create app container\n");
        return 1;
    }

    // docker cp config into container
    let cp_src = cat(&[&cfg, b""]);
    let cp_dst = cat(&[&app, b":/app/app-config.smoke.yaml"]);
    let rc = status(
        0,
        Command::new("docker")
            .arg("cp")
            .arg(shell_compat::os(&cp_src))
            .arg(shell_compat::os(&cp_dst))
            .stdout(std::process::Stdio::null()),
        false,
    );
    if rc != 0 {
        err(b"boot-smoke: failed to copy config into container\n");
        return 1;
    }

    // docker start
    let rc = status(
        0,
        Command::new("docker")
            .arg("start")
            .arg(shell_compat::os(&app))
            .stdout(std::process::Stdio::null()),
        false,
    );
    if rc != 0 {
        err(b"boot-smoke: failed to start app container\n");
        return 1;
    }

    // Poll for readiness (up to 150s)
    let start = std::time::Instant::now();
    let deadline = std::time::Duration::from_secs(150);
    let mut result = Status::Timeout;

    while start.elapsed() < deadline {
        // Check container still running
        let r = capture(
            0,
            Command::new("docker")
                .arg("ps")
                .arg("-q")
                .arg("--filter")
                .arg(shell_compat::os(&cat(&[b"name=", &app]))),
        );
        let ps_out = subst(r.stdout);
        if ps_out.is_empty() {
            result = Status::Died;
            break;
        }

        // Get logs
        let logs = docker_logs(&app);

        // Fail fast on startup error
        if shell_compat::contains(&logs, b"threw an error during startup")
            || shell_compat::contains(&logs, b"BackendStartupError")
            || shell_compat::contains(&logs, b"startup failed")
        {
            result = Status::StartupError;
            break;
        }

        // Check for success: plugin init complete AND readiness 200
        if shell_compat::contains(&logs, b"Plugin initialization complete") {
            let r = capture(
                0,
                Command::new("curl")
                    .arg("-fsS")
                    .arg("-o")
                    .arg("/dev/null")
                    .arg("-w")
                    .arg("%{http_code}")
                    .arg("http://localhost:17007/.backstage/health/v1/readiness"),
            );
            let code = subst(r.stdout);
            if code == b"200" {
                result = Status::Ok;
                break;
            }
        }

        std::thread::sleep(std::time::Duration::from_secs(2));
    }

    match result {
        Status::Ok => {
            out(b"boot-smoke: \xe2\x9c\x93 all plugins initialized and readiness returned 200\n");
            0
        }
        Status::StartupError => {
            err(b"boot-smoke: \xe2\x9c\x97 a plugin failed to initialize\n");
            show_errors(&app);
            1
        }
        Status::Died => {
            err(b"boot-smoke: \xe2\x9c\x97 container exited before becoming ready\n");
            show_errors(&app);
            1
        }
        Status::Timeout => {
            err(b"boot-smoke: \xe2\x9c\x97 timed out after 150s without reaching readiness\n");
            show_errors(&app);
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base64_encode_matches_printf_pipe() {
        assert_eq!(
            base64_encode(b"boot-smoke-ephemeral-key"),
            b"Ym9vdC1zbW9rZS1lcGhlbWVyYWwta2V5"
        );
    }

    #[test]
    fn base64_encode_empty() {
        assert_eq!(base64_encode(b""), b"");
    }

    #[test]
    fn base64_encode_one_byte() {
        assert_eq!(base64_encode(b"a"), b"YQ==");
    }

    #[test]
    fn base64_encode_two_bytes() {
        assert_eq!(base64_encode(b"ab"), b"YWI=");
    }

    #[test]
    fn base64_encode_three_bytes() {
        assert_eq!(base64_encode(b"abc"), b"YWJj");
    }

    #[test]
    fn generate_config_contains_pg_host() {
        let cfg = generate_config(b"my-pg-container", b"dGVzdA==");
        let s = std::str::from_utf8(&cfg).unwrap();
        assert!(s.contains("host: my-pg-container"));
        assert!(s.contains("secret: dGVzdA=="));
        assert!(s.contains("baseUrl: http://localhost:7007"));
        assert!(s.contains("grafana:"));
        assert!(s.contains("domain: https://grafana.invalid"));
    }

    #[test]
    fn generate_config_has_all_required_sections() {
        let cfg = generate_config(b"pg", b"key");
        let s = std::str::from_utf8(&cfg).unwrap();
        assert!(s.contains("backend:"));
        assert!(s.contains("app:"));
        assert!(s.contains("auth:"));
        assert!(s.contains("permission:"));
        assert!(s.contains("kubernetes:"));
        assert!(s.contains("catalog:"));
        assert!(s.contains("techdocs:"));
        assert!(s.contains("grafana:"));
    }

    #[test]
    fn extract_errors_finds_error_messages() {
        let logs = b"some info line\n\
{\"level\":\"info\",\"message\":\"ok\"}\n\
{\"level\":\"error\",\"message\":\"auth provider not found\"}\n\
{\"level\":\"error\",\"message\":\"plugin X failed\"}\n\
another line\n";
        let errs = extract_errors(logs);
        let s = std::str::from_utf8(&errs).unwrap();
        assert!(s.contains("auth provider not found"));
        assert!(s.contains("plugin X failed"));
    }

    #[test]
    fn extract_errors_limits_to_4() {
        let mut logs = Vec::new();
        for i in 0..10 {
            logs.extend_from_slice(
                format!("{{\"level\":\"error\",\"message\":\"err{}\"}}\n", i).as_bytes(),
            );
        }
        let errs = extract_errors(&logs);
        let count = errs
            .split(|&c| c == b'\n')
            .filter(|l| !l.is_empty())
            .count();
        assert_eq!(count, 4);
    }

    #[test]
    fn extract_errors_returns_empty_on_no_errors() {
        let logs = b"info line 1\ninfo line 2\n";
        let errs = extract_errors(logs);
        assert!(errs.is_empty());
    }

    #[test]
    fn extract_errors_truncates_long_messages() {
        let long_msg = "x".repeat(300);
        let log_line = format!("{{\"level\":\"error\",\"message\":\"{}\"}}\n", long_msg);
        let errs = extract_errors(log_line.as_bytes());
        // Should have "  " prefix + up to 200 chars + newline
        let lines: Vec<&[u8]> = errs
            .split(|&c| c == b'\n')
            .filter(|l| !l.is_empty())
            .collect();
        assert_eq!(lines.len(), 1);
        // 2 spaces prefix + 200 chars max
        assert!(lines[0].len() <= 202);
    }

    #[test]
    fn run_with_no_args_fails() {
        let rc = run(&[]);
        assert_eq!(rc, 1);
    }

    /// The config byte for byte as the retired script's heredoc produced it
    /// (tools/ci/src/backstage_boot_smoke/testdata/smoke-config.golden.yaml,
    /// copied from that heredoc with $PG=pg-x and $SMOKE_KEY=a2V5).
    #[test]
    fn config_matches_the_scripts_heredoc_exactly() {
        let got = generate_config(b"pg-x", b"a2V5");
        let want = include_str!("testdata/smoke-config.golden.yaml");
        assert_eq!(String::from_utf8_lossy(&got), want);
    }

    #[test]
    fn config_keeps_its_indentation() {
        let got = String::from_utf8(generate_config(b"pg", b"k")).unwrap();
        assert!(
            got.contains("\n  baseUrl: http://localhost:7007\n"),
            "{got}"
        );
        assert!(got.contains("\n      host: pg\n"), "{got}");
        let top: Vec<&str> = got
            .lines()
            .filter(|l| !l.starts_with(' ') && !l.is_empty())
            .collect();
        let mut uniq = top.clone();
        uniq.sort();
        uniq.dedup();
        assert_eq!(top.len(), uniq.len(), "duplicate top-level keys: {top:?}");
    }
}
