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

//! The installer's and the launcher's tests: a throwaway vitruvian-core
//! checkout with a real git history and an origin/main ref, wired the way
//! the repo is.
//!
//! The launcher in it is one of the repo's real launchers (hook.sh, or
//! proposed-hook.sh while it waits to replace hook.sh) with the list of
//! programs it tries replaced by stand-ins. For the Python launcher that is
//! its list of pythons, and the stand-in is a stub python; for the Rust one
//! it is its list of rustcs, and the stand-in is a stub rustc that "builds" a
//! stub guard. Either way these tests need neither python3 nor a compiler:
//! what they exercise is the installer and the launcher, not the guard's
//! decisions (launcher_test.rs also builds the real guard with a real rustc).
//! The repo's real .claude/settings.json and .agents/hooks.json are copied in
//! unchanged, so the wiring checks compare against the files as they are.

use std::collections::BTreeMap;
use std::ffi::OsString;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::process::Command;

use agent_guard::paths::{exists, getcwd, join, realpath};
use agent_guard::pyval::{dict, loads, s, PyVal};

use crate::pyjson::{dumps_indent, get_mut, set};
use crate::sys::mkdtemp;

pub const GIT_ENV: [(&str, &str); 6] = [
    ("GIT_AUTHOR_NAME", "t"),
    ("GIT_AUTHOR_EMAIL", "t@example.com"),
    ("GIT_COMMITTER_NAME", "t"),
    ("GIT_COMMITTER_EMAIL", "t@example.com"),
    ("GIT_CONFIG_NOSYSTEM", "1"),
    ("GIT_CONFIG_GLOBAL", "/dev/null"),
];

/// A file from the test's runfiles (the repo's hook files, policy.json).
pub fn runfile(rel: &str) -> String {
    runfile_opt(rel).unwrap_or_else(|| panic!("runfile {} not found", rel))
}

/// A file from the test's runfiles, if it is there.
pub fn runfile_opt(rel: &str) -> Option<String> {
    let mut bases = vec![getcwd()];
    for var in ["TEST_SRCDIR", "RUNFILES_DIR"] {
        if let Ok(d) = std::env::var(var) {
            bases.push(join(&d, "_main"));
        }
    }
    bases.iter().map(|base| join(base, rel)).find(|p| exists(p))
}

pub fn read(path: &str) -> String {
    fs::read_to_string(path).unwrap_or_else(|e| panic!("read {}: {}", path, e))
}

pub fn write(path: &str, text: &str) {
    if let Some(parent) = std::path::Path::new(path).parent() {
        fs::create_dir_all(parent).unwrap();
    }
    fs::write(path, text).unwrap_or_else(|e| panic!("write {}: {}", path, e));
}

/// A folder under /tmp, not TEST_TMPDIR: inside Bazel that sits below an
/// execroot whose MODULE.bazel would make the "outside" folders look inside.
pub fn tmpdir(prefix: &str) -> String {
    let base = if fs::metadata("/tmp").map(|m| m.is_dir()).unwrap_or(false) {
        "/tmp".to_string()
    } else {
        std::env::temp_dir().to_string_lossy().into_owned()
    };
    realpath(&mkdtemp(&base, prefix).unwrap())
}

/// The guard's answer, as the stand-ins give it: refuses `git stash`
/// (git-stash) and `go vet` (go) unless the policy hook.sh chose
/// (AGENT_GUARD_POLICY) puts the category in warn or off mode, and answers in
/// the caller's format (agy's has "toolCall"). It also says on stderr which
/// copy hook.sh said it was running (AGENT_GUARD_SOURCE), so a test can tell.
const STUB_ANSWER: &str = r##"in=$(cat)
echo "stub guard: source=$AGENT_GUARD_SOURCE" >&2
case $in in
*'git stash'*) cat=git-stash ;;
*'go vet'*) cat=go ;;
*) exit 0 ;;
esac
if tr -d ' \t\n' <"$AGENT_GUARD_POLICY" | grep -Eq "\"$cat\":\\{\"mode\":\"(warn|off)\""; then
  exit 0
fi
why="agent-guard (stub): $cat is refused"
case $in in
*'"toolCall"'*) printf '{"decision": "deny", "reason": "%s"}\n' "$why" ;;
*) printf '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "%s"}}\n' "$why" ;;
esac
"##;

/// What a test writes into a guard source to make it fail: a stub python
/// will not run it, a stub rustc will not build it.
pub const BROKEN: &str = "this does not compile (: an agent's half-finished edit\n";
/// What a test writes into src/main.rs for a guard that builds but exits 1.
pub const EXITS_1: &str = "// builds, then exits 1\n";

/// Stands in for python3 running agent_guard.py. The Python launcher runs it
/// as `"$py" -I -S -c "$boot" "$src"`, the tool call on stdin.
fn stub_python() -> String {
    format!(
        "#!/bin/sh\nsrc=$5\n\
[ -s \"$src/agent_guard.py\" ] || {{ echo \"stub python: no agent_guard.py in $src\" >&2; exit 1; }}\n\
if grep -q 'does not compile' \"$src/agent_guard.py\"; then echo \"stub python: $src/agent_guard.py will not run\" >&2; exit 1; fi\n\
{}",
        STUB_ANSWER
    )
}

/// Stands in for rustc. The Rust launcher's build() runs it twice, as
/// `rustc ... -o OUT SRC/lib.rs` and `rustc ... -o OUT SRC/main.rs`: for
/// main.rs it writes the stub guard to OUT. A source holding BROKEN does not
/// build; a main.rs holding EXITS_1 builds a guard that exits 1. Each call is
/// counted in $0.calls, so a test can see whether the launcher compiled.
fn stub_rustc() -> String {
    format!(
        r##"#!/bin/sh
echo "$*" >>"$0.calls"
out=
src=
while [ $# -gt 0 ]; do
  case $1 in
  -o) out=$2; shift ;;
  *.rs) src=$1 ;;
  esac
  shift
done
[ -s "$src" ] || {{ echo "stub rustc: no $src" >&2; exit 1; }}
if grep -q 'does not compile' "$src"; then echo "stub rustc: $src does not build" >&2; exit 1; fi
case $src in
*/main.rs)
  if grep -q 'then exits 1' "$src"; then
    printf '#!/bin/sh\nexit 1\n' >"$out"
  else
    cat >"$out" <<'GUARD'
#!/bin/sh
{}GUARD
  fi
  chmod 755 "$out"
  ;;
*) echo "an rlib" >"$out" ;;
esac
"##,
        STUB_ANSWER
    )
}

pub const HOOK_SH: &str = "tools/agent-guard/hook.sh";
pub const PROPOSED_HOOK_SH: &str = "tools/agent-guard/proposed-hook.sh";

/// AGENT_GUARD_TEST_SWAPPED=1: test the tree as it will be once James moves
/// proposed-hook.sh over hook.sh, without that move. Agents may not write
/// hook.sh (agent-guard refuses it, even in a scratch tree), so this is how
/// an agent proves a proposed launcher passes as the live one:
///   bazel test //tools/agent-guard/... --test_env=AGENT_GUARD_TEST_SWAPPED=1
pub fn swapped() -> bool {
    std::env::var("AGENT_GUARD_TEST_SWAPPED").map_or(false, |v| v == "1")
}

/// The file a launcher's runfile path names: as is, or with
/// AGENT_GUARD_TEST_SWAPPED, proposed-hook.sh for hook.sh.
pub fn launcher_file(rel: &str) -> String {
    if swapped() && rel == HOOK_SH {
        return runfile_opt(PROPOSED_HOOK_SH)
            .expect("AGENT_GUARD_TEST_SWAPPED=1, but there is no proposed-hook.sh");
    }
    runfile(rel)
}

/// The launchers this tree has: hook.sh, and proposed-hook.sh while it waits
/// for James to move it over hook.sh. Runfile paths, hook.sh first; with
/// AGENT_GUARD_TEST_SWAPPED, hook.sh alone (read from proposed-hook.sh).
pub fn launchers() -> Vec<String> {
    if swapped() {
        launcher_file(HOOK_SH);
        return vec![HOOK_SH.to_string()];
    }
    [HOOK_SH, PROPOSED_HOOK_SH]
        .iter()
        .filter(|rel| runfile_opt(rel).is_some())
        .map(|rel| rel.to_string())
        .collect()
}

/// Which guard a launcher runs.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Flavor {
    /// agent_guard.py, on one of a list of pythons.
    Python,
    /// src/lib.rs and src/main.rs, built with one of a list of rustcs.
    Rust,
}

const PYTHONS_BEGIN: &str = "# --- pythons: begin";
const PYTHONS_END: &str = "# --- pythons: end ---\n";
const RUSTCS_BEGIN: &str = "# --- rustcs: begin";
const RUSTCS_END: &str = "# --- rustcs: end ---\n";

pub fn flavor_of(text: &str) -> Flavor {
    if text.contains(RUSTCS_BEGIN) {
        Flavor::Rust
    } else if text.contains(PYTHONS_BEGIN) {
        Flavor::Python
    } else {
        panic!("the launcher has neither a pythons nor a rustcs block (the tests replace it)")
    }
}

impl Flavor {
    /// The launcher's last words when no stand-in it tried worked.
    pub fn nothing_ran(self) -> &'static str {
        match self {
            Flavor::Python => "no working python3",
            Flavor::Rust => "no copy of the guard would build or run",
        }
    }

    /// The guard's sources a checkout holds, relative to its root.
    pub fn guard_sources(self) -> &'static [&'static str] {
        match self {
            Flavor::Python => &["tools/agent-guard/agent_guard.py"],
            Flavor::Rust => &[
                "tools/agent-guard/src/lib.rs",
                "tools/agent-guard/src/main.rs",
            ],
        }
    }

    /// What `origin/main:` names to find main's guard: the file, or the folder.
    pub fn guard_on_main(self) -> &'static str {
        match self {
            Flavor::Python => "tools/agent-guard/agent_guard.py",
            Flavor::Rust => "tools/agent-guard/src",
        }
    }
}

/// The launcher at runfile rel, with the programs it tries replaced by stand_ins.
pub fn launcher_text_of(rel: &str, stand_ins: &[String]) -> String {
    let text = read(&launcher_file(rel));
    let (begin, end_marker, block) = match flavor_of(&text) {
        Flavor::Python => (
            PYTHONS_BEGIN,
            PYTHONS_END,
            format!("pythons=\"{}\"\n", stand_ins.join(" ")),
        ),
        Flavor::Rust => (
            RUSTCS_BEGIN,
            RUSTCS_END,
            format!(
                "rustcs() {{\n  for p in {}; do echo \"$p\"; done\n}}\n",
                stand_ins.join(" ")
            ),
        ),
    };
    let start = text
        .find(begin)
        .expect("the launcher lost its block markers");
    let end = text[start..]
        .find(end_marker)
        .expect("the launcher lost its block markers")
        + start
        + end_marker.len();
    format!("{}{}{}", &text[..start], block, &text[end..])
}

/// hook.sh, with the programs it tries replaced by stand_ins.
pub fn launcher_text(stand_ins: &[String]) -> String {
    launcher_text_of("tools/agent-guard/hook.sh", stand_ins)
}

/// The flavor of the repo's live launcher, hook.sh.
pub fn live_flavor() -> Flavor {
    flavor_of(&read(&launcher_file(HOOK_SH)))
}

pub fn git(cwd: &str, args: &[&str]) -> String {
    let out = Command::new("git")
        .arg("-C")
        .arg(cwd)
        .args(args)
        .envs(GIT_ENV)
        .output()
        .expect("git runs");
    assert!(
        out.status.success(),
        "git {:?} in {}: {}",
        args,
        cwd,
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8_lossy(&out.stdout).into_owned()
}

/// A fake checkout: MODULE.bazel, tools/agent-guard and both hook files,
/// committed, with refs/remotes/origin/main pointing at that commit.
pub struct Checkout {
    pub tmp: String,
    pub root: String,
    pub home: String,
    pub out: String,
    pub guard_dir: String,
    /// The stand-in for python3 or rustc, by flavor.
    pub stub: String,
    pub flavor: Flavor,
}

impl Checkout {
    /// With the repo's hook.sh, trying only the stand-in.
    pub fn new() -> Checkout {
        Checkout::with_launcher("tools/agent-guard/hook.sh", None, true)
    }

    /// With the given launcher (one of launchers()), trying only the stand-in.
    pub fn new_for(launcher: &str) -> Checkout {
        Checkout::with_launcher(launcher, None, true)
    }

    /// launcher: which of launchers() to install as the checkout's hook.sh;
    /// stand_ins: the programs it tries (default: the stub); with_git: a git
    /// checkout with an origin/main, or a bare folder.
    pub fn with_launcher(
        launcher: &str,
        stand_ins: Option<Vec<String>>,
        with_git: bool,
    ) -> Checkout {
        let tmp = tmpdir("agent-guard-checkout-");
        let flavor = flavor_of(&read(&launcher_file(launcher)));
        let co = Checkout {
            root: join(&tmp, "vitruvian-core"),
            home: join(&tmp, "home"),
            out: join(&tmp, "elsewhere"),
            guard_dir: join(&tmp, "vitruvian-core/tools/agent-guard"),
            stub: join(
                &tmp,
                match flavor {
                    Flavor::Python => "stub-python3",
                    Flavor::Rust => "stub-rustc",
                },
            ),
            flavor,
            tmp,
        };
        for d in [&co.guard_dir, &co.home, &co.out] {
            fs::create_dir_all(d).unwrap();
        }
        write(
            &co.stub,
            &match flavor {
                Flavor::Python => stub_python(),
                Flavor::Rust => stub_rustc(),
            },
        );
        fs::set_permissions(&co.stub, fs::Permissions::from_mode(0o755)).unwrap();
        co.write("MODULE.bazel", "module(name = \"vitruvian_core\")\n");
        let stand_ins = stand_ins.unwrap_or_else(|| vec![co.stub.clone()]);
        co.write(
            "tools/agent-guard/hook.sh",
            &launcher_text_of(launcher, &stand_ins),
        );
        // The Rust guard's sources whatever the launcher (the installer
        // compares them with origin/main's), and the Python one's for it.
        let mut sources = Flavor::Rust.guard_sources().to_vec();
        if flavor == Flavor::Python {
            sources.extend(Flavor::Python.guard_sources());
        }
        for rel in sources {
            co.write(
                rel,
                "// Stands in for the guard: the tests' stub answers instead.\n",
            );
        }
        co.write(
            "tools/agent-guard/policy.json",
            &read(&runfile("tools/agent-guard/policy.json")),
        );
        for rel in [".claude/settings.json", ".agents/hooks.json"] {
            co.write(rel, &read(&runfile(rel)));
        }
        if with_git {
            git(&co.root, &["init", "-q", "-b", "main"]);
            git(&co.root, &["add", "-A"]);
            git(&co.root, &["commit", "-q", "-m", "init", "--no-gpg-sign"]);
            git(
                &co.root,
                &["update-ref", "refs/remotes/origin/main", "HEAD"],
            );
        }
        co
    }

    /// Make the checkout's own copy of the guard fail (not build, or not run).
    pub fn break_guard(&self) {
        for rel in self.flavor.guard_sources() {
            self.write(rel, BROKEN);
        }
    }

    pub fn write(&self, rel: &str, text: &str) {
        write(&join(&self.root, rel), text);
    }

    pub fn append(&self, rel: &str, text: &str) {
        let path = join(&self.root, rel);
        let mut have = read(&path);
        have.push_str(text);
        write(&path, &have);
    }

    pub fn set_policy(&self, modes: &[(&str, &str)], commit: bool) {
        let mut data = loads(&read(&runfile("tools/agent-guard/policy.json"))).unwrap();
        let cats = get_mut(&mut data, "categories").unwrap();
        for (cat, mode) in modes {
            set(get_mut(cats, cat).unwrap(), "mode", s(mode));
        }
        self.write(
            "tools/agent-guard/policy.json",
            &(dumps_indent(&data, ": ", true) + "\n"),
        );
        if commit {
            self.commit_to_main("policy");
        }
    }

    pub fn commit_to_main(&self, message: &str) {
        git(&self.root, &["add", "-A"]);
        git(
            &self.root,
            &["commit", "-q", "-m", message, "--no-gpg-sign"],
        );
        git(
            &self.root,
            &["update-ref", "refs/remotes/origin/main", "HEAD"],
        );
    }
}

impl Drop for Checkout {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.tmp);
    }
}

/// The test process's environment without anything that would make a run
/// an agent's, or aim it: each test adds what it needs.
pub fn clean_env() -> BTreeMap<OsString, OsString> {
    std::env::vars_os()
        .filter(|(k, _)| {
            let k = k.to_string_lossy();
            !(["CLAUDECODE", "ANTIGRAVITY_AGENT", "GEMINI_CLI"].contains(&k.as_ref())
                || k.starts_with("ANTIGRAVITY_")
                || k.starts_with("AGENT_GUARD_")
                || k == "BUILD_WORKSPACE_DIRECTORY"
                || k == "CLAUDE_PROJECT_DIR"
                || k == "CLAUDE_CODE_SESSION_ID")
        })
        .collect()
}

/// Claude Code's PreToolUse payload for Bash.
pub fn claude(command: &str, cwd: &str) -> PyVal {
    dict(vec![
        ("session_id", s("test")),
        ("cwd", s(cwd)),
        ("hook_event_name", s("PreToolUse")),
        ("tool_name", s("Bash")),
        ("tool_input", dict(vec![("command", s(command))])),
    ])
}

/// agy 1.4.0's real PreToolUse payload for run_command (no top-level cwd).
pub fn agy(command: &str, cwd: &str) -> PyVal {
    dict(vec![
        (
            "toolCall",
            dict(vec![
                ("name", s("run_command")),
                (
                    "args",
                    dict(vec![
                        ("CommandLine", s(command)),
                        ("Cwd", s(cwd)),
                        ("WaitMsBeforeAsync", PyVal::Int("5000".into())),
                    ]),
                ),
            ]),
        ),
        ("stepIdx", PyVal::Int("0".into())),
        ("conversationId", s("test")),
        ("workspacePaths", PyVal::List(vec![s(cwd)])),
    ])
}

pub fn decision(out: &str, antigravity: bool) -> String {
    if out.is_empty() {
        return "allow".into();
    }
    let data = loads(out).expect("hook JSON");
    let v = if antigravity {
        data.get("decision")
    } else {
        data.get("hookSpecificOutput")
            .and_then(|h| h.get("permissionDecision"))
    };
    v.and_then(|v| v.as_str()).expect("a decision").to_string()
}
