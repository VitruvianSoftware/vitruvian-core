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

//! The PreToolUse hook: the payload on stdin, the answer on stdout, a line in
//! ~/.local/state/agent-guard/log.jsonl.

use std::fs;
use std::io::Write;
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt, PermissionsExt};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::guard::{evaluate_tool, load_policy, render, resolve_cwd, tool_call, Decision, VERSION};
use crate::paths::{dirname, exists, home_dir, join};
use crate::pyval::{dumps, loads, JsonErr, PyVal};
use crate::redact::redact_for_log;
use crate::tamper::STATE_DIR_REL;

const LOG_MAX_BYTES: u64 = 10 * 1024 * 1024;

pub fn log_path(home: &str) -> String {
    join(&join(home, STATE_DIR_REL), "log.jsonl")
}

/// Append one record; logging must never break the agent.
pub fn write_log(home: &str, record: &PyVal) {
    let path = log_path(home);
    let dir = dirname(&path);
    let _ = (|| -> std::io::Result<()> {
        if !std::path::Path::new(&dir).is_dir() {
            fs::create_dir_all(dirname(&dir))?;
            match fs::DirBuilder::new().mode(0o700).create(&dir) {
                Ok(()) => {}
                Err(e)
                    if e.kind() == std::io::ErrorKind::AlreadyExists
                        && std::path::Path::new(&dir).is_dir() => {}
                Err(e) => return Err(e),
            }
        }
        if fs::metadata(&dir)?.permissions().mode() & 0o077 != 0 {
            fs::set_permissions(&dir, fs::Permissions::from_mode(0o700))?;
        }
        if let Ok(m) = fs::metadata(&path) {
            if m.len() > LOG_MAX_BYTES {
                let _ = fs::rename(&path, format!("{}.1", path));
            }
        }
        let mut f = fs::OpenOptions::new()
            .append(true)
            .create(true)
            .mode(0o600)
            .open(&path)?;
        if f.metadata()?.permissions().mode() & 0o077 != 0 {
            f.set_permissions(fs::Permissions::from_mode(0o600))?;
        }
        f.write_all(format!("{}\n", dumps(record, true)).as_bytes())?;
        Ok(())
    })();
}

/// `datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")`.
pub fn now() -> String {
    let d = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    let secs = d.as_secs() as i64;
    let micros = d.subsec_micros();
    let days = secs.div_euclid(86400);
    let rem = secs.rem_euclid(86400);
    // Howard Hinnant's civil_from_days.
    let z = days + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = if month <= 2 { y + 1 } else { y };
    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}.{:06}Z",
        year,
        month,
        day,
        rem / 3600,
        (rem % 3600) / 60,
        rem % 60,
        micros
    )
}

/// What a panic carried, as Python's `repr(exc)` would show the exception.
pub fn panic_repr(err: &(dyn std::any::Any + Send)) -> String {
    let msg = if let Some(s) = err.downcast_ref::<&str>() {
        s.to_string()
    } else if let Some(s) = err.downcast_ref::<String>() {
        s.clone()
    } else {
        "unknown".to_string()
    };
    match msg.split_once(": ") {
        Some((kind, rest))
            if !kind.is_empty() && kind.chars().all(|c| c.is_ascii_alphanumeric()) =>
        {
            format!("{}({})", kind, crate::pyutil::py_repr_str(rest))
        }
        _ => format!("RuntimeError({})", crate::pyutil::py_repr_str(&msg)),
    }
}

fn env_nonempty(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.is_empty())
}

/// Where policy.json sits beside the binary (or in its runfiles).
pub fn default_policy_path() -> String {
    let exe = std::env::current_exe()
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_default();
    let beside = join(&dirname(&exe), "policy.json");
    let mut candidates = vec![
        beside.clone(),
        format!("{}.runfiles/_main/tools/agent-guard/policy.json", exe),
    ];
    if let Some(r) = env_nonempty("RUNFILES_DIR") {
        candidates.push(join(&r, "_main/tools/agent-guard/policy.json"));
    }
    candidates.into_iter().find(|c| exists(c)).unwrap_or(beside)
}

/// The outcome of one hook run: what to print, and the exit code. A Python
/// crash (an uncaught exception outside the guarded part) is exit 1.
pub struct Outcome {
    pub stdout: String,
    pub stderr: String,
    pub code: i32,
}

fn crash(msg: &str) -> Outcome {
    Outcome {
        stdout: String::new(),
        stderr: format!(
            "Traceback (most recent call last):\n  agent-guard: {}\n",
            msg
        ),
        code: 1,
    }
}

pub fn main(argv: &[String], stdin: &[u8]) -> Outcome {
    if argv
        .first()
        .map_or(false, |a| a == "--version" || a == "-V")
    {
        return Outcome {
            stdout: format!("agent-guard {}\n", VERSION),
            stderr: String::new(),
            code: 0,
        };
    }
    let home = env_nonempty("AGENT_GUARD_HOME").unwrap_or_else(home_dir);
    let policy = env_nonempty("AGENT_GUARD_POLICY").unwrap_or_else(default_policy_path);
    let raw = match std::str::from_utf8(stdin) {
        Ok(s) => crate::pyutil::universal_newlines(s),
        Err(_) => return crash("UnicodeDecodeError: stdin is not UTF-8"),
    };
    let payload = if crate::pyutil::py_strip(&raw).is_empty() {
        PyVal::Dict(vec![])
    } else {
        match loads(&raw) {
            Ok(p) => p,
            Err(JsonErr::Value) => PyVal::Dict(vec![]),
            Err(JsonErr::Recursion) => {
                return crash("RecursionError: maximum recursion depth exceeded")
            }
        }
    };
    let payload = if payload.is_dict() {
        payload
    } else {
        PyVal::Dict(vec![])
    };
    let modes = match load_policy(Some(&policy)) {
        Ok(m) => m,
        Err(e) => return crash(&e.0),
    };
    let antigravity = payload.has("toolCall");
    let (decision, tool, text) = match catch_unwind(AssertUnwindSafe(|| {
        evaluate_tool(&payload, &modes, &home, None)
    })) {
        Ok(r) => r,
        Err(err) => {
            let mut error = panic_repr(err.as_ref());
            error = error.chars().take(500).collect();
            write_log(
                &home,
                &crate::pyval::dict(vec![
                    ("ts", PyVal::Str(now())),
                    ("event", PyVal::Str("error".into())),
                    ("error", PyVal::Str(error)),
                ]),
            );
            (
                Decision::allow("unknown"),
                tool_call(&payload).1,
                String::new(),
            )
        }
    };
    if !text.is_empty() || decision.decision != "allow" {
        let (cwd_text, session) = if antigravity {
            // agy sends no cwd or session_id: log the directory the guard
            // judged by ("" if none was given) and the conversation id.
            let (where_, known) = catch_unwind(AssertUnwindSafe(|| resolve_cwd(&payload, &home)))
                .unwrap_or((String::new(), false));
            (
                if known { where_ } else { String::new() },
                payload.get_or_none("conversationId"),
            )
        } else {
            let c = payload
                .get("cwd")
                .filter(|c| c.truthy())
                .map(|c| c.py_str())
                .unwrap_or_default();
            (c, payload.get_or_none("session_id"))
        };
        let session = if session.truthy() {
            session.py_str()
        } else {
            String::new()
        };
        let source = std::env::var("AGENT_GUARD_SOURCE").unwrap_or_default();
        let record = crate::pyval::dict(vec![
            ("ts", PyVal::Str(now())),
            (
                "agent",
                PyVal::Str(
                    if antigravity {
                        "antigravity"
                    } else {
                        "claude-code"
                    }
                    .into(),
                ),
            ),
            ("tool", PyVal::Str(tool)),
            ("cwd", PyVal::Str(cwd_text)),
            ("scope", PyVal::Str(decision.scope.clone())),
            (
                "category",
                decision
                    .category
                    .clone()
                    .map(PyVal::Str)
                    .unwrap_or(PyVal::None),
            ),
            ("op", PyVal::Str(decision.op.clone())),
            ("decision", PyVal::Str(decision.decision.clone())),
            ("command", PyVal::Str(redact_for_log(&text))),
            ("session", PyVal::Str(session.chars().take(64).collect())),
            ("source", PyVal::Str(source.chars().take(200).collect())),
        ]);
        write_log(&home, &record);
    }
    let stdout = match render(&decision, antigravity) {
        Some(out) => format!("{}\n", dumps(&out, false)),
        None => String::new(),
    };
    Outcome {
        stdout,
        stderr: String::new(),
        code: 0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn timestamp_shape() {
        let t = now();
        assert_eq!(t.len(), 27, "{}", t);
        assert!(t.ends_with('Z') && &t[4..5] == "-" && &t[10..11] == "T" && &t[19..20] == ".");
    }

    #[test]
    fn repr_of_a_panic() {
        let e: Box<dyn std::any::Any + Send> = Box::new("ValueError: embedded null byte");
        assert_eq!(panic_repr(e.as_ref()), "ValueError('embedded null byte')");
    }
}
