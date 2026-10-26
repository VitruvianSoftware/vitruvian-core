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

//! The command: flags, discovery through `bazel query`, and writing (and
//! pruning) the per-app workflows — main.go's main(), discover(), writeApps()
//! and writeAtomic(), with their exact output and error text.

use std::io::Write;
use std::process::{Command, Stdio};

use crate::actionpins::Pins;
use crate::gostd;
use crate::render::{self, AppGroup, GenError, GENERATED_BANNER};
use crate::unit;

// ---------------------------------------------------------------------------
// Discovery: the Bazel graph IS the delivery registry (spec §4.1).
// ---------------------------------------------------------------------------

/// bazelRunner: run bazel, return its stdout. Injected so tests can drive
/// discovery against a fake.
pub type BazelRunner<'a> = dyn FnMut(&[String]) -> Result<Vec<u8>, String> + 'a;

/// LookPath, for a bare command name.
fn look_path(file: &str) -> Result<String, String> {
    use std::os::unix::fs::PermissionsExt;
    let find = |p: &str| -> Result<(), std::io::Error> {
        let m = std::fs::metadata(p)?;
        if m.is_dir() {
            return Err(std::io::Error::from_raw_os_error(21));
        }
        if m.permissions().mode() & 0o111 != 0 {
            return Ok(());
        }
        Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied))
    };
    let path = std::env::var("PATH").unwrap_or_default();
    // filepath.SplitList: an empty PATH has no entries.
    let dirs: Vec<&str> = if path.is_empty() {
        Vec::new()
    } else {
        path.split(':').collect()
    };
    for d in dirs {
        let d = if d.is_empty() { "." } else { d };
        let p = gostd::join(&[d, file]);
        if find(&p).is_ok() {
            if !gostd::is_abs(&p) {
                return Err(format!(
                    "exec: {}: cannot run executable found relative to current directory",
                    gostd::q(file)
                ));
            }
            return Ok(p);
        }
    }
    Err(format!(
        "exec: {}: executable file not found in $PATH",
        gostd::q(file)
    ))
}

/// execBazel: the production runner, with exec.Cmd's error text.
pub fn exec_bazel(bin: String, dir: String) -> impl FnMut(&[String]) -> Result<Vec<u8>, String> {
    move |args: &[String]| {
        use std::os::unix::process::{CommandExt, ExitStatusExt};
        // exec.Command looks a name up on PATH only when it is its own
        // filepath.Base, i.e. contains no '/'.
        if bin.is_empty() {
            return Err("exec: no command".into());
        }
        let program = if !bin.contains('/') {
            look_path(&bin)?
        } else {
            bin.clone()
        };
        if !dir.is_empty() {
            if let Err(e) = std::fs::metadata(&dir) {
                return Err(gostd::path_err("chdir", &dir, &e));
            }
        }
        // A relative program path is resolved against Dir, as the child's
        // execve after its chdir would.
        let spawn_path = if !dir.is_empty() && !gostd::is_abs(&program) {
            format!("{}/{}", dir, program)
        } else {
            program.clone()
        };
        let mut cmd = Command::new(spawn_path);
        cmd.arg0(&bin)
            .args(args)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit());
        if !dir.is_empty() {
            cmd.current_dir(&dir);
        }
        let out = cmd
            .output()
            .map_err(|e| gostd::path_err("fork/exec", &program, &e))?;
        if out.status.success() {
            return Ok(out.stdout);
        }
        let mut msg = if let Some(code) = out.status.code() {
            format!("exit status {}", code)
        } else if let Some(sig) = out.status.signal() {
            format!("signal: {}", gostd::signal_name(sig))
        } else {
            "exit status -1".into()
        };
        if out.status.core_dumped() {
            msg.push_str(" (core dumped)");
        }
        Err(msg)
    }
}

/// splitLabel: "//some/pkg:target" -> ("some/pkg", "target").
fn split_label(label: &str) -> Option<(&str, &str)> {
    let l = label.strip_prefix("@//").unwrap_or(label);
    let l = l.strip_prefix("//").unwrap_or(l);
    let i = l.rfind(':')?;
    Some((&l[..i], &l[i + 1..]))
}

/// discover: every delivery() unit's metadata JSON path, sorted.
pub fn discover(run: &mut BazelRunner) -> Result<Vec<String>, String> {
    let out = run(&[
        "query".into(),
        "attr(tags, \"delivery\", //...)".into(),
        "--output=label".into(),
    ])
    .map_err(|e| format!("bazel query for delivery units: {}", e))?;
    let text = gostd::go_lossy(&out);
    let mut labels: Vec<String> = text
        .split('\n')
        .map(|l| l.trim())
        .filter(|l| l.ends_with(".delivery_unit"))
        .map(|l| l.to_string())
        .collect();
    labels.sort();
    if labels.is_empty() {
        return Err("no delivery() units found by 'bazel query attr(tags, \"delivery\", //...)' — the tag, the macro, or the query drifted".into());
    }
    let mut build_args = vec!["build".to_string()];
    build_args.extend(labels.iter().cloned());
    run(&build_args).map_err(|e| format!("bazel build of delivery units: {}", e))?;
    let bin_out = run(&["info".into(), "bazel-bin".into()])
        .map_err(|e| format!("bazel info bazel-bin: {}", e))?;
    let bin_dir = gostd::go_lossy(&bin_out).trim().to_string();

    let mut paths = Vec::with_capacity(labels.len());
    for l in &labels {
        let (pkg, target) =
            split_label(l).ok_or_else(|| format!("unparseable label {}", gostd::q(l)))?;
        let base = format!("{}.json", target.strip_suffix("_unit").unwrap_or(target));
        paths.push(gostd::join(&[&bin_dir, pkg, &base]));
    }
    Ok(paths)
}

// ---------------------------------------------------------------------------
// Output.
// ---------------------------------------------------------------------------

fn random_u32() -> u32 {
    use std::collections::hash_map::RandomState;
    use std::hash::{BuildHasher, Hasher};
    let mut h = RandomState::new().build_hasher();
    h.write_u128(
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0),
    );
    h.finish() as u32
}

/// writeAtomic: same-directory temp file + rename; reports whether the bytes
/// changed.
pub fn write_atomic(path: &str, content: &str) -> Result<bool, String> {
    use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
    match gostd::read_file(path) {
        Ok(old) => {
            if old == content.as_bytes() {
                return Ok(false);
            }
        }
        Err((msg, e)) => {
            if !gostd::is_not_exist(&e) {
                return Err(format!("read {}: {}", path, msg));
            }
        }
    }
    let d = gostd::dir(path);
    gostd::mkdir_all(&d).map_err(|e| format!("mkdir {}: {}", d, e))?;
    let prefix = if d.ends_with('/') {
        format!("{}.delivery-gen-", d)
    } else {
        format!("{}/.delivery-gen-", d)
    };
    let mut tries = 0;
    let (mut f, tmp) = loop {
        let name = format!("{}{}", prefix, random_u32());
        match std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&name)
        {
            Ok(f) => break (f, name),
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists && tries < 10000 => {
                tries += 1;
                continue;
            }
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {
                return Err(format!(
                    "temp file: createtemp {}*: file already exists",
                    prefix
                ));
            }
            Err(e) => return Err(format!("temp file: {}", gostd::path_err("open", &name, &e))),
        }
    };
    struct Cleanup<'a>(&'a str);
    impl Drop for Cleanup<'_> {
        fn drop(&mut self) {
            let _ = std::fs::remove_file(self.0);
        }
    }
    let _cleanup = Cleanup(&tmp);
    if let Err(e) = f.write_all(content.as_bytes()) {
        return Err(format!(
            "write {}: {}",
            tmp,
            gostd::path_err("write", &tmp, &e)
        ));
    }
    // Close. (Rust reports no close(2) error; Go's "close %s" error path
    // has no reachable trigger on a regular file either.)
    drop(f);
    if let Err(e) = std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o644)) {
        return Err(format!(
            "chmod {}: {}",
            tmp,
            gostd::path_err("chmod", &tmp, &e)
        ));
    }
    if let Err(e) = std::fs::rename(&tmp, path) {
        return Err(format!(
            "rename onto {}: rename {} {}: {}",
            path,
            tmp,
            path,
            gostd::errno_text(&e)
        ));
    }
    Ok(true)
}

/// Pins are loaded on the first render, exactly once — like the Go
/// generator's sync.OnceValue.
pub struct PinSource {
    loader: Box<dyn Fn() -> Result<Pins, String>>,
    cached: Option<Pins>,
}

impl PinSource {
    pub fn new(loader: Box<dyn Fn() -> Result<Pins, String>>) -> Self {
        PinSource {
            loader,
            cached: None,
        }
    }

    pub fn fixed(p: Pins) -> Self {
        PinSource {
            loader: Box::new(|| Err("unreachable".into())),
            cached: Some(p),
        }
    }

    fn get(&mut self) -> Result<&Pins, GenError> {
        if self.cached.is_none() {
            // The Go generator loads through sync.OnceValue, which recovers a
            // panic in its function and re-panics it: the runtime then marks
            // the message " [recovered, repanicked]".
            let p = (self.loader)()
                .map_err(|m| GenError::Panic(format!("{} [recovered, repanicked]", m)))?;
            self.cached = Some(p);
        }
        Ok(self.cached.as_ref().unwrap())
    }
}

/// writeApps: render every app's workflow into dir and prune the generated
/// workflows no app renders any more.
pub fn write_apps(
    dir: &str,
    groups: &[AppGroup],
    phase: i64,
    pins: &mut PinSource,
) -> Result<(Vec<String>, Vec<String>), GenError> {
    let mut written = Vec::new();
    let mut removed = Vec::new();
    let mut keep = std::collections::HashSet::new();
    for g in groups {
        let path = gostd::join(&[dir, &g.file]);
        if let Ok(old) = gostd::read_file(&path) {
            if !contains_bytes(&old, GENERATED_BANNER.as_bytes()) {
                return Err(GenError::Msg(format!(
                    "{} exists and is not generated — refusing to overwrite it with app {}'s workflow; rename the app",
                    path,
                    gostd::q(&g.app)
                )));
            }
        }
        let p = pins.get()?;
        let body = render::render(&g.units, phase, &g.file, p).map_err(|e| match e {
            GenError::Msg(m) => GenError::Msg(format!("app {}: {}", gostd::q(&g.app), m)),
            panic => panic,
        })?;
        let changed = write_atomic(&path, &body)?;
        keep.insert(g.file.clone());
        if changed {
            written.push(g.file.clone());
        }
    }
    let mut entries: Vec<(String, bool)> = Vec::new();
    match std::fs::read_dir(dir) {
        Ok(rd) => {
            for e in rd.flatten() {
                let is_dir = e.file_type().map(|t| t.is_dir()).unwrap_or(false);
                entries.push((e.file_name().to_string_lossy().into_owned(), is_dir));
            }
        }
        Err(e) => {
            return Err(GenError::Msg(format!(
                "read {}: {}",
                dir,
                gostd::path_err("open", dir, &e)
            )))
        }
    }
    entries.sort();
    for (name, is_dir) in entries {
        if is_dir
            || keep.contains(&name)
            || !name.starts_with("delivery")
            || gostd::ext(&name) != ".yaml"
        {
            continue;
        }
        let full = gostd::join(&[dir, &name]);
        let body = gostd::read_file(&full)
            .map_err(|(m, _)| GenError::Msg(format!("read {}: {}", name, m)))?;
        if !contains_bytes(&body, GENERATED_BANNER.as_bytes()) {
            continue;
        }
        std::fs::remove_file(&full).map_err(|e| {
            GenError::Msg(format!(
                "remove stale {}: {}",
                name,
                gostd::path_err("remove", &full, &e)
            ))
        })?;
        removed.push(name);
    }
    Ok((written, removed))
}

fn contains_bytes(hay: &[u8], needle: &[u8]) -> bool {
    hay.windows(needle.len()).any(|w| w == needle)
}

/// resolveWorkspace: BUILD_WORKSPACE_DIRECTORY, then GITHUB_WORKSPACE, then
/// the cwd.
pub fn resolve_workspace() -> String {
    for k in ["BUILD_WORKSPACE_DIRECTORY", "GITHUB_WORKSPACE"] {
        if let Some(v) = std::env::var_os(k) {
            if !v.is_empty() {
                return v.to_string_lossy().into_owned();
            }
        }
    }
    gostd::getwd().unwrap_or_else(|| ".".into())
}

/// bazelBinary: --bazel, then GEN_BAZEL, then "bazel".
pub fn bazel_binary(flag_val: &str) -> String {
    if !flag_val.is_empty() {
        return flag_val.into();
    }
    if let Some(v) = std::env::var_os("GEN_BAZEL") {
        if !v.is_empty() {
            return v.to_string_lossy().into_owned();
        }
    }
    "bazel".into()
}

// ---------------------------------------------------------------------------
// Flags: the Go `flag` package's command line, error text and usage.
// ---------------------------------------------------------------------------

pub struct Flags {
    pub out_dir: String,
    pub bazel: String,
    pub phase: i64,
}

const USAGE_BAZEL: &str = "bazel binary to shell out to (default: $GEN_BAZEL, else 'bazel')";
const USAGE_OUT_DIR: &str =
    "directory the per-app delivery-<app>.yaml workflows are written to, relative to the workspace root";
const USAGE_PHASE: &str = "0 = shadow (orchestrate job only); 1 = + the push rung; >=2 = + release promotion, dispatch inputs and changelog";
const DEFAULT_OUT_DIR: &str = ".github/workflows";

fn usage(argv0: &str) -> String {
    let mut s = if argv0.is_empty() {
        "Usage:\n".to_string()
    } else {
        format!("Usage of {}:\n", argv0)
    };
    s.push_str(&format!("  -bazel string\n    \t{}\n", USAGE_BAZEL));
    s.push_str(&format!(
        "  -out-dir string\n    \t{} (default {})\n",
        USAGE_OUT_DIR,
        gostd::q(DEFAULT_OUT_DIR)
    ));
    s.push_str(&format!(
        "  -phase int\n    \t{} (default 2)\n",
        USAGE_PHASE
    ));
    s
}

/// flag.Parse with ExitOnError: Ok(flags), or Err(exit code) after printing
/// what Go prints.
pub fn parse_flags(argv0: &str, args: &[String], stderr: &mut dyn Write) -> Result<Flags, i32> {
    let mut f = Flags {
        out_dir: DEFAULT_OUT_DIR.into(),
        bazel: String::new(),
        phase: 2,
    };
    let fail = |msg: String, stderr: &mut dyn Write| -> i32 {
        let _ = writeln!(stderr, "{}", msg);
        let _ = write!(stderr, "{}", usage(argv0));
        2
    };
    let mut i = 0;
    while i < args.len() {
        let s = &args[i];
        let b = s.as_bytes();
        if b.len() < 2 || b[0] != b'-' {
            break;
        }
        let mut minuses = 1;
        if b[1] == b'-' {
            minuses = 2;
            if b.len() == 2 {
                break;
            }
        }
        let mut name = &s[minuses..];
        if name.is_empty() || name.starts_with('-') || name.starts_with('=') {
            return Err(fail(format!("bad flag syntax: {}", s), stderr));
        }
        i += 1;
        let mut value: Option<String> = None;
        if let Some(eq) = name.as_bytes()[1..].iter().position(|&c| c == b'=') {
            let eq = eq + 1;
            value = Some(name[eq + 1..].to_string());
            name = &name[..eq];
        }
        match name {
            "bazel" | "out-dir" | "phase" => {
                let v = match value {
                    Some(v) => v,
                    None => {
                        if i < args.len() {
                            i += 1;
                            args[i - 1].clone()
                        } else {
                            return Err(fail(format!("flag needs an argument: -{}", name), stderr));
                        }
                    }
                };
                match name {
                    "bazel" => f.bazel = v,
                    "out-dir" => f.out_dir = v,
                    _ => match gostd::parse_int0(&v) {
                        Ok(n) => f.phase = n,
                        Err(e) => {
                            let why = match e {
                                gostd::NumErr::Syntax => "parse error",
                                gostd::NumErr::Range => "value out of range",
                            };
                            return Err(fail(
                                format!(
                                    "invalid value {} for flag -{}: {}",
                                    gostd::q(&v),
                                    name,
                                    why
                                ),
                                stderr,
                            ));
                        }
                    },
                }
            }
            "help" | "h" => {
                let _ = write!(stderr, "{}", usage(argv0));
                return Err(0);
            }
            other => {
                return Err(fail(
                    format!("flag provided but not defined: -{}", other),
                    stderr,
                ))
            }
        }
    }
    Ok(f)
}

/// The Go runtime's report of an unrecovered panic (exit status 2). The
/// goroutine trace below the first line is Go's own and is not reproduced.
fn die_panic(msg: &str) -> i32 {
    let _ = std::io::stdout().flush();
    eprint!(
        "panic: {}\n\ngoroutine 1 [running]:\nmain.main()\n\t(delivery-gen, Rust port)\n",
        msg
    );
    2
}

/// main().
pub fn main_with_args(argv0: &str, args: &[String]) -> i32 {
    let flags = match parse_flags(argv0, args, &mut std::io::stderr()) {
        Ok(f) => f,
        Err(code) => return code,
    };
    let ws = resolve_workspace();
    let mut runner = exec_bazel(bazel_binary(&flags.bazel), ws.clone());
    let paths = match discover(&mut runner) {
        Ok(p) => p,
        Err(e) => {
            eprintln!("delivery-gen: {}", e);
            return 1;
        }
    };
    let units = match unit::load_units(&paths) {
        Ok(u) => u,
        Err(e) => {
            eprintln!("delivery-gen: {}", e);
            return 1;
        }
    };
    let groups = match render::group_by_app(&units) {
        Ok(g) => g,
        Err(e) => {
            eprintln!("delivery-gen: {}", e);
            return 1;
        }
    };
    let dir = if gostd::is_abs(&flags.out_dir) {
        flags.out_dir.clone()
    } else {
        gostd::join(&[&ws, &flags.out_dir])
    };
    let mut pins = PinSource::new(Box::new(Pins::load_default));
    let (written, removed) = match write_apps(&dir, &groups, flags.phase, &mut pins) {
        Ok(r) => r,
        Err(GenError::Panic(m)) => return die_panic(&m),
        Err(GenError::Msg(e)) => {
            eprintln!("delivery-gen: {}", e);
            return 1;
        }
    };
    let mut out = String::new();
    for g in &groups {
        let state = if written.contains(&g.file) {
            "REGENERATED"
        } else {
            "unchanged"
        };
        out.push_str(&format!(
            "delivery-gen: {} (app {}, {} unit(s), phase {}) — {}\n",
            gostd::join(&[&dir, &g.file]),
            g.app,
            g.units.len(),
            flags.phase,
            state
        ));
    }
    for f in &removed {
        out.push_str(&format!(
            "delivery-gen: {} — REMOVED (no app renders it any more)\n",
            gostd::join(&[&dir, f])
        ));
    }
    let mut so = std::io::stdout().lock();
    let _ = so.write_all(out.as_bytes());
    let _ = so.flush();
    0
}
