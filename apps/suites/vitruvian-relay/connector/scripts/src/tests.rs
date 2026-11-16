// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//! The install, run against fake `launchctl`, `codesign`, `security`,
//! `plutil` and `node` in a temporary home. Each fake appends its name and
//! arguments to `calls.log`.

use super::*;
use crate::layout::{fake_package, rg_platform, test_dir};

/// A temp folder outside Bazel's output base: `node` there passes the
/// stable-node check, which refuses anything under an output base (where
/// `TEST_TMPDIR` is).
fn outside_dir(name: &str) -> PathBuf {
    let d = PathBuf::from("/tmp").join(format!("vrelay-install-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    d
}
use std::os::unix::fs::PermissionsExt;
use std::time::Duration;
use vitruvian_relay_connector::bridge::{locate_from, BridgeCommand};

const TEMPLATE: &str = include_str!("../com.vitruvian.vrelay.plist");
const LISTING: &str = "  1) 0123456789ABCDEF0123456789ABCDEF01234567 \"Apple Development: Someone (AAAAAAAAAA)\"\n  2) FEDCBA9876543210FEDCBA9876543210FEDCBA98 \"Developer ID Application: Some One (TEAM123456)\"\n     2 valid identities found\n";
const NO_IDENTITY: &str = "     0 valid identities found\n";
const UID: u32 = 501;

/// Removes a folder when dropped.
struct Rm(PathBuf);

impl Drop for Rm {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

struct World {
    t: PathBuf,
    home: PathBuf,
    install: Install,
}

impl Drop for World {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.t);
    }
}

impl World {
    fn calls(&self) -> String {
        std::fs::read_to_string(self.t.join("calls.log")).unwrap_or_default()
    }
    fn run(&self) -> (Result<()>, String) {
        let mut out = Vec::new();
        let r = install(&self.install, &mut out);
        (r, String::from_utf8(out).unwrap())
    }
}

fn script(path: &Path, body: &str) {
    std::fs::write(path, format!("#!/bin/sh\n{body}\n")).unwrap();
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755)).unwrap();
}

/// A home, the inputs in a fake runfiles tree, and fakes for every command.
/// `listing` is what `security find-identity` prints; `node_version` and
/// `probe_exit` are what the fake `node` answers.
fn world(name: &str, listing: &str, node_version: &str, probe_exit: i32) -> World {
    let t = outside_dir(name);
    let home = t.join("home");
    std::fs::create_dir_all(&home).unwrap();
    let log = t.join("calls.log");
    let log = log.display();
    let bin = t.join("bin");
    std::fs::create_dir_all(&bin).unwrap();
    let logs_dir = home.join(LOG_REL);
    // launchctl: `print` succeeds while loaded; bootstrap refuses to load
    // unless the log folder already exists (launchd never makes it).
    let loaded = t.join("loaded");
    script(
        &bin.join("launchctl"),
        &format!(
            r#"echo "launchctl $*" >> {log}
case "$1" in
  print) [ -e {loaded} ] || [ -e {t}/stuck ] ;;
  bootout) rm -f {loaded} ;;
  enable) rm -f {t}/disabled ;;
  bootstrap)
    [ -d {logs} ] || {{ echo "no log folder" >&2; exit 5; }}
    [ -e {t}/disabled ] && {{ echo "Service is disabled" >&2; exit 119; }}
    [ -e {t}/fail-bootstrap ] && {{ echo "Input/output error" >&2; exit 5; }}
    [ -e {t}/break-rg ] && find {share} -path '*/bin/rg' -exec rm {{}} +
    touch {loaded} ;;
  *) exit 0 ;;
esac"#,
            loaded = loaded.display(),
            logs = logs_dir.display(),
            t = t.display(),
            share = home.join(SHARE_REL).join("node_modules").display()
        ),
    );
    script(
        &bin.join("codesign"),
        // Signing (`--force`) fails while `sign-failures` counts down.
        &format!(
            r#"echo "codesign $*" >> {log}
if [ "$1" = "--force" ] && [ -s {t}/sign-failures ]; then
  n=$(cat {t}/sign-failures); echo $((n - 1)) > {t}/sign-failures
  [ "$n" -gt 0 ] && {{ echo "timestamp service unavailable" >&2; exit 1; }}
fi
exit 0"#,
            t = t.display()
        ),
    );
    std::fs::write(t.join("listing"), listing).unwrap();
    script(
        &bin.join("security"),
        &format!(
            r#"echo "security $*" >> {log}; cat {}"#,
            t.join("listing").display()
        ),
    );
    script(
        &bin.join("plutil"),
        &format!(
            r#"echo "plutil $*" >> {log}; [ ! -e {t}/fail-plutil ] || {{ echo "bad plist"; exit 1; }}"#,
            t = t.display()
        ),
    );
    script(
        &bin.join("node"),
        &format!(
            r#"if [ "$1" = "--version" ]; then echo {node_version}; exit 0; fi
if [ "$1" = "-p" ]; then echo "$0"; exit 0; fi
echo "node $1 $2" >> {log}
echo /found/rg
exit {probe_exit}"#
        ),
    );
    let runfiles = t.join("runfiles");
    let vrelay = runfiles.join(RUNFILES_VRELAY);
    std::fs::create_dir_all(vrelay.parent().unwrap()).unwrap();
    script(&vrelay, "echo vrelay");
    fake_package(
        &runfiles.join(RUNFILES_NODE_MODULES),
        &rg_platform().unwrap(),
    );
    let plist = runfiles.join(RUNFILES_PLIST);
    std::fs::create_dir_all(plist.parent().unwrap()).unwrap();
    std::fs::write(&plist, TEMPLATE).unwrap();
    let install = Install {
        home: home.clone(),
        uid: UID,
        inputs: Inputs::from_runfiles(&[runfiles]).unwrap(),
        tools: Tools {
            launchctl: bin.join("launchctl"),
            codesign: bin.join("codesign"),
            security: bin.join("security"),
            plutil: bin.join("plutil"),
        },
        node: bin.join("node"),
        unsigned: false,
        workspace: None,
        timing: Timing {
            bootout_wait: Duration::from_millis(400),
            sign_backoff: Duration::from_millis(10),
        },
    };
    World { t, home, install }
}

fn ok_world(name: &str) -> World {
    world(name, LISTING, "v22.12.0", 0)
}

#[test]
fn render_plist_fills_paths_and_args() {
    let p = render_plist(
        TEMPLATE,
        Path::new("/Users/a&b/.local/share/vrelay/vrelay"),
        &["run"],
        Path::new("/Users/a&b/Library/Logs/vrelay/vrelay.log"),
        "/opt/homebrew/bin:/usr/bin:/bin",
    );
    assert!(!p.contains("__"), "{p}");
    assert!(p.contains("<string>com.vitruvian.vrelay</string>"), "{p}");
    assert!(
        p.contains(
            "<string>/Users/a&amp;b/.local/share/vrelay/vrelay</string>\n\t\t<string>run</string>"
        ),
        "{p}"
    );
    assert_eq!(
        p.matches("<string>/Users/a&amp;b/Library/Logs/vrelay/vrelay.log</string>")
            .count(),
        2,
        "{p}"
    );
    assert!(p.contains("<key>KeepAlive</key>\n\t<true/>"), "{p}");
    assert!(p.contains("<key>RunAtLoad</key>\n\t<true/>"), "{p}");
}

#[test]
fn plist_path_includes_node_dir() {
    let path = plist_path_env(Path::new(
        "/Users/a/.local/share/mise/installs/node/22.12.0/bin/node",
    ))
    .unwrap();
    assert_eq!(
        path,
        "/Users/a/.local/share/mise/installs/node/22.12.0/bin:/usr/bin:/bin"
    );
    let p = render_plist(TEMPLATE, Path::new("/b"), &["run"], Path::new("/l"), &path);
    assert!(
        p.contains(&format!(
            "<key>EnvironmentVariables</key>\n\t<dict>\n\t\t<key>PATH</key>\n\t\t<string>{path}</string>"
        )),
        "{p}"
    );
    // A node in /usr/bin is not listed twice.
    assert_eq!(
        plist_path_env(Path::new("/usr/bin/node")).unwrap(),
        "/usr/bin:/bin"
    );
    // A colon would split PATH.
    let err = plist_path_env(Path::new("/opt/a:b/bin/node")).unwrap_err();
    assert!(err.contains(':'), "{err}");
}

#[test]
fn identity_is_the_first_developer_id_application() {
    let id = developer_id_identity(LISTING).unwrap();
    assert_eq!(id.hash, "FEDCBA9876543210FEDCBA9876543210FEDCBA98");
    assert_eq!(id.name, "Developer ID Application: Some One (TEAM123456)");
    assert_eq!(developer_id_identity(NO_IDENTITY), None);
    assert_eq!(developer_id_identity(""), None);
}

#[test]
fn install_fails_without_identity() {
    let w = world("no-identity", NO_IDENTITY, "v22.12.0", 0);
    let (r, _) = w.run();
    let err = r.unwrap_err();
    assert!(err.contains("Developer ID Application"), "{err}");
    assert!(err.contains("--unsigned"), "{err}");
    // It stopped before touching anything.
    assert!(!w.calls().contains("launchctl"), "{}", w.calls());
    assert!(!w.calls().contains("\ncodesign "), "{}", w.calls());
    assert!(!w.calls().starts_with("codesign "), "{}", w.calls());
    assert!(!w.home.join(SHARE_REL).exists());
    assert!(!Paths::for_home(&w.home).plist.exists());
}

#[test]
fn install_creates_log_dir() {
    let w = ok_world("log-dir");
    let (r, out) = w.run();
    r.unwrap();
    let logs = w.home.join(LOG_REL);
    let mode = std::fs::metadata(&logs).unwrap().permissions().mode() & 0o777;
    assert_eq!(mode, 0o700);
    // The fake launchctl refuses to bootstrap without it, so it was there
    // first.
    assert!(
        w.calls()
            .contains(&format!("launchctl bootstrap gui/{UID} ")),
        "{}",
        w.calls()
    );
    assert!(out.contains("Installed"), "{out}");
    // Final review I5: how to pause, and that an edit needs a reload.
    for needle in ["vrelay pause", "vrelay resume", "vrelay reload", "rules.toml"] {
        assert!(out.contains(needle), "{needle}: {out}");
    }
}

#[test]
fn install_tightens_an_existing_log_dir() {
    let w = ok_world("log-dir-loose");
    let logs = w.home.join(LOG_REL);
    std::fs::create_dir_all(&logs).unwrap();
    std::fs::set_permissions(&logs, std::fs::Permissions::from_mode(0o755)).unwrap();
    w.run().0.unwrap();
    let mode = std::fs::metadata(&logs).unwrap().permissions().mode() & 0o777;
    assert_eq!(mode, 0o700);
}

#[test]
fn unsigned_flag_skips_signing_with_warning() {
    let mut w = world("unsigned", NO_IDENTITY, "v22.12.0", 0);
    w.install.unsigned = true;
    let (r, out) = w.run();
    r.unwrap();
    assert!(!w.calls().contains("codesign"), "{}", w.calls());
    assert!(!w.calls().contains("security"), "{}", w.calls());
    assert!(
        out.contains("warning:") && out.contains("unsigned"),
        "{out}"
    );
    assert!(Paths::for_home(&w.home).bin.is_file());
}

#[test]
fn install_signs_and_loads_in_order() {
    let w = ok_world("order");
    let (r, out) = w.run();
    r.unwrap();
    let p = Paths::for_home(&w.home);
    let calls = w.calls();
    let lines: Vec<&str> = calls.lines().collect();
    let pos = |needle: &str| {
        lines
            .iter()
            .position(|l| l.starts_with(needle))
            .unwrap_or_else(|| panic!("no {needle:?} in {calls}"))
    };
    let sign = pos("codesign --force");
    assert!(
        lines[sign].contains("--identifier dev.vitruvian.vrelay")
            && lines[sign].contains("--sign FEDCBA9876543210FEDCBA9876543210FEDCBA98")
            && lines[sign].contains("--options runtime")
            && lines[sign].contains("--timestamp")
            && lines[sign].contains("--strip-disallowed-xattrs"),
        "{}",
        lines[sign]
    );
    let verify = pos("codesign --verify");
    let probe = pos("node --input-type=module");
    let bootout = pos(&format!("launchctl bootout gui/{UID}/com.vitruvian.vrelay"));
    let bootstrap = pos(&format!(
        "launchctl bootstrap gui/{UID} {}",
        p.plist.display()
    ));
    let enable = pos(&format!("launchctl enable gui/{UID}/com.vitruvian.vrelay"));
    let lint = pos("plutil -lint");
    // Everything that can fail (signing, the search check, the plist lint)
    // runs before the running agent is stopped. Enable comes before
    // bootstrap, so a service someone disabled can load again.
    assert!(sign < verify && verify < bootout, "{calls}");
    assert!(probe < bootout && lint < bootout, "{calls}");
    assert!(bootout < enable && enable < bootstrap, "{calls}");
    assert!(out.contains("Developer ID Application: Some One"), "{out}");
    let plist = std::fs::read_to_string(&p.plist).unwrap();
    assert!(
        plist.contains(&format!("<string>{}</string>", p.bin.display())),
        "{plist}"
    );
    let node_dir = w.install.node.parent().unwrap().display().to_string();
    assert!(
        plist.contains(&format!("<string>{node_dir}:/usr/bin:/bin</string>")),
        "{plist}"
    );
    assert!(
        plist.contains(&format!("<string>{}</string>", p.log.display())),
        "{plist}"
    );
}

#[test]
fn install_writes_a_bridge_json_that_vrelay_reads() {
    let w = ok_world("bridge-json");
    w.run().0.unwrap();
    let p = Paths::for_home(&w.home);
    let cmd = locate_from(&w.home, false, &[], None).unwrap();
    assert_eq!(
        cmd,
        BridgeCommand {
            node: w.install.node.clone(),
            entry: p.entry.clone(),
        }
    );
    assert!(cmd.entry.is_file());
    // The search binary is in the installed copy.
    assert!(crate::layout::find_rg(&p.node_modules, &rg_platform().unwrap()).is_ok());
    assert!(p.bin.is_file());
    let mode = std::fs::metadata(&p.bin).unwrap().permissions().mode();
    assert_eq!(mode & 0o111, 0o111);
}

#[test]
fn reinstall_replaces_the_package() {
    let w = ok_world("reinstall");
    w.run().0.unwrap();
    let p = Paths::for_home(&w.home);
    std::fs::write(p.node_modules.join("stale"), "x").unwrap();
    w.run().0.unwrap();
    assert!(!p.node_modules.join("stale").exists());
    assert!(p.entry.is_file());
    // Nothing staged is left behind.
    let names: Vec<_> = std::fs::read_dir(&p.share)
        .unwrap()
        .map(|e| e.unwrap().file_name().into_string().unwrap())
        .collect();
    let mut names = names;
    names.sort();
    assert_eq!(names, ["bridge.json", "node_modules", "vrelay"]);
}

#[test]
fn install_fails_when_search_cannot_run() {
    let w = world("probe-fails", LISTING, "v22.12.0", 1);
    let err = w.run().0.unwrap_err();
    assert!(err.contains("ripgrep"), "{err}");
    assert!(!w.calls().contains("launchctl"), "{}", w.calls());
    assert!(!Paths::for_home(&w.home).plist.exists());
}

#[test]
fn install_fails_when_the_package_has_no_rg() {
    let w = ok_world("no-rg");
    let rg =
        crate::layout::find_rg(&w.install.inputs.node_modules, &rg_platform().unwrap()).unwrap();
    std::fs::remove_file(rg).unwrap();
    let err = w.run().0.unwrap_err();
    assert!(err.contains("@vscode/ripgrep-"), "{err}");
    assert!(!w.calls().contains("launchctl"), "{}", w.calls());
}

#[test]
fn install_fails_on_old_node() {
    let w = world("old-node", LISTING, "v20.11.0", 0);
    let err = w.run().0.unwrap_err();
    assert!(err.contains("22.12"), "{err}");
    assert!(!w.calls().contains("launchctl"), "{}", w.calls());
}

#[test]
fn install_warns_about_rules_missing_new_hidden_defaults() {
    let w = ok_world("rules-warn");
    let state = w.home.join("Library/Application Support/vrelay");
    std::fs::create_dir_all(&state).unwrap();
    let rules = "hidden = [\"set_config_value\"]\nno_prompt = []\n";
    std::fs::write(state.join("rules.toml"), rules).unwrap();
    let (r, out) = w.run();
    r.unwrap();
    assert!(
        out.contains("warning:") && out.contains("track_ui_event"),
        "{out}"
    );
    assert_eq!(
        std::fs::read_to_string(state.join("rules.toml")).unwrap(),
        rules
    );
    // No rules file: no warning, nothing written.
    let w = ok_world("rules-none");
    let (r, out) = w.run();
    r.unwrap();
    assert!(
        !out.lines()
            .any(|l| l.starts_with("warning:") && l.contains("rules.toml")),
        "{out}"
    );
    assert!(!w
        .home
        .join("Library/Application Support/vrelay/rules.toml")
        .exists());
}

#[test]
fn uninstall_removes_agent_and_files_but_keeps_sign_in() {
    let w = ok_world("uninstall");
    w.run().0.unwrap();
    let state = w.home.join("Library/Application Support/vrelay");
    std::fs::create_dir_all(&state).unwrap();
    std::fs::write(state.join("token.json"), "{}").unwrap();
    let mut out = Vec::new();
    uninstall(&w.home, UID, &w.install.tools, &mut out).unwrap();
    let p = Paths::for_home(&w.home);
    assert!(!p.plist.exists());
    assert!(!p.share.exists());
    assert!(state.join("token.json").exists());
    assert!(p.log_dir.exists());
    assert!(w
        .calls()
        .contains(&format!("launchctl bootout gui/{UID}/com.vitruvian.vrelay")));
    // Again: nothing left to do, and that is fine.
    uninstall(&w.home, UID, &w.install.tools, &mut Vec::new()).unwrap();
}

#[test]
fn inputs_come_from_the_runfiles() {
    let t = test_dir("inputs");
    let err = Inputs::from_runfiles(&[t.join("nowhere")]).unwrap_err();
    assert!(
        err.contains("bazel run //apps/suites/vitruvian-relay/connector/scripts:install"),
        "{err}"
    );
}

#[test]
fn node_must_be_absolute_and_new_enough() {
    let t = outside_dir("resolve-node");
    let _rm = Rm(t.clone());
    let bin = t.join("bin");
    std::fs::create_dir_all(&bin).unwrap();
    script(&bin.join("node"), "echo v22.12.0");
    let path = format!("/nonexistent:{}", bin.display());
    assert_eq!(
        resolve_node(None, Some(&path), None).unwrap(),
        bin.join("node")
    );
    assert_eq!(
        resolve_node(Some(&bin.join("node")), Some("/nonexistent"), None).unwrap(),
        bin.join("node")
    );
    let err = resolve_node(None, Some("/nonexistent"), None).unwrap_err();
    assert!(err.contains("22.12") && err.contains("--node"), "{err}");
    let err = resolve_node(Some(Path::new("bin/node")), None, None).unwrap_err();
    assert!(err.contains("absolute"), "{err}");
    script(&bin.join("node"), "echo v18.0.0");
    assert!(resolve_node(None, Some(&path), None)
        .unwrap_err()
        .contains("22.12"));
}

#[test]
fn render_plist_substitutes_in_one_pass() {
    // A home whose name holds placeholder text keeps it, escaped as text.
    let p = render_plist(
        TEMPLATE,
        Path::new("/Users/__LOG__&__PATH__/vrelay"),
        &["__BIN__"],
        Path::new("/l/vrelay.log"),
        "/n:/usr/bin:/bin",
    );
    assert!(
        p.contains(
            "<string>/Users/__LOG__&amp;__PATH__/vrelay</string>\n\t\t<string>__BIN__</string>"
        ),
        "{p}"
    );
    assert_eq!(
        p.matches("<string>/l/vrelay.log</string>").count(),
        2,
        "{p}"
    );
    assert!(p.contains("<string>/n:/usr/bin:/bin</string>"), "{p}");
}

/// A fake `node` that answers 22.21.1; `-p` prints `exec_path` (what
/// `process.execPath` would say; default: the script itself).
fn fake_node(dir: &Path, exec_path: Option<&Path>) -> PathBuf {
    std::fs::create_dir_all(dir).unwrap();
    let node = dir.join("node");
    let exec = exec_path.map_or("$0".to_string(), |p| p.display().to_string());
    script(
        &node,
        &format!(r#"[ "$1" = "-p" ] && {{ echo "{exec}"; exit 0; }}; echo v22.21.1"#),
    );
    node
}

#[test]
fn a_node_in_a_bazel_tree_is_passed_over_for_a_stable_one() {
    let t = outside_dir("node-bazel-out");
    let _rm = Rm(t.clone());
    // The repo's bazel_env node: a launcher under bazel-out.
    let bazel = fake_node(
        &t.join("ws/bazel-out/bazel_env-opt/bin/tools/bazel_env/bin"),
        None,
    );
    // A launcher outside that runs a node in Bazel's output base.
    let ob = t.join("output_base");
    std::fs::create_dir_all(ob.join("execroot")).unwrap();
    std::fs::create_dir_all(ob.join("external/nodejs/bin")).unwrap();
    std::fs::write(ob.join("DO_NOT_BUILD_HERE"), "").unwrap();
    let shim = fake_node(
        &t.join("shim/bin"),
        Some(&ob.join("external/nodejs/bin/node")),
    );
    // One in the checkout itself.
    let ws = t.join("ws");
    let in_ws = fake_node(&ws.join("tools/bin"), None);
    let stable = fake_node(&t.join("opt/homebrew/bin"), None);
    let path = [&bazel, &shim, &in_ws, &stable]
        .iter()
        .map(|n| n.parent().unwrap().display().to_string())
        .collect::<Vec<_>>()
        .join(":");
    assert_eq!(resolve_node(None, Some(&path), Some(&ws)).unwrap(), stable);
}

#[test]
fn only_bazel_nodes_is_an_error_that_says_to_pass_node() {
    let t = outside_dir("node-bazel-only");
    let _rm = Rm(t.clone());
    let bazel = fake_node(&t.join("ws/bazel-out/k8-opt/bin"), None);
    let path = bazel.parent().unwrap().display().to_string();
    let err = resolve_node(None, Some(&path), None).unwrap_err();
    for want in ["--node", "bazel-out", "Homebrew", "mise"] {
        assert!(err.contains(want), "{want}: {err}");
    }
    // Named with --node, it is refused too.
    let err = resolve_node(Some(&bazel), None, None).unwrap_err();
    assert!(err.contains("--node") && err.contains("bazel-out"), "{err}");
}

#[test]
fn install_refuses_a_node_in_a_bazel_tree() {
    let mut w = ok_world("install-bazel-node");
    w.install.node = fake_node(&w.t.join("bazel-out/bin"), None);
    let err = w.run().0.unwrap_err();
    assert!(err.contains("bazel-out"), "{err}");
    assert!(!w.calls().contains("launchctl"), "{}", w.calls());
}

#[test]
fn a_failing_check_leaves_the_running_agent_alone() {
    let w = ok_world("lint-fails");
    std::fs::write(w.t.join("fail-plutil"), "").unwrap();
    let (r, _) = w.run();
    let err = r.unwrap_err();
    assert!(
        err.contains("plutil") && err.contains("keeps running"),
        "{err}"
    );
    assert!(!w.calls().contains("launchctl"), "{}", w.calls());
    let p = Paths::for_home(&w.home);
    assert!(!p.plist.exists() && !p.bin.exists() && !p.bridge_json.exists());
    // Nothing staged is left.
    let left: Vec<_> = std::fs::read_dir(&p.share)
        .unwrap()
        .map(|e| e.unwrap().file_name())
        .collect();
    assert!(left.is_empty(), "{left:?}");
}

#[test]
fn a_failure_after_stopping_says_vrelay_is_stopped() {
    let w = ok_world("bootstrap-fails");
    std::fs::write(w.t.join("fail-bootstrap"), "").unwrap();
    let err = w.run().0.unwrap_err();
    assert!(err.contains("Input/output error"), "{err}");
    assert!(
        err.contains("vrelay is stopped") && err.contains("install again"),
        "{err}"
    );
}

#[test]
fn a_disabled_service_is_enabled_and_loads() {
    let w = ok_world("disabled");
    std::fs::write(w.t.join("disabled"), "").unwrap();
    w.run().0.unwrap();
    assert!(w.t.join("loaded").exists());
}

#[test]
fn a_stop_timeout_cleans_the_staged_copy() {
    let w = ok_world("stuck");
    w.run().0.unwrap();
    let p = Paths::for_home(&w.home);
    let before = std::fs::read(&p.bin).unwrap();
    std::fs::write(w.t.join("stuck"), "").unwrap();
    let err = w.run().0.unwrap_err();
    assert!(
        err.contains("did not stop") && err.contains("Nothing was replaced"),
        "{err}"
    );
    let mut names: Vec<_> = std::fs::read_dir(&p.share)
        .unwrap()
        .map(|e| e.unwrap().file_name().into_string().unwrap())
        .collect();
    names.sort();
    assert_eq!(names, ["bridge.json", "node_modules", "vrelay"]);
    assert_eq!(std::fs::read(&p.bin).unwrap(), before);
}

#[test]
fn signing_retries_the_timestamp_server_three_times() {
    let w = ok_world("sign-retry");
    std::fs::write(w.t.join("sign-failures"), "2").unwrap();
    w.run().0.unwrap();
    assert_eq!(
        w.calls().matches("codesign --force").count(),
        3,
        "{}",
        w.calls()
    );
    let w = ok_world("sign-gives-up");
    std::fs::write(w.t.join("sign-failures"), "9").unwrap();
    let err = w.run().0.unwrap_err();
    assert!(
        err.contains("timestamp service unavailable") && err.contains("keeps running"),
        "{err}"
    );
    assert_eq!(
        w.calls().matches("codesign --force").count(),
        3,
        "{}",
        w.calls()
    );
}

#[test]
fn a_folder_with_execroot_and_external_but_no_marker_is_not_an_output_base() {
    let t = outside_dir("node-lookalike");
    let _rm = Rm(t.clone());
    // Someone's own folder that happens to hold both names.
    std::fs::create_dir_all(t.join("tools/execroot")).unwrap();
    std::fs::create_dir_all(t.join("tools/external")).unwrap();
    let node = fake_node(&t.join("tools/node/bin"), None);
    assert_eq!(unstable_node(&node, None), None);
    assert_eq!(resolve_node(Some(&node), None, None).unwrap(), node);
    // With Bazel's marker it is one, and --node is refused too.
    std::fs::write(t.join("tools/DO_NOT_BUILD_HERE"), "").unwrap();
    let why = unstable_node(&node, None).unwrap();
    assert!(why.contains("output base"), "{why}");
    let err = resolve_node(Some(&node), None, None).unwrap_err();
    assert!(
        err.contains("output base") && err.contains("--node"),
        "{err}"
    );
}

#[test]
fn search_lost_after_loading_says_vrelay_is_running_without_search() {
    let w = ok_world("rg-after-load");
    std::fs::write(w.t.join("break-rg"), "").unwrap();
    let err = w.run().0.unwrap_err();
    assert!(err.contains("installed and running"), "{err}");
    assert!(err.contains("search will not work"), "{err}");
    assert!(err.contains("run the install again"), "{err}");
    assert!(
        !err.contains("keeps running") && !err.contains("is stopped"),
        "{err}"
    );
    assert!(w.t.join("loaded").exists());
}
