// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! `alert-test`: fire one synthetic alert into Alertmanager, hold it, then
//! resolve it, to prove the whole delivery path end to end:
//! Alertmanager -> alertmanager-ntfy-bridge -> ntfy -> every subscribed device.
//!
//! The alert goes in through Alertmanager's own API (`POST /api/v2/alerts`),
//! posted by a short-lived Job in the monitoring namespace (see job_yaml),
//! created and removed with the caller's kubeconfig, so nothing new is exposed. It carries severity=warning, so the
//! normal ntfy route takes it, and a test_id label so two runs never merge.
//!
//!   bazel run //tools/gitops:alert-test                 # fire, hold 90s, resolve
//!   bazel run //tools/gitops:alert-test -- --hold 300   # hold 5 minutes
//!   bazel run //tools/gitops:alert-test -- --fire-only  # leave it firing
//!   bazel run //tools/gitops:alert-test -- --resolve <test_id>

use std::time::{Duration, SystemTime, UNIX_EPOCH};

use shell_compat as sc;

use super::common::*;

const AM_URL: &str =
    "http://prometheus-alertmanager.monitoring.svc.cluster.local:9093/api/v2/alerts";
/// curl, pinned by digest (Docker Hub, 2026-11-15).
const CURL_IMAGE: &str = "curlimages/curl:8.23.0@sha256:3fb7e13e5d179a845c97d78204f3f1064d1907037f26a3ebf91710571151fd93";
const ALERTNAME: &str = "VitruvianAlertTest";
const DEFAULT_HOLD_SECS: u64 = 90;

/// RFC 3339 UTC timestamp ("2026-11-15T06:40:00Z") for a Unix time, using the
/// civil-from-days algorithm (Howard Hinnant), since std has no formatter.
pub fn rfc3339(unix: u64) -> String {
    let days = (unix / 86_400) as i64;
    let secs = unix % 86_400;
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + if m <= 2 { 1 } else { 0 };
    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
        y,
        m,
        d,
        secs / 3600,
        (secs / 60) % 60,
        secs % 60
    )
}

/// The one-alert JSON array Alertmanager's v2 API takes. `ends_at` in the
/// future keeps it firing; `ends_at` <= now resolves it.
pub fn alert_json(test_id: &str, starts_at: u64, ends_at: u64) -> String {
    format!(
        concat!(
            "[{{\"labels\":{{\"alertname\":\"{name}\",\"severity\":\"warning\",",
            "\"namespace\":\"monitoring\",\"test_id\":\"{id}\"}},",
            "\"annotations\":{{\"summary\":\"Test alert {id} from bazel run //tools/gitops:alert-test. ",
            "It should disappear on its own once resolved.\"}},",
            "\"startsAt\":\"{s}\",\"endsAt\":\"{e}\"}}]"
        ),
        name = ALERTNAME,
        id = test_id,
        s = rfc3339(starts_at),
        e = rfc3339(ends_at),
    )
}

/// test_id must be plain digits: it goes into JSON unescaped.
pub fn valid_test_id(v: &[u8]) -> bool {
    !v.is_empty() && v.len() <= 20 && v.iter().all(|c| c.is_ascii_digit())
}

fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// A one-shot Job that POSTs `json` to Alertmanager from inside the cluster.
///
/// Why a Job and not `kubectl create --raw` through the API server proxy:
/// kubectl sends that body without `Content-Type: application/json`, and
/// Alertmanager answers 415 Unsupported Media Type (seen live, 2026-11-15).
/// curl in a pod sets the header and talks to the Service directly.
pub fn job_yaml(job: &str, json: &str) -> String {
    // The JSON goes in a single-quoted YAML scalar; alert_json never emits a
    // single quote (checked in the tests), so no escaping is needed.
    format!(
        r#"apiVersion: batch/v1
kind: Job
metadata:
  name: {job}
  namespace: monitoring
  labels:
    app.kubernetes.io/name: alert-test
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 600
  template:
    metadata:
      labels:
        app.kubernetes.io/name: alert-test
    spec:
      restartPolicy: Never
      securityContext:
        runAsNonRoot: true
        runAsUser: 100
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: post
          image: {image}
          env:
            - name: ALERT_JSON
              value: '{json}'
          args:
            - -fsS
            - -X
            - POST
            - -H
            - "Content-Type: application/json"
            - --data-binary
            - $(ALERT_JSON)
            - {url}
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
            limits:
              memory: 32Mi
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
"#,
        job = job,
        image = CURL_IMAGE,
        json = json,
        url = AM_URL,
    )
}

fn post(k: &[u8], job: &str, json: &str) -> Res<()> {
    let yaml = job_yaml(job, json);
    let st = feed(
        60,
        kubectl(k, &[b"apply", b"-f", b"-"]),
        yaml.as_bytes(),
        Some(to_stderr()),
    );
    if st != 0 {
        return die(
            st,
            b"ERROR: could not create the alert-test Job (is the cluster reachable?).",
        );
    }
    let target = format!("job/{}", job);
    let st = run(
        61,
        &mut kubectl(
            k,
            &[
                b"wait",
                b"-n",
                b"monitoring",
                b"--for=condition=complete",
                b"--timeout=120s",
                target.as_bytes(),
            ],
        ),
        true,
    );
    if st != 0 {
        run(
            62,
            &mut kubectl(k, &[b"logs", b"-n", b"monitoring", target.as_bytes()]),
            false,
        );
        return die(
            st,
            b"ERROR: the alert-test Job did not complete; Alertmanager may have refused the alert (log above).",
        );
    }
    // Done with it; ttlSecondsAfterFinished cleans up if this fails.
    run(
        63,
        &mut kubectl(
            k,
            &[
                b"delete",
                b"-n",
                b"monitoring",
                b"--wait=false",
                target.as_bytes(),
            ],
        ),
        true,
    );
    Ok(())
}

pub fn main(args: &[Vec<u8>]) -> i32 {
    match run_main(args) {
        Ok(c) | Err(c) => c,
    }
}

fn run_main(args: &[Vec<u8>]) -> Res<i32> {
    let mut hold = DEFAULT_HOLD_SECS;
    let mut fire_only = false;
    let mut resolve_id: Option<Vec<u8>> = None;
    let mut i = 0;
    while i < args.len() {
        let a = &args[i];
        if a == b"--fire-only" {
            fire_only = true;
        } else if a == b"--hold" || a == b"--resolve" {
            let v = args.get(i + 1).cloned().unwrap_or_default();
            if a == b"--hold" {
                hold = match test_int(&v) {
                    Some(n) if (0..=3600).contains(&n) => n as u64,
                    _ => return die(2, b"ERROR: --hold takes seconds, 0 to 3600."),
                };
            } else {
                if !valid_test_id(&v) {
                    return die(
                        2,
                        b"ERROR: --resolve takes the test_id the fire step printed.",
                    );
                }
                resolve_id = Some(v);
            }
            i += 1;
        } else {
            return die(
                2,
                &sc::cat(&[
                    b"ERROR: unknown argument '",
                    a,
                    b"' (expected --hold SECS, --fire-only or --resolve TEST_ID)",
                ]),
            );
        }
        i += 1;
    }

    default_kubeconfig(54)?;
    let k = kctx();
    need_tools(&["kubectl"], false)?;

    if let Some(id) = resolve_id {
        let id = String::from_utf8_lossy(&id).to_string();
        let t = now();
        // startsAt can be anything at or before the original; Alertmanager
        // matches on labels. endsAt = now resolves it.
        post(
            &k,
            &format!("alert-test-{}-resolve", id),
            &alert_json(&id, t.saturating_sub(3600), t),
        )?;
        say(format!("\u{2713} resolved {} test_id={}", ALERTNAME, id).as_bytes());
        say(b"  expect the ntfy notification to disappear within ~5 minutes (next group flush).");
        return Ok(0);
    }

    let start = now();
    let id = start.to_string();
    post(
        &k,
        &format!("alert-test-{}-fire", id),
        &alert_json(&id, start, start + 3600),
    )?;
    say(format!(
        "\u{2713} fired {} test_id={} (severity=warning)",
        ALERTNAME, id
    )
    .as_bytes());
    say(b"  expect it on ntfy (phone and web) within ~1 minute.");
    if fire_only {
        say(format!(
            "  left firing; it auto-resolves in 1h, or: bazel run //tools/gitops:alert-test -- --resolve {}",
            id
        )
        .as_bytes());
        return Ok(0);
    }
    say(format!("  holding {}s so you can see it, then resolving...", hold).as_bytes());
    std::thread::sleep(Duration::from_secs(hold));
    post(
        &k,
        &format!("alert-test-{}-resolve", id),
        &alert_json(&id, start, now()),
    )?;
    say(format!("\u{2713} resolved {} test_id={}", ALERTNAME, id).as_bytes());
    say(b"  expect the notification to disappear from every device within ~5 minutes.");
    say(b"  check: bazel run //tools/gitops:logs -- -n monitoring deploy/alertmanager-ntfy-bridge\n    should show \"ntfy: published ... (... VitruvianAlertTest ...)\" then \"ntfy: deleted ... (VitruvianAlertTest) -> 200\"");
    Ok(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rfc3339_known_instants() {
        assert_eq!(rfc3339(0), "1970-01-01T00:00:00Z");
        assert_eq!(rfc3339(951_782_400), "2000-02-29T00:00:00Z");
        // Expected values checked against Python's datetime.
        assert_eq!(rfc3339(1_794_725_999), "2026-11-15T06:59:59Z");
    }

    #[test]
    fn alert_json_shape() {
        let j = alert_json("123", 0, 60);
        assert!(j.starts_with("[{\"labels\":{\"alertname\":\"VitruvianAlertTest\""));
        assert!(j.contains("\"severity\":\"warning\""));
        assert!(j.contains("\"test_id\":\"123\""));
        assert!(j.contains("\"startsAt\":\"1970-01-01T00:00:00Z\""));
        assert!(j.contains("\"endsAt\":\"1970-01-01T00:01:00Z\""));
        assert!(j.ends_with("}]"));
    }

    #[test]
    fn job_carries_the_json_unchanged_and_sets_content_type() {
        let json = alert_json("42", 0, 60);
        assert!(
            !json.contains('\''),
            "alert_json must never emit a single quote"
        );
        let y = job_yaml("alert-test-42-fire", &json);
        assert!(y.contains(&format!("value: '{}'", json)));
        assert!(y.contains("\"Content-Type: application/json\""));
        assert!(y.contains("name: alert-test-42-fire"));
        assert!(y.contains(CURL_IMAGE));
        assert!(y.contains(AM_URL));
    }

    #[test]
    fn test_id_must_be_digits() {
        assert!(valid_test_id(b"1794725999"));
        assert!(!valid_test_id(b""));
        assert!(!valid_test_id(b"12a"));
        assert!(!valid_test_id(b"1\",\"x"));
    }
}
