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

//! cicd_telemetry_smoke.sh: the live gate for the CI collector. An unsigned
//! POST must get 400; a correctly signed sample workflow_run event must
//! produce a metric in Prometheus and a trace in Tempo without the committer
//! email. Signing (HMAC-SHA256) and the JSON reads are done here, so the
//! port needs neither python3 nor jq; every run still ends with exactly one
//! verdict, worded as the script's (its ERR trap included).

use std::process::{Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

use shell_compat as sc;

use super::common::*;
use super::crypto;
use super::jq;

/// GitHub's X-Hub-Signature-256 for `payload` under `key`.
pub fn sign(key: &[u8], payload: &[u8]) -> String {
    format!("sha256={}", crypto::hex(&crypto::hmac_sha256(key, payload)))
}

fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs() as i64)
}

/// `date -u +%Y-%m-%dT%H:%M:%SZ` for an epoch time.
pub fn iso_utc(t: i64) -> String {
    let days = t.div_euclid(86400);
    let secs = t.rem_euclid(86400);
    // civil_from_days (Howard Hinnant).
    let z = days + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
        y,
        m,
        d,
        secs / 3600,
        secs % 3600 / 60,
        secs % 60
    )
}

/// `awk -v a="$n" 'BEGIN{exit !(a>=1)}'`: a number-looking value compares
/// numerically, anything else as a string against "1".
pub fn awk_ge_1(n: &[u8]) -> bool {
    let s = String::from_utf8_lossy(n);
    let t = s.trim_matches(|c: char| c == ' ' || c == '\t' || c == '\n');
    let looks_numeric = !t.is_empty()
        && t.parse::<f64>().is_ok()
        && t.bytes()
            .all(|c| c.is_ascii_digit() || matches!(c, b'.' | b'-' | b'+' | b'e' | b'E'));
    if looks_numeric {
        t.parse::<f64>().map_or(false, |x| x >= 1.0)
    } else {
        n >= b"1".as_slice()
    }
}

/// The ERR trap: `✗ FAIL: unexpected error (exit $?) at line $LINENO:
/// $BASH_COMMAND`, then `set -e` exits with that status.
fn unexpected(status: i32, line: u32, command: &str) -> i32 {
    warn(
        format!(
            "\u{2717} FAIL: unexpected error (exit {}) at line {}: {}",
            status, line, command
        )
        .as_bytes(),
    );
    status
}

/// `sleep 5` (the tool on PATH, as the script runs it).
fn sleep5(line: u32) -> Res<()> {
    let mut c = Command::new("sleep");
    c.arg("5");
    let st = run(0, &mut c, false);
    if st != 0 {
        return Err(unexpected(st, line, "sleep 5"));
    }
    Ok(())
}

/// prom <promql>: the first sample value (or nothing), the pipefail status,
/// and what went to stderr (the script keeps it in $W/prom.err).
fn prom(q: &str) -> (i32, Vec<u8>, Vec<u8>) {
    let url = format!(
        "localhost:9090/api/v1/query?query={}",
        jq::uri(q.as_bytes())
    );
    let mut c = cmd(
        "kubectl",
        &[
            b"-n",
            b"monitoring",
            b"exec",
            b"prometheus-server-0",
            b"-c",
            b"prometheus-server",
            b"--",
            b"wget",
            b"-qO-",
            url.as_bytes(),
        ],
    );
    c.stdout(Stdio::piped()).stderr(Stdio::piped());
    let (st, out, errs) = match c.output() {
        Ok(o) => (sc::status_code(o.status), o.stdout, o.stderr),
        Err(e) => (
            sc::spawn_failure_status(&e),
            Vec::new(),
            sc::spawn_diag(0, &c, &e),
        ),
    };
    let (val, ok) = jq::prom_value(&out);
    let mut errs = errs;
    let status = if !ok {
        errs.extend_from_slice(b"jq: error (at <stdin>:0): Cannot parse the query result\n");
        5
    } else {
        st
    };
    (status, sc::subst(val), errs)
}

pub fn main(args: &[Vec<u8>]) -> i32 {
    // The script doubles as a library: sourced with SMOKE_LIB_ONLY set it
    // only defines sign(); run so, it exits 0 at once. The port's stand-in
    // for the sourced function is `SMOKE_LIB_ONLY=1 ... sign SECRET_FILE
    // PAYLOAD_FILE`, which prints the signature (what the shell test checks).
    if sc::env_set_nonempty("SMOKE_LIB_ONLY") {
        if args.len() == 3 && args[0] == b"sign" {
            let key = std::fs::read(sc::path(&args[1])).unwrap_or_default();
            let body = std::fs::read(sc::path(&args[2])).unwrap_or_default();
            say(sign(&key, &body).as_bytes());
        }
        return 0;
    }
    let mut w: Option<Vec<u8>> = None;
    let r = smoke(&mut w);
    if let Some(d) = w {
        let _ = std::fs::remove_dir_all(sc::path(&d));
    }
    match r {
        Ok(c) | Err(c) => c,
    }
}

fn smoke(w_slot: &mut Option<Vec<u8>>) -> Res<i32> {
    default_kubeconfig(49)?;
    let url = sc::env_or("SMOKE_URL", b"https://github-otel.ipv1337.dev/events");
    // python3 and jq are no longer needed: signing and JSON are done here.
    need_tools(&["curl", "kubectl"], false)?;
    let old = sc::umask(0o077);
    let w = sc::mktemp_dir();
    sc::umask(old);
    let w = match w {
        Ok(w) => w,
        Err(e) => {
            sc::err(format!("mktemp: {}\n", sc::strerror(&e)).as_bytes());
            return Err(unexpected(1, 54, "W=\"$(umask 077; mktemp -d)\""));
        }
    };
    *w_slot = Some(w.clone());

    let run_id = now();
    let run_name = format!("cicd-telemetry smoke {}", run_id);
    let q = format!(
        "sum(cicd_calls_total{{cicd_pipeline_name=\"{}\", ci_span_type=\"run\"}})",
        run_name
    );

    // 1. unsigned -> 400
    let (st, code) = capture(
        71,
        cmd(
            "curl",
            &[
                b"-s",
                b"-o",
                b"/dev/null",
                b"-w",
                b"%{http_code}",
                b"-X",
                b"POST",
                b"-H",
                b"X-GitHub-Event: workflow_run",
                b"-H",
                b"Content-Type: application/json",
                b"--data",
                b"{}",
                &url,
            ],
        ),
    );
    if st != 0 {
        return Err(unexpected(st, 71, "code=\"$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'X-GitHub-Event: workflow_run' -H 'Content-Type: application/json' --data '{}' \"$URL\")\""));
    }
    if code != b"400" {
        return die(
            1,
            &sc::cat(&[
                "\u{2717} unsigned request got ".as_bytes(),
                &code,
                b", want 400 -- is the webhook secret empty?",
            ]),
        );
    }
    say("\u{2713} unsigned request rejected (400)".as_bytes());

    // 2. signed sample event -> 200
    let t = now();
    let (now_s, start) = (iso_utc(t), iso_utc(t - 180));
    let payload = format!(
        "{{\"action\":\"completed\",\"workflow_run\":{{\"id\":{id},\"name\":\"{name}\",\"run_attempt\":1,\"status\":\"completed\",\"conclusion\":\"success\",\"run_started_at\":\"{start}\",\"created_at\":\"{start}\",\"updated_at\":\"{now}\",\"html_url\":\"https://github.com/VitruvianSoftware/vitruvian-core/actions/runs/{id}\",\"head_branch\":\"main\",\"head_sha\":\"0000000000000000000000000000000000000000\",\"head_commit\":{{\"committer\":{{\"name\":\"smoke\",\"email\":\"smoke@example.invalid\"}}}}}},\"repository\":{{\"name\":\"vitruvian-core\",\"full_name\":\"VitruvianSoftware/vitruvian-core\",\"owner\":{{\"login\":\"VitruvianSoftware\"}}}},\"sender\":{{\"login\":\"cicd-telemetry-smoke\"}}}}\n",
        id = run_id,
        name = run_name,
        start = start,
        now = now_s
    );
    let payload_path = sc::cat(&[&w, b"/payload"]);
    if let Err(e) = sc::write_file(&payload_path, payload.as_bytes(), 0o600) {
        sc::redirect_error(78, &payload_path, &e);
        return Err(unexpected(1, 78, "cat > \"$W/payload\" <<JSON"));
    }
    let get_secret = cmd(
        "kubectl",
        &[
            b"-n",
            b"cicd-telemetry",
            b"get",
            b"secret",
            b"github-otel-webhook",
            b"-o",
            b"jsonpath={.data.GITHUB_WEBHOOK_SECRET}",
        ],
    );
    let (st, enc) = output(81, get_secret, false);
    let (b64_st, key) = match crypto::b64decode(&enc) {
        Ok(k) => (0, k),
        Err(k) => {
            sc::err(b"base64: invalid input\n");
            (1, k)
        }
    };
    let pst = if b64_st != 0 { b64_st } else { st };
    if pst != 0 {
        return Err(unexpected(pst, 81, "base64 -d > \"$W/secret\""));
    }
    if key.is_empty() {
        return die(
            1,
            "\u{2717} Secret cicd-telemetry/github-otel-webhook is empty or missing".as_bytes(),
        );
    }
    let sig = sign(&key, payload.as_bytes());
    let (st, code) = capture(
        86,
        cmd(
            "curl",
            &[
                b"-s",
                b"-o",
                b"/dev/null",
                b"-w",
                b"%{http_code}",
                b"-X",
                b"POST",
                b"-H",
                b"X-GitHub-Event: workflow_run",
                b"-H",
                format!("X-GitHub-Delivery: smoke-{}", run_id).as_bytes(),
                b"-H",
                b"Content-Type: application/json",
                b"-H",
                format!("X-Hub-Signature-256: {}", sig).as_bytes(),
                b"--data-binary",
                &sc::cat(&[b"@", &payload_path]),
                &url,
            ],
        ),
    );
    if st != 0 {
        return Err(unexpected(st, 86, "code=\"$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'X-GitHub-Event: workflow_run' -H \"X-GitHub-Delivery: smoke-${run_id}\" -H 'Content-Type: application/json' -H \"X-Hub-Signature-256: ${sig}\" --data-binary @\"$W/payload\" \"$URL\")\""));
    }
    if code != b"200" {
        return die(
            1,
            &sc::cat(&[
                "\u{2717} signed request got ".as_bytes(),
                &code,
                b", want 200",
            ]),
        );
    }
    say("\u{2713} signed sample event accepted (200)".as_bytes());
    let sent_at = now();

    // 3. this run's series reaches a count of 1 (up to ~2 minutes, measured
    //    live; allow SMOKE_METRIC_WAIT_S, default 240, by the clock).
    let wait: i64 = String::from_utf8_lossy(&sc::env_or("SMOKE_METRIC_WAIT_S", b"240"))
        .trim()
        .parse()
        .unwrap_or(0);
    let deadline = sent_at + wait;
    let mut n: Vec<u8>;
    let mut last_err: Vec<u8>;
    loop {
        let (st, v, e) = prom(&q);
        n = if st != 0 { b"0".to_vec() } else { v };
        last_err = e;
        if awk_ge_1(&n) {
            break;
        }
        if now() >= deadline {
            break;
        }
        sleep5(104)?;
    }
    if !awk_ge_1(&n) {
        warn(
            format!(
                "\u{2717} no run count for '{}' in Prometheus after {}s",
                run_name,
                now() - sent_at
            )
            .as_bytes(),
        );
        if !last_err.is_empty() {
            // tail -n 1 "$W/prom.err"
            let trimmed = sc::subst(last_err.clone());
            let last = match trimmed.iter().rposition(|&c| c == b'\n') {
                Some(i) => trimmed[i + 1..].to_vec(),
                None => trimmed,
            };
            warn(&sc::cat(&[b"  last query error: ", &last]));
        }
        return Err(1);
    }
    say(&sc::cat(&[
        "\u{2713} metric for this run in Prometheus (count ".as_bytes(),
        &n,
        format!(", after {}s)", now() - sent_at).as_bytes(),
    ]));

    // 4. trace appears in Tempo, WITHOUT the committer email
    let tq = jq::uri(
        format!(
            "{{ resource.service.name = \"github-actions\" && resource.cicd.pipeline.run.id = {} }}",
            run_id
        )
        .as_bytes(),
    );
    let (st, pods) = capture(
        121,
        cmd(
            "kubectl",
            &[
                b"-n",
                b"opentelemetry",
                b"get",
                b"pods",
                b"-l",
                b"app.kubernetes.io/name=tempo",
                b"-o",
                b"name",
            ],
        ),
    );
    if st != 0 {
        return Err(unexpected(st, 121, "tempo_pods=\"$(kubectl -n opentelemetry get pods -l app.kubernetes.io/name=tempo -o name)\""));
    }
    let pods = sc::ifs_split(&pods);
    let mut tid: Vec<u8> = Vec::new();
    let mut tpod: Vec<u8> = Vec::new();
    for _ in 0..24 {
        let now_s = now();
        for pod in &pods {
            let search = format!(
                "localhost:3200/api/search?q={}&limit=1&start={}&end={}",
                tq,
                now_s - 3600,
                now_s + 60
            );
            let (_, res) = capture_quiet(
                0,
                cmd(
                    "kubectl",
                    &[
                        b"-n",
                        b"opentelemetry",
                        b"exec",
                        pod,
                        b"--",
                        b"wget",
                        b"-qO-",
                        search.as_bytes(),
                    ],
                ),
            );
            // jq ... <<<"$res": the here-string adds a newline.
            tid = sc::subst(jq::first_trace_id(&sc::cat(&[&res, b"\n"])));
            if !tid.is_empty() {
                tpod = pod.clone();
                break;
            }
        }
        if !tid.is_empty() {
            break;
        }
        sleep5(130)?;
    }
    if tid.is_empty() {
        return die(
            1,
            format!(
                "\u{2717} no trace for run {} in Tempo after 2 minutes",
                run_id
            )
            .as_bytes(),
        );
    }
    let (st, trace) = capture(
        133,
        cmd(
            "kubectl",
            &[
                b"-n",
                b"opentelemetry",
                b"exec",
                &tpod,
                b"--",
                b"wget",
                b"-qO-",
                &sc::cat(&[b"localhost:3200/api/traces/", &tid]),
            ],
        ),
    );
    if st != 0 {
        return Err(unexpected(st, 133, "trace=\"$(kubectl -n opentelemetry exec \"$tpod\" -- wget -qO- \"localhost:3200/api/traces/${tid}\")\""));
    }
    if grep_dot(&trace, b"smoke@example.invalid") {
        return die(1, "\u{2717} committer email reached Tempo".as_bytes());
    }
    say(&sc::cat(&[
        format!("\u{2713} trace for run {} in Tempo (", run_id).as_bytes(),
        &tid,
        format!(", after {}s), committer email stripped", now() - sent_at).as_bytes(),
    ]));
    say(
        "\u{2713} PASS: CI telemetry works end to end (webhook -> collector -> Prometheus + Tempo)"
            .as_bytes(),
    );
    Ok(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn signs_like_github() {
        assert_eq!(
            sign(b"It's a Secret to Everybody", b"Hello, World!"),
            "sha256=757107ea0eb2509fc211221cce984b8a37570b6d7586c22c46f4379c8b043e17"
        );
    }

    #[test]
    fn iso_dates() {
        assert_eq!(iso_utc(0), "1970-01-01T00:00:00Z");
        assert_eq!(iso_utc(1_700_000_000), "2023-11-14T22:13:20Z");
        assert_eq!(iso_utc(951_782_400), "2000-02-29T00:00:00Z");
    }

    #[test]
    fn awk_comparison() {
        assert!(awk_ge_1(b"1"));
        assert!(awk_ge_1(b"2.5"));
        assert!(!awk_ge_1(b"0"));
        assert!(!awk_ge_1(b"0.5"));
        assert!(!awk_ge_1(b""));
        // Not a number: a string comparison against "1".
        assert!(awk_ge_1(b"abc"));
    }
}
