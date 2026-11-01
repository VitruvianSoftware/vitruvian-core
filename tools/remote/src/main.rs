// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

//! Build-cache setup helper: `bazel run //tools/remote:setup`.
//!
//! Presents a menu of build caches (none / local / shared bazel-remote /
//! BuildBuddy) and writes your choice to user.bazelrc (git-ignored). Nothing
//! is enabled until you run it. See docs/guides/build-cache.md (and
//! docs/guides/remote-build.md for BuildBuddy/RBE).
//!
//! A port of the former tools/remote/setup.sh, line for line: the same flags,
//! prompts, messages, exit codes and files. It is std only and a single crate
//! on purpose, so it also builds with a bare `rustc --edition 2021
//! tools/remote/src/main.rs` where there is no Bazel yet (a cloud session's
//! first minute), and on the repo's Rust 1.75 toolchain.
//!
//! Where the script relied on `set -e`, a failed step prints what bash would
//! have and exits 1. Line numbers in those messages are the script's.

use std::env;
use std::fs;
use std::io::{self, BufRead, BufReader, IsTerminal, Write};
use std::path::{Path, PathBuf};
use std::process::{self, Command, Stdio};

/// Markers delimiting the block this tool manages in user.bazelrc (matched
/// literally, as whole lines). tools/doctor and tools/worktree read them too.
const MARK_BEGIN: &str = "# >>> build cache (managed by tools/remote:setup) — do not edit by hand";
const MARK_END: &str = "# <<< build cache (managed by tools/remote:setup)";
const SECRET_NAME: &str = "BUILDBUDDY_API_KEY";

const USAGE: &str = "Usage: bazel run //tools/remote:setup -- [flags]
  --cache <none|local|shared|buildbuddy>  Build cache to configure (prompted if omitted)
  --url <grpcs://host>                     Cache URL (shared bazel-remote)
  --provider <buildbuddy|custom>           RBE provider (implies --cache buildbuddy)
  --endpoint <grpcs://host>                gRPC endpoint (custom RBE provider)
  --header-name <name>                     Auth header name (default x-buildbuddy-api-key)
  --key <key>                              API key (NON-interactive/testing only; prefer the
                                           hidden prompt or the BUILDBUDDY_API_KEY env var)
  --yes                                    Accepted for non-interactive callers (no-op)
  --no-ci                                  Configure local only; skip CI secret/snippet
  --no-local-default                       Do NOT make --config=remotecache the default
                                           for plain bazel invocations (#506 opt-out)
  -h, --help                               Show this help
";

const MENU: &str = "Pick a build cache (opt-in; the default is none):
  1) none        no cache — builds run fully locally
  2) local       disk cache on THIS machine only
  3) shared      your team's self-hosted bazel-remote server (read-only)
  4) buildbuddy  BuildBuddy (cache + remote execution)
";

fn main() {
    process::exit(run());
}

/// The script's name for bash-style diagnostics (`<prog>: line N: ...`).
fn prog() -> String {
    env::args().next().unwrap_or_else(|| "setup".to_string())
}

/// What `set -e` does when a step fails: bash has already said why; stop.
fn die(msg: &str) -> ! {
    eprintln!("{msg}");
    process::exit(1);
}

/// strerror text, without Rust's " (os error N)" suffix.
fn strerror(e: &io::Error) -> String {
    let s = e.to_string();
    match s.find(" (os error ") {
        Some(i) => s[..i].to_string(),
        None => s,
    }
}

fn out(s: &str) {
    let mut o = io::stdout().lock();
    let _ = o.write_all(s.as_bytes());
    let _ = o.flush();
}

fn echo(s: &str) {
    out(&format!("{s}\n"));
}

/// Stdin, read the way bash's `read` consumes it.
struct Input {
    r: BufReader<io::Stdin>,
    tty: bool,
}

impl Input {
    fn new() -> Self {
        let tty = io::stdin().is_terminal();
        Input {
            r: BufReader::new(io::stdin()),
            tty,
        }
    }

    /// `read -r [-s] -p PROMPT VAR`: the prompt goes to stderr, and only when
    /// stdin is a terminal; `-s` turns echo off while reading. Returns the
    /// line with leading/trailing blanks trimmed (IFS whitespace, one
    /// variable) and whether a full line was read: at end of input `read`
    /// fails, though the variable still gets what it read.
    fn read(&mut self, prompt: &str, silent: bool) -> (String, bool) {
        // bash's `read -s` turns echo off itself; this port asks stty. If that
        // fails the key would be shown as it is typed, so it is not read at
        // all (it can still come from BUILDBUDDY_API_KEY or --key).
        let echo_off = silent && self.tty;
        if echo_off {
            term::trap_interrupt();
            if !stty("-echo") {
                term::release();
                eprintln!(
                    "Cannot hide the input (stty -echo failed), so the key is not read from the terminal.\nPass it in the BUILDBUDDY_API_KEY environment variable instead."
                );
                process::exit(2);
            }
        }
        if self.tty {
            eprint!("{prompt}");
            let _ = io::stderr().flush();
        }
        let mut buf = Vec::new();
        let got = self.r.read_until(b'\n', &mut buf).is_ok();
        let complete = got && buf.last() == Some(&b'\n');
        if complete {
            buf.pop();
        }
        if echo_off {
            stty("echo");
            term::release();
        }
        buf.retain(|&c| c != 0);
        let s = String::from_utf8_lossy(&buf);
        let t = s.trim_matches(|c| c == ' ' || c == '\t' || c == '\n');
        (t.to_string(), complete)
    }
}

/// Ctrl-C during the hidden key prompt must not leave the terminal with echo
/// off. The terminal state is saved before echo goes off, and a SIGINT
/// handler puts it back (tcsetattr is async-signal-safe) and then dies of the
/// signal as it would have. The termios struct is only saved and restored
/// whole, so it is kept as opaque bytes (big enough for Linux and macOS).
mod term {
    use std::sync::atomic::{AtomicBool, Ordering};

    const SIGINT: i32 = 2;
    const SIG_DFL: usize = 0;
    const TCSANOW: i32 = 0;

    #[repr(C, align(8))]
    struct Termios([u8; 256]);

    static mut SAVED: Termios = Termios([0; 256]);
    static HAVE: AtomicBool = AtomicBool::new(false);

    extern "C" {
        fn tcgetattr(fd: i32, t: *mut u8) -> i32;
        fn tcsetattr(fd: i32, action: i32, t: *const u8) -> i32;
        fn signal(sig: i32, handler: usize) -> usize;
        fn raise(sig: i32) -> i32;
    }

    extern "C" fn on_interrupt(_: i32) {
        // SAFETY: only async-signal-safe calls; SAVED is written before the
        // handler is installed and not again while it is.
        unsafe {
            if HAVE.load(Ordering::SeqCst) {
                tcsetattr(0, TCSANOW, std::ptr::addr_of!(SAVED) as *const u8);
            }
            signal(SIGINT, SIG_DFL);
            raise(SIGINT);
        }
    }

    pub fn trap_interrupt() {
        // SAFETY: SAVED is a buffer larger than any platform's termios.
        unsafe {
            if tcgetattr(0, std::ptr::addr_of_mut!(SAVED) as *mut u8) == 0 {
                HAVE.store(true, Ordering::SeqCst);
                signal(SIGINT, on_interrupt as extern "C" fn(i32) as usize);
            }
        }
    }

    pub fn release() {
        if HAVE.swap(false, Ordering::SeqCst) {
            // SAFETY: restores the default disposition.
            unsafe {
                signal(SIGINT, SIG_DFL);
            }
        }
    }
}

/// `stty <mode>` on the terminal that is our stdin.
fn stty(mode: &str) -> bool {
    Command::new("stty")
        .arg(mode)
        .stdin(Stdio::inherit())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// `command -v NAME` for a bare name: the first executable file on $PATH.
fn on_path(name: &str) -> bool {
    use std::os::unix::fs::PermissionsExt;
    let path = env::var_os("PATH").unwrap_or_default();
    env::split_paths(&path).any(|d| {
        let d = if d.as_os_str().is_empty() {
            PathBuf::from(".")
        } else {
            d
        };
        fs::metadata(d.join(name))
            .map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
            .unwrap_or(false)
    })
}

/// The lines of a file, each without its newline (a missing final newline
/// still ends a line, as awk and grep read it).
fn read_lines(p: &str) -> Vec<Vec<u8>> {
    let data = fs::read(p).unwrap_or_default();
    let mut lines: Vec<Vec<u8>> = data.split(|&c| c == b'\n').map(|l| l.to_vec()).collect();
    if data.is_empty() || data.ends_with(b"\n") {
        lines.pop();
    }
    lines
}

/// user.bazelrc holds the API key, so it (and its temp file) is written
/// 0600, or kept stricter if the user made it so. setup.sh left it at the
/// umask default (usually 0644), and its temp-file-and-rename undid a user's
/// own `chmod 600` on every run. The mode is read once, before this run
/// changes the file.
fn private_mode() -> u32 {
    use std::os::unix::fs::PermissionsExt;
    static MODE: std::sync::OnceLock<u32> = std::sync::OnceLock::new();
    *MODE.get_or_init(|| match fs::metadata("user.bazelrc") {
        Ok(m) if m.permissions().mode() & 0o600 != 0 => m.permissions().mode() & 0o600,
        _ => 0o600,
    })
}

fn is_private(p: &str) -> bool {
    p == "user.bazelrc" || p == "user.bazelrc.tmp"
}

/// Open for writing; a private file is created 0600 and set to private_mode.
fn open_for_write(p: &str, append: bool) -> io::Result<fs::File> {
    use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
    let mut o = fs::OpenOptions::new();
    o.create(true).write(true).append(append).truncate(!append);
    if is_private(p) {
        o.mode(0o600);
    }
    let f = o.open(p)?;
    if is_private(p) {
        f.set_permissions(fs::Permissions::from_mode(private_mode()))?;
    }
    Ok(f)
}

fn write_lines(p: &str, lines: &[Vec<u8>]) -> io::Result<()> {
    let mut v = Vec::new();
    for l in lines {
        v.extend_from_slice(l);
        v.push(b'\n');
    }
    open_for_write(p, false)?.write_all(&v)
}

fn contains(hay: &[u8], needle: &[u8]) -> bool {
    needle.is_empty() || hay.windows(needle.len()).any(|w| w == needle)
}

/// `>> file` / `> file`, or bash's redirection error and exit 1.
fn write_to(line: u32, p: &str, data: &str, append: bool) {
    let r = open_for_write(p, append).and_then(|mut f| f.write_all(data.as_bytes()));
    if let Err(e) = r {
        die(&format!("{}: line {line}: {p}: {}", prog(), strerror(&e)));
    }
}

/// `touch user.bazelrc`.
fn touch(p: &str) {
    if let Err(e) = open_for_write(p, true) {
        die(&format!("touch: cannot touch '{p}': {}", strerror(&e)));
    }
}

/// `mkdir -p DIR`.
fn mkdir_p(p: &str) {
    if let Err(e) = fs::create_dir_all(p) {
        die(&format!(
            "mkdir: cannot create directory '{p}': {}",
            strerror(&e)
        ));
    }
}

/// Remove any block this tool previously wrote to user.bazelrc (idempotent
/// switch). From the begin marker through the end marker, or to the end of
/// the file when the end marker is missing.
fn strip_managed_block() {
    if !Path::new("user.bazelrc").is_file() {
        return;
    }
    let mut skip = false;
    let mut kept = Vec::new();
    for l in read_lines("user.bazelrc") {
        if l == MARK_BEGIN.as_bytes() {
            skip = true;
        }
        if !skip {
            kept.push(l.clone());
        }
        if l == MARK_END.as_bytes() {
            skip = false;
        }
    }
    if let Err(e) = write_lines("user.bazelrc.tmp", &kept)
        .and_then(|_| fs::rename("user.bazelrc.tmp", "user.bazelrc"))
    {
        die(&format!(
            "{}: line 63: user.bazelrc: {}",
            prog(),
            strerror(&e)
        ));
    }
}

fn ensure_user_bazelrc_ignored() {
    if Path::new(".gitignore").is_file()
        && !read_lines(".gitignore")
            .iter()
            .any(|l| l == b"user.bazelrc")
    {
        write_to(70, ".gitignore", "user.bazelrc\n", true);
        echo("✓ Added user.bazelrc to .gitignore.");
    }
}

/// Every file under DIR whose content matches `bazel (build|test)`, as
/// `grep -rl` names them (DIR/relative/path). Symlinks met while recursing
/// are not followed, as grep -r does not. Sorted, for a stable listing.
fn workflows_running_bazel(dir: &Path, hits: &mut Vec<String>) {
    let Ok(rd) = fs::read_dir(dir) else { return };
    for ent in rd.flatten() {
        let p = ent.path();
        let Ok(m) = fs::symlink_metadata(&p) else {
            continue;
        };
        if m.is_dir() {
            workflows_running_bazel(&p, hits);
        } else if m.is_file() {
            let data = fs::read(&p).unwrap_or_default();
            if contains(&data, b"bazel build") || contains(&data, b"bazel test") {
                hits.push(p.to_string_lossy().into_owned());
            }
        }
    }
}

/// `${2:?}` on a flag given without its value.
fn need_value(args: &[String], i: usize, line: u32) -> String {
    match args.get(i + 1) {
        Some(v) if !v.is_empty() => v.clone(),
        _ => die(&format!(
            "{}: line {line}: 2: parameter null or not set",
            prog()
        )),
    }
}

/// `cd "${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel || pwd)}"`.
/// Returns the directory as `$PWD` then names it.
fn enter_workspace() -> PathBuf {
    let target = match env::var("BUILD_WORKSPACE_DIRECTORY") {
        Ok(d) if !d.is_empty() => d,
        _ => {
            let top = Command::new("git")
                .args(["rev-parse", "--show-toplevel"])
                .stderr(Stdio::null())
                .output()
                .ok()
                .filter(|o| o.status.success())
                .map(|o| {
                    let mut s = String::from_utf8_lossy(&o.stdout).into_owned();
                    while s.ends_with('\n') {
                        s.pop();
                    }
                    s
                })
                .filter(|s| !s.is_empty());
            match top {
                Some(t) => t,
                None => logical_cwd().to_string_lossy().into_owned(),
            }
        }
    };
    if let Err(e) = env::set_current_dir(&target) {
        die(&format!(
            "{}: line 14: cd: {target}: {}",
            prog(),
            strerror(&e)
        ));
    }
    let p = PathBuf::from(&target);
    if p.is_absolute() {
        p
    } else {
        env::current_dir().unwrap_or(p)
    }
}

/// `pwd`: $PWD when it names the current directory, else the physical one.
fn logical_cwd() -> PathBuf {
    let phys = env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    if let Some(pwd) = env::var_os("PWD") {
        let pwd = PathBuf::from(pwd);
        if pwd.is_absolute() && fs::canonicalize(&pwd).ok() == fs::canonicalize(&phys).ok() {
            return pwd;
        }
    }
    phys
}

fn run() -> i32 {
    let ws = enter_workspace();

    let mut cache = String::new();
    let mut url = String::new();
    let mut provider = String::new();
    let mut endpoint = String::new();
    let mut header_name = String::new();
    let mut key = String::new();
    let mut do_ci = true;
    let mut local_default = true;

    let args: Vec<String> = env::args().skip(1).collect();
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--cache" => cache = need_value(&args, i, 45),
            "--url" => url = need_value(&args, i, 46),
            "--provider" => provider = need_value(&args, i, 47),
            "--endpoint" => endpoint = need_value(&args, i, 48),
            "--header-name" => header_name = need_value(&args, i, 49),
            "--key" => key = need_value(&args, i, 50),
            "--yes" | "-y" => {
                i += 1;
                continue;
            }
            "--no-ci" => {
                do_ci = false;
                i += 1;
                continue;
            }
            "--no-local-default" => {
                local_default = false;
                i += 1;
                continue;
            }
            "-h" | "--help" => {
                out(USAGE);
                return 0;
            }
            other => {
                eprintln!("unknown argument: {other}");
                out(USAGE);
                return 2;
            }
        }
        i += 2;
    }

    // Legacy callers passing RBE flags directly imply the buildbuddy choice.
    if cache.is_empty() && !(provider.is_empty() && endpoint.is_empty()) {
        cache = "buildbuddy".to_string();
    }

    let mut input = Input::new();

    // --- Menu --------------------------------------------------------------
    if cache.is_empty() {
        out(MENU);
        let (choice, _) = input.read("Choice [1-4] (1): ", false);
        cache = match if choice.is_empty() {
            "1"
        } else {
            choice.as_str()
        } {
            "1" => "none",
            "2" => "local",
            "3" => "shared",
            "4" => "buildbuddy",
            _ => {
                eprintln!("Invalid choice: {choice}");
                return 2;
            }
        }
        .to_string();
    }

    match cache.as_str() {
        "none" => {
            strip_managed_block();
            echo("✓ No build cache configured — builds run fully locally.");
            echo("  Re-run 'bazel run //tools/remote:setup' anytime to pick one.");
            return 0;
        }
        "local" => {
            let Ok(home) = env::var("HOME") else {
                die(&format!("{}: line 108: HOME: unbound variable", prog()));
            };
            let base = ws
                .file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_else(|| "/".to_string());
            let dir = format!("{home}/.cache/{base}-bazel-disk");
            mkdir_p(&dir);
            touch("user.bazelrc");
            strip_managed_block();
            write_to(
                116,
                "user.bazelrc",
                &format!("{MARK_BEGIN}\ncommon --disk_cache={dir}\n{MARK_END}\n"),
                true,
            );
            ensure_user_bazelrc_ignored();
            echo(&format!("✓ Local disk cache enabled: {dir}"));
            echo("  Personal to this machine, written to user.bazelrc (git-ignored). Safe to delete the dir.");
            return 0;
        }
        "shared" => {
            if url.is_empty() {
                let (u, ok) = input.read(
                    "bazel-remote cache URL (e.g. grpcs://cache.example.com): ",
                    false,
                );
                if !ok {
                    return 1;
                }
                url = u;
            }
            if url.is_empty() {
                eprintln!("A cache URL is required for the shared cache.");
                return 2;
            }
            if key.is_empty() {
                key = input
                    .read(
                        "Auth key if the cache needs one (blank for none, input hidden): ",
                        true,
                    )
                    .0;
                echo("");
            }
            let hdr = if key.is_empty() {
                String::new()
            } else if header_name.is_empty() {
                "x-api-key".to_string()
            } else {
                header_name.clone()
            };
            touch("user.bazelrc");
            strip_managed_block();
            let mut block = format!(
                "{MARK_BEGIN}\ncommon --remote_cache={url}\ncommon --remote_upload_local_results=false\n"
            );
            if !hdr.is_empty() {
                block.push_str(&format!("common --remote_header={hdr}={key}\n"));
            }
            block.push_str(&format!("{MARK_END}\n"));
            write_to(139, "user.bazelrc", &block, true);
            ensure_user_bazelrc_ignored();
            echo(&format!("✓ Shared cache enabled (read-only): {url}"));
            echo("  Written to user.bazelrc (git-ignored). If it is ever unreachable, builds fall back to local.");
            echo(&format!("  CI should WRITE to it: add '--remote_cache={url}' (+ a write credential) to the CI bazel step."));
            return 0;
        }
        "buildbuddy" => strip_managed_block(), // clear any prior local/shared selection
        _ => {
            eprintln!("unknown cache: {cache} (use none|local|shared|buildbuddy)");
            return 2;
        }
    }

    // === BuildBuddy / Remote Build Execution (RBE): cache + remote execution

    // --- Provider ----------------------------------------------------------
    if provider.is_empty() {
        provider = input
            .read("RBE provider [buildbuddy/custom] (buildbuddy): ", false)
            .0;
        if provider.is_empty() {
            provider = "buildbuddy".to_string();
        }
    }
    let mut bes_results = String::new();
    match provider.as_str() {
        "buildbuddy" => {
            endpoint = "grpcs://remote.buildbuddy.io".to_string();
            bes_results = "https://app.buildbuddy.io/invocation/".to_string();
            if header_name.is_empty() {
                header_name = "x-buildbuddy-api-key".to_string();
            }
        }
        "custom" => {
            if endpoint.is_empty() {
                let (e, ok) = input.read("gRPC endpoint (e.g. grpcs://your.rbe.host): ", false);
                if !ok {
                    return 1;
                }
                endpoint = e;
            }
            if header_name.is_empty() {
                let (h, ok) = input.read("Auth header name (e.g. x-api-key): ", false);
                if !ok {
                    return 1;
                }
                header_name = h;
            }
            if endpoint.is_empty() {
                eprintln!("An endpoint is required for a custom provider.");
                return 2;
            }
        }
        _ => {
            eprintln!("unknown provider: {provider} (use buildbuddy|custom)");
            return 2;
        }
    }

    // --- API key (never echoed/logged) -------------------------------------
    if key.is_empty() {
        match env::var(SECRET_NAME) {
            Ok(k) if !k.is_empty() => key = k,
            _ => {
                key = input
                    .read(&format!("API key for {provider} (input hidden): "), true)
                    .0;
                echo("");
            }
        }
    }
    if key.is_empty() {
        eprintln!("No API key provided.");
        return 2;
    }

    // --- Committed, non-secret config: tools/remote.bazelrc ----------------
    // LATENT-FOOTGUN GUARD: this template regenerates a COMMITTED file. It
    // drifted once (older RBE image without the git>=2.28 fix; no remotecache
    // profile) and a routine setup run would have silently downgraded CI's RBE
    // config. Only rewrite when the endpoint actually differs from what is
    // committed; keep the template in lockstep with tools/remote.bazelrc when
    // either changes.
    let executor = format!("--remote_executor={endpoint}");
    let committed = Path::new("tools/remote.bazelrc").is_file()
        && read_lines("tools/remote.bazelrc")
            .iter()
            .any(|l| contains(l, executor.as_bytes()));
    if committed {
        echo(&format!(
            "✓ tools/remote.bazelrc already targets {endpoint} (left untouched)."
        ));
    } else {
        mkdir_p("tools");
        write_to(
            226,
            "tools/remote.bazelrc",
            &remote_bazelrc(&endpoint, &bes_results),
            false,
        );
        echo("✓ Wrote tools/remote.bazelrc (commit this — it is non-secret).");
    }

    // --- Secret config: user.bazelrc (git-ignored) -------------------------
    touch("user.bazelrc");
    // Idempotent: drop any prior header lines for this header before
    // re-adding. (strip_managed_block already ran at case entry, clearing the
    // managed block.) This also cleans up the config-scoped header lines older
    // setups wrote.
    let remote_hdr = format!("--remote_header={header_name}=");
    let bes_hdr = format!("--bes_header={header_name}=");
    let kept: Vec<Vec<u8>> = read_lines("user.bazelrc")
        .into_iter()
        .filter(|l| !contains(l, remote_hdr.as_bytes()) && !contains(l, bes_hdr.as_bytes()))
        .collect();
    if let Err(e) = write_lines("user.bazelrc.tmp", &kept)
        .and_then(|_| fs::rename("user.bazelrc.tmp", "user.bazelrc"))
    {
        die(&format!(
            "{}: line 236: user.bazelrc: {}",
            prog(),
            strerror(&e)
        ));
    }
    // Local-default shared cache (#506): make every plain bazel invocation on
    // this machine read AND write the BuildBuddy cache (cache-only — execution
    // stays local; RBE remains an explicit --config=remote). A dead/stale key
    // degrades gracefully: Bazel treats remote-cache errors as warnings and
    // the build continues locally. Opt out with --no-local-default; `--cache
    // none` removes everything.
    //
    // HEADER LINES ARE UNSCOPED (plain `common`) ON PURPOSE: writing them
    // under BOTH common:remote and common:remotecache doubled the header when
    // a dev ran the documented `bazel build --config=remote` on a machine with
    // the remotecache default — --remote_header values for the same name
    // COMMA-JOIN ("KEY,KEY"), corrupting auth. One unscoped line applies
    // exactly once no matter which config (or combination) expands, and is
    // inert with no remote endpoint configured.
    let mut block = format!("{MARK_BEGIN}\n");
    if local_default {
        block.push_str("common --config=remotecache\n");
    }
    block.push_str(&format!("common --remote_header={header_name}={key}\n"));
    block.push_str(&format!("common --bes_header={header_name}={key}\n"));
    block.push_str("common:remotecache --remote_upload_local_results\n");
    block.push_str(&format!("{MARK_END}\n"));
    write_to(260, "user.bazelrc", &block, true);
    echo("✓ Wrote the API key to user.bazelrc (git-ignored — do NOT commit).");
    if local_default {
        echo("✓ Shared cache is now the LOCAL DEFAULT (plain bazel reads + writes it; #506).");
    } else {
        echo("  Local default skipped (--no-local-default): use --config=remotecache explicitly.");
    }
    ensure_user_bazelrc_ignored();

    // --- CI: GitHub Actions secret + workflow snippet ----------------------
    if do_ci {
        echo("");
        echo("Configuring CI (GitHub Actions)…");
        if on_path("gh") && gh_authenticated() {
            if gh_secret_set(&key) {
                echo(&format!(
                    "✓ Set the GitHub Actions secret {SECRET_NAME} on this repo."
                ));
            } else {
                echo("! Could not set the secret (need repo admin?). Run it yourself:");
                echo(&format!(
                    "    printf '%s' '<your-key>' | gh secret set {SECRET_NAME}"
                ));
            }
        } else {
            echo("! gh CLI not found or not authenticated — set the secret manually:");
            echo(&format!(
                "    printf '%s' '<your-key>' | gh secret set {SECRET_NAME}"
            ));
        }

        echo("");
        echo("Add this step (or these flags) to your GitHub Actions Bazel job:");
        echo("------------------------------------------------------------------");
        echo("    - name: Build/test with RBE");
        echo("      env:");
        echo(&format!(
            "        {SECRET_NAME}: ${{{{ secrets.{SECRET_NAME} }}}}"
        ));
        echo(&format!(
            "      run: bazel test --config=remote --remote_header={header_name}=${SECRET_NAME} //..."
        ));
        echo("------------------------------------------------------------------");

        // Best-effort: point out existing workflows that run Bazel and should
        // get the flags.
        let wf = Path::new(".github/workflows");
        if wf.is_dir() {
            let mut hits = Vec::new();
            workflows_running_bazel(wf, &mut hits);
            hits.sort();
            if !hits.is_empty() {
                echo("Detected Bazel steps in these workflows — add the env + --config=remote flags to each:");
                for h in hits {
                    echo(&format!("  {h}"));
                }
            }
        }
    }

    // --- Summary -----------------------------------------------------------
    echo("");
    echo(&format!(
        "Done. Cache: buildbuddy — provider {provider} ({endpoint})."
    ));
    echo("  • Local:  bazel test --config=remote //...");
    echo(&format!("  • CI:     add the snippet above (secret {SECRET_NAME} is set automatically when gh is available)."));
    echo("  • Details: docs/guides/build-cache.md and docs/guides/remote-build.md.");
    0
}

/// `gh auth status >/dev/null 2>&1`.
fn gh_authenticated() -> bool {
    Command::new("gh")
        .args(["auth", "status"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// `printf '%s' "$KEY" | gh secret set BUILDBUDDY_API_KEY >/dev/null 2>&1`.
/// The key travels on stdin, never in argv (which `ps` shows to everyone).
/// Under pipefail a write gh refused counts as failure too.
fn gh_secret_set(key: &str) -> bool {
    let child = Command::new("gh")
        .args(["secret", "set", SECRET_NAME])
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
    let Ok(mut child) = child else { return false };
    let wrote = child
        .stdin
        .take()
        .map(|mut s| s.write_all(key.as_bytes()).is_ok())
        .unwrap_or(false);
    let ok = child.wait().map(|s| s.success()).unwrap_or(false);
    ok && wrote
}

/// The committed, non-secret tools/remote.bazelrc. Keep in lockstep with the
/// checked-in file when either changes.
fn remote_bazelrc(endpoint: &str, bes_results: &str) -> String {
    let mut s = String::new();
    let mut l = |line: &str| {
        s.push_str(line);
        s.push('\n');
    };
    l("# Remote build execution (RBE) — generated by `bazel run //tools/remote:setup`.");
    l("# Non-secret + committed. The API key lives in the git-ignored user.bazelrc.");
    l("# Opt in per build with `--config=remote` (never breaks offline/local builds).");
    l(&format!("common:remote --remote_executor={endpoint}"));
    l(&format!("common:remote --remote_cache={endpoint}"));
    l(&format!("common:remote --bes_backend={endpoint}"));
    if !bes_results.is_empty() {
        l(&format!("common:remote --bes_results_url={bes_results}"));
    }
    l("common:remote --remote_timeout=10m");
    l("common:remote --jobs=50");
    l("common:remote --remote_download_outputs=minimal");
    l("# Default Linux execution platform/container for RBE actions. The image must ship");
    l("# a modern glibc (>=2.28) for current Node/Python toolchains AND a modern git");
    l("# (>=2.28) for tests/tools that use `git init -b`, `git switch`, etc. Ubuntu");
    l("# 22.04 (rbe-ubuntu22-04) provides git 2.34 / glibc 2.35. Adjust to match your");
    l("# toolchains. NOTE: macOS targets cannot run on Linux RBE — keep them local.");
    l("# See docs/guides/remote-build.md.");
    l("common:remote --remote_default_exec_properties=OSFamily=linux");
    l("common:remote --remote_default_exec_properties=container-image=docker://gcr.io/flame-public/rbe-ubuntu22-04:latest");
    l("");
    l("# Cache-only profile (--config=remotecache): share the BuildBuddy remote cache +");
    l("# BES but WITHOUT remote execution — outputs stay local, actions run locally.");
    l("# Remote-cache I/O errors fall back to local execution; BES upload is fully");
    l("# async so it never blocks or fails the build.");
    l(&format!("common:remotecache --remote_cache={endpoint}"));
    l(&format!("common:remotecache --bes_backend={endpoint}"));
    if !bes_results.is_empty() {
        l(&format!(
            "common:remotecache --bes_results_url={bes_results}"
        ));
    }
    l("common:remotecache --bes_upload_mode=fully_async");
    l("common:remotecache --remote_timeout=10m");
    s
}
