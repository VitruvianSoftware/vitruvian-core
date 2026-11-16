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

//! `bazel run //apps/suites/vitruvian-relay/connector/scripts:install`:
//! installs `vrelay` as a LaunchAgent for the person running it, the way
//! `apps/mobile/vitruvian-remote/macagent/scripts` installs the remote agent
//! (`render_plist`, `launchctl bootout` / `bootstrap gui/<uid>` / `enable`).
//!
//! What goes where:
//! - `~/.local/share/vrelay/vrelay`, signed with the Developer ID identity
//!   (identifier `dev.vitruvian.vrelay`). With no such identity the install
//!   fails, unless `--unsigned` says otherwise.
//! - `~/.local/share/vrelay/node_modules/`: the pinned desktop-commander and
//!   everything it imports, ripgrep's `rg` included (see [`layout`]).
//! - `~/.local/share/vrelay/bridge.json`: the absolute `node` (22.12 or
//!   newer) and desktop-commander's `dist/index.js`, read by
//!   `BridgeCommand::locate`.
//! - `~/Library/LaunchAgents/com.vitruvian.vrelay.plist`, from the template
//!   beside this crate. Its `PATH` starts with `node`'s folder, because
//!   launchd starts agents with a `PATH` that has no Homebrew or mise.
//! - `~/Library/Logs/vrelay/` (mode 0700), made before the agent is loaded:
//!   launchd does not make it, and the agent would never start.
//!
//! Every command it runs (`launchctl`, `codesign`, `security`, `plutil`,
//! `node`) comes in through [`Tools`] and [`Install::node`], so the tests run
//! the whole install against fakes in a temporary home.

pub mod layout;

use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::time::{Duration, Instant};

use vitruvian_relay_connector::bridge::check_node;
use vitruvian_relay_connector::config::Config;
use vitruvian_relay_connector::proc::output_within;
use vitruvian_relay_connector::rules;
use vitruvian_relay_connector::state::write_private;
use vitruvian_relay_connector::Result;

pub const LABEL: &str = "com.vitruvian.vrelay";
/// The code-signing identifier.
pub const IDENTIFIER: &str = "dev.vitruvian.vrelay";
/// Where the binary, the package and `bridge.json` go, relative to `HOME`.
pub const SHARE_REL: &str = ".local/share/vrelay";
/// The agent's log folder, relative to `HOME` (`vrelay`'s own default).
pub const LOG_REL: &str = "Library/Logs/vrelay";
pub const PLIST_REL_DIR: &str = "Library/LaunchAgents";

/// The inputs, relative to the runfiles folder.
pub const RUNFILES_VRELAY: &str = "_main/apps/suites/vitruvian-relay/connector/vrelay";
pub const RUNFILES_NODE_MODULES: &str =
    "_main/apps/suites/vitruvian-relay/connector/dc/node_modules";
pub const RUNFILES_PLIST: &str =
    "_main/apps/suites/vitruvian-relay/connector/scripts/com.vitruvian.vrelay.plist";

/// Where an install puts things, for one home folder.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Paths {
    pub share: PathBuf,
    pub bin: PathBuf,
    pub node_modules: PathBuf,
    pub entry: PathBuf,
    pub bridge_json: PathBuf,
    pub log_dir: PathBuf,
    pub log: PathBuf,
    pub plist: PathBuf,
}

impl Paths {
    pub fn for_home(home: &Path) -> Paths {
        let share = home.join(SHARE_REL);
        let node_modules = share.join("node_modules");
        let log_dir = home.join(LOG_REL);
        Paths {
            bin: share.join("vrelay"),
            entry: node_modules.join(layout::DC_PACKAGE).join(layout::DC_ENTRY),
            bridge_json: home.join(vitruvian_relay_connector::bridge::BRIDGE_JSON),
            log: log_dir.join("vrelay.log"),
            plist: home.join(PLIST_REL_DIR).join(format!("{LABEL}.plist")),
            node_modules,
            share,
            log_dir,
        }
    }
}

pub fn xml_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for ch in s.chars() {
        match ch {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            _ => out.push(ch),
        }
    }
    out
}

/// Fills the template in one pass: `__BIN__`, `__LOG__` and `__PATH__`
/// anywhere, and a line that is only `__ARGS__` becomes one `<string>` per
/// argument. A value is never searched again, so a path that itself holds
/// `__LOG__` stays as it is.
pub fn render_plist(
    template: &str,
    bin: &Path,
    args: &[&str],
    log: &Path,
    path_env: &str,
) -> String {
    let subs = [
        ("__BIN__", xml_escape(&bin.to_string_lossy())),
        ("__LOG__", xml_escape(&log.to_string_lossy())),
        ("__PATH__", xml_escape(path_env)),
    ];
    let mut out = String::with_capacity(template.len() + 256);
    for line in template.lines() {
        if line.trim() == "__ARGS__" {
            for a in args {
                out.push_str("\t\t<string>");
                out.push_str(&xml_escape(a));
                out.push_str("</string>\n");
            }
            continue;
        }
        let mut rest = line;
        while let Some(at) = rest.find("__") {
            out.push_str(&rest[..at]);
            let tail = &rest[at..];
            match subs.iter().find(|(ph, _)| tail.starts_with(ph)) {
                Some((ph, value)) => {
                    out.push_str(value);
                    rest = &tail[ph.len()..];
                }
                None => {
                    out.push_str("__");
                    rest = &tail[2..];
                }
            }
        }
        out.push_str(rest);
        out.push('\n');
    }
    out
}

/// The agent's `PATH`: `node`'s folder, then `/usr/bin:/bin`. A folder with
/// a `:` in it would split the list, so it is refused.
pub fn plist_path_env(node: &Path) -> Result<String> {
    const BASE: &str = "/usr/bin:/bin";
    match node.parent() {
        Some(d) if d.to_string_lossy().contains(':') => Err(format!(
            "{} has a ':' in its folder name, which would split the agent's PATH; \
             pass --node with a node in another folder",
            node.display()
        )),
        Some(d) if d != Path::new("/usr/bin") && d != Path::new("/bin") => {
            Ok(format!("{}:{BASE}", d.display()))
        }
        _ => Ok(BASE.to_string()),
    }
}

/// A code-signing identity from `security find-identity`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Identity {
    /// The certificate's SHA-1, which `codesign -s` takes unambiguously.
    pub hash: String,
    pub name: String,
}

/// The first "Developer ID Application" identity in a
/// `security find-identity -v -p codesigning` listing (as
/// `developer_id_identity` in `apps/desktop/vitruvian-atrium/build.sh`).
/// Lines look like `  1) <40 hex> "Developer ID Application: Name (TEAM)"`.
pub fn developer_id_identity(listing: &str) -> Option<Identity> {
    listing.lines().find_map(|line| {
        let (_, rest) = line.split_once(") ")?;
        let (hash, quoted) = rest.trim_start().split_once(' ')?;
        let name = quoted.trim().strip_prefix('"')?.strip_suffix('"')?;
        let is_hash = hash.len() == 40 && hash.chars().all(|c| c.is_ascii_hexdigit());
        (is_hash && name.starts_with("Developer ID Application:")).then(|| Identity {
            hash: hash.to_string(),
            name: name.to_string(),
        })
    })
}

/// The commands the install runs.
#[derive(Debug, Clone)]
pub struct Tools {
    pub launchctl: PathBuf,
    pub codesign: PathBuf,
    pub security: PathBuf,
    pub plutil: PathBuf,
}

impl Tools {
    pub fn system() -> Tools {
        Tools {
            launchctl: "/bin/launchctl".into(),
            codesign: "/usr/bin/codesign".into(),
            security: "/usr/bin/security".into(),
            plutil: "/usr/bin/plutil".into(),
        }
    }
}

/// What the install copies, found in the runfiles.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Inputs {
    pub vrelay: PathBuf,
    pub node_modules: PathBuf,
    pub plist_template: PathBuf,
}

impl Inputs {
    pub fn from_runfiles(dirs: &[PathBuf]) -> Result<Inputs> {
        dirs.iter()
            .map(|d| Inputs {
                vrelay: d.join(RUNFILES_VRELAY),
                node_modules: d.join(RUNFILES_NODE_MODULES),
                plist_template: d.join(RUNFILES_PLIST),
            })
            .find(|i| {
                i.vrelay.is_file()
                    && i.node_modules.join(layout::DC_PACKAGE).is_dir()
                    && i.plist_template.is_file()
            })
            .ok_or_else(|| {
                let looked: Vec<_> = dirs.iter().map(|d| d.display().to_string()).collect();
                format!(
                    "cannot find vrelay, desktop-commander and the plist template in the \
                     runfiles (looked in {}). Run it with: \
                     bazel run //apps/suites/vitruvian-relay/connector/scripts:install",
                    if looked.is_empty() {
                        "nothing".to_string()
                    } else {
                        looked.join(", ")
                    }
                )
            })
    }
}

const STABLE_NODE_ADVICE: &str = "pass --node /absolute/path/to/node with a node that stays \
     put, such as Homebrew's (`brew install node`, then /opt/homebrew/bin/node) or mise's real \
     binary (the path `mise which node` prints)";

/// What `node` says `process.execPath` is: the real binary behind a launcher
/// or shim.
fn exec_path(node: &Path) -> Option<PathBuf> {
    let out = output_within(
        Command::new(node).args(["-p", "process.execPath"]),
        Duration::from_secs(10),
        4096,
    )
    .ok()??;
    let p = String::from_utf8_lossy(&out.stdout).trim().to_string();
    (out.status.success() && p.starts_with('/')).then(|| PathBuf::from(p))
}

/// Why `node` would not last, if it would not: it is (or, behind a launcher,
/// runs) a binary in a Bazel output tree (`bazel-out`), in a Bazel output
/// base ([`is_output_base`]), or inside the repo
/// checkout `workspace`. Those go with a `bazel clean`, a removed worktree
/// or a garbage-collected output base, and the agent would then fail every
/// start. This is the repo's own bazel_env `node`, which direnv puts first
/// on PATH.
pub fn unstable_node(node: &Path, workspace: Option<&Path>) -> Option<String> {
    let mut seen = vec![node.to_path_buf()];
    seen.extend(std::fs::canonicalize(node));
    if let Some(e) = exec_path(node) {
        seen.extend(std::fs::canonicalize(&e));
        seen.push(e);
    }
    let workspaces: Vec<PathBuf> = workspace
        .into_iter()
        .flat_map(|w| {
            [w.to_path_buf()]
                .into_iter()
                .chain(std::fs::canonicalize(w))
        })
        .collect();
    for p in &seen {
        if p.components().any(|c| c.as_os_str() == "bazel-out") {
            return Some(format!(
                "{} is {} in a Bazel output tree (bazel-out)",
                node.display(),
                via(node, p)
            ));
        }
        if let Some(w) = workspaces.iter().find(|w| p.starts_with(w)) {
            return Some(format!(
                "{} is {} inside the repo checkout {}",
                node.display(),
                via(node, p),
                w.display()
            ));
        }
        if let Some(base) = p.ancestors().skip(1).find(|a| is_output_base(a)) {
            return Some(format!(
                "{} is {} in Bazel's output base {}",
                node.display(),
                via(node, p),
                base.display()
            ));
        }
    }
    None
}

/// A Bazel output base: `execroot/`, `external/`, and the
/// `DO_NOT_BUILD_HERE` file Bazel writes in every one. All three, so a
/// person's own folder that happens to hold the two names is not mistaken
/// for one.
fn is_output_base(dir: &Path) -> bool {
    dir.join("execroot").is_dir()
        && dir.join("external").is_dir()
        && dir.join("DO_NOT_BUILD_HERE").is_file()
}

fn via(node: &Path, p: &Path) -> String {
    if p == node {
        "a node".to_string()
    } else {
        format!("{}, a node", p.display())
    }
}

/// The `node` to write into `bridge.json` and the plist: `explicit`
/// (`--node`) if given, else the first on `PATH` that is absolute, lasts
/// (see [`unstable_node`]) and is Node 22.12 or newer; the others are
/// passed over and named if none is left. Not resolved through symlinks:
/// Homebrew's `/opt/homebrew/bin/node` keeps working across `brew upgrade`.
pub fn resolve_node(
    explicit: Option<&Path>,
    path: Option<&str>,
    workspace: Option<&Path>,
) -> Result<PathBuf> {
    if let Some(node) = explicit {
        if !node.is_absolute() {
            return Err(format!(
                "{} is not an absolute path: launchd starts vrelay from /, so pass \
                 --node /absolute/path/to/node",
                node.display()
            ));
        }
        if let Some(why) = unstable_node(node, workspace) {
            return Err(format!(
                "{why}, which can disappear and leave the agent unable to start. Instead, \
                 {STABLE_NODE_ADVICE}"
            ));
        }
        check_node(node)?;
        return Ok(node.to_path_buf());
    }
    let mut passed_over = Vec::new();
    for node in vitruvian_relay_connector::bridge::all_on_path("node", path) {
        if !node.is_absolute() {
            passed_over.push(format!("{} is not an absolute path", node.display()));
        } else if let Some(why) = unstable_node(&node, workspace) {
            passed_over.push(why);
        } else {
            match check_node(&node) {
                Ok(()) => return Ok(node),
                Err(e) => passed_over.push(e),
            }
        }
    }
    if passed_over.is_empty() {
        return Err(format!(
            "no `node` on PATH. desktop-commander needs Node.js 22.12 or newer: {STABLE_NODE_ADVICE}"
        ));
    }
    Err(format!(
        "no usable `node` on PATH:\n  {}\ndesktop-commander needs Node.js 22.12 or newer \
         that stays put: {STABLE_NODE_ADVICE}",
        passed_over.join("\n  ")
    ))
}

/// Waits the install allows itself.
#[derive(Debug, Clone, Copy)]
pub struct Timing {
    /// How long a booted-out agent may take to go.
    pub bootout_wait: Duration,
    /// Between signing attempts: this, then twice this (atrium's backoff).
    pub sign_backoff: Duration,
}

impl Default for Timing {
    fn default() -> Timing {
        Timing {
            bootout_wait: Duration::from_secs(10),
            sign_backoff: Duration::from_secs(1),
        }
    }
}

pub struct Install {
    pub home: PathBuf,
    pub uid: u32,
    pub inputs: Inputs,
    pub tools: Tools,
    pub node: PathBuf,
    /// `--unsigned`: install without signing, with a warning.
    pub unsigned: bool,
    /// The repo checkout (`BUILD_WORKSPACE_DIRECTORY`): no `node` from in it.
    pub workspace: Option<PathBuf>,
    pub timing: Timing,
}

/// How long the search check (`node` finding and running `rg`) may take.
const PROBE_TIMEOUT: Duration = Duration::from_secs(30);
/// How many times codesign is tried (the timestamp server can flake).
const SIGN_ATTEMPTS: u32 = 3;

/// The installer's search check (see the file).
pub const SEARCH_PROBE: &str = include_str!("search_probe.mjs");

const UNTOUCHED: &str = "Nothing was changed: a running vrelay keeps running.";
const NOT_REPLACED: &str = "Nothing was replaced, and the old vrelay may still be running. \
                            Run the install again.";
const STOPPED: &str = "vrelay is stopped now: fix this, then run the install again \
                       (bazel run //apps/suites/vitruvian-relay/connector/scripts:install).";

/// Everything checked and staged before the running agent is stopped.
struct Prepared {
    identity: Option<Identity>,
    platform: String,
    bin: PathBuf,
    node_modules: PathBuf,
    plist: PathBuf,
}

impl Prepared {
    fn discard(&self) {
        for p in [&self.bin, &self.node_modules, &self.plist] {
            let _ = remove_path(p);
        }
    }
}

pub fn install(i: &Install, out: &mut dyn Write) -> Result<()> {
    let p = Paths::for_home(&i.home);
    let prep = prepare(i, &p, out).map_err(|e| format!("{e}\n{UNTOUCHED}"))?;
    if let Err(e) = bootout(&i.tools, i.uid, i.timing.bootout_wait) {
        prep.discard();
        return Err(format!("{e}\n{NOT_REPLACED}"));
    }
    finish(i, &p, &prep).map_err(|e| format!("{e}\n{STOPPED}"))?;
    // It passed in staging, and a rename keeps pnpm's relative links, so
    // this should not fail; if it does, the agent is already running.
    let rg = layout::find_rg(&p.node_modules, &prep.platform).map_err(|e| {
        format!(
            "{e}\nvrelay is installed and running, but desktop-commander's search will not \
             work until this is fixed. To check: `{} tools` lists the tools, and a search \
             from Claude shows the error; run the install again to fix it (it checks search \
             before it stops the agent).",
            p.bin.display()
        )
    })?;

    say(
        out,
        &format!("Installed vrelay as the LaunchAgent {LABEL}."),
    );
    let signed = match &prep.identity {
        Some(id) => format!("signed by {}", id.name),
        None => "unsigned".to_string(),
    };
    say(out, &format!("  Binary:  {} ({signed})", p.bin.display()));
    say(out, &format!("  Node:    {}", i.node.display()));
    say(out, &format!("  Search:  {}", rg.display()));
    say(out, &format!("  Log:     {}", p.log.display()));
    say(out, &format!("  Plist:   {}", p.plist.display()));
    say(
        out,
        &format!(
            "It waits for a sign-in until you run `{} login`. To remove it: \
             bazel run //apps/suites/vitruvian-relay/connector/scripts:uninstall",
            p.bin.display()
        ),
    );
    let state = Config::from_lookup(|k| (k == "HOME").then(|| i.home.to_string_lossy().into()));
    say(
        out,
        &format!(
            "To stop remote calls at once: `{bin} pause` (no tools visible, every call \
             refused); `{bin} resume` undoes it. After editing {rules}, run `{bin} reload`: \
             the running agent keeps the rules it loaded until then. `{bin} status` shows \
             which are in use.",
            bin = p.bin.display(),
            rules = rules::rules_path(&state.dir).display(),
        ),
    );
    for w in rules::file_warnings(&state.dir) {
        say(out, &format!("warning: {w}"));
    }
    Ok(())
}

fn utf8(p: &Path) -> Result<&str> {
    p.to_str().ok_or_else(|| {
        format!(
            "{} is not UTF-8, which a LaunchAgent plist cannot name",
            p.display()
        )
    })
}

/// Every check that can fail, and the new copy staged beside the old one
/// (`vrelay.new`, `node_modules.new`, `com.vitruvian.vrelay.plist.new`):
/// signed, its search working, its plist linted. Nothing running is touched.
fn prepare(i: &Install, p: &Paths, out: &mut dyn Write) -> Result<Prepared> {
    let platform = layout::rg_platform()
        .ok_or("@vscode/ripgrep has no rg for this platform, so search would not work")?;
    if !i.node.is_absolute() {
        return Err(format!("{} is not an absolute path", i.node.display()));
    }
    if let Some(why) = unstable_node(&i.node, i.workspace.as_deref()) {
        return Err(format!("{why}. Instead, {STABLE_NODE_ADVICE}"));
    }
    check_node(&i.node)?;
    for path in [&i.node, &p.bin, &p.entry, &p.log, &p.plist] {
        utf8(path)?;
    }
    let path_env = plist_path_env(&i.node)?;
    let template = std::fs::read_to_string(&i.inputs.plist_template)
        .map_err(|e| format!("read {}: {e}", i.inputs.plist_template.display()))?;
    let plist_text = render_plist(&template, &p.bin, &["run"], &p.log, &path_env);
    let identity = if i.unsigned {
        say(
            out,
            "warning: installing unsigned (--unsigned). macOS ties what you allow vrelay \
             to do to its signature, so you may be asked again after every reinstall.",
        );
        None
    } else {
        Some(find_identity(&i.tools)?)
    };

    std::fs::create_dir_all(&p.share).map_err(|e| format!("create {}: {e}", p.share.display()))?;
    let prep = Prepared {
        identity,
        platform,
        bin: p.share.join("vrelay.new"),
        node_modules: p.share.join("node_modules.new"),
        plist: p.share.join(format!("{LABEL}.plist.new")),
    };
    // Left over from an install that was cut short.
    for s in [&prep.bin, &prep.node_modules, &prep.plist] {
        remove_path(s)?;
    }
    if let Err(e) = stage(i, &prep, &plist_text, &p.log_dir) {
        prep.discard();
        return Err(e);
    }
    Ok(prep)
}

fn stage(i: &Install, prep: &Prepared, plist_text: &str, log_dir: &Path) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::copy(&i.inputs.vrelay, &prep.bin)
        .map_err(|e| format!("copy {}: {e}", i.inputs.vrelay.display()))?;
    std::fs::set_permissions(&prep.bin, std::fs::Permissions::from_mode(0o755))
        .map_err(|e| format!("make {} executable: {e}", prep.bin.display()))?;
    if let Some(id) = &prep.identity {
        sign(&i.tools, id, &prep.bin, i.timing.sign_backoff)?;
    }
    layout::copy_tree(&i.inputs.node_modules, &prep.node_modules)?;
    layout::find_rg(&prep.node_modules, &prep.platform)
        .map_err(|e| format!("desktop-commander's search would not work: {e}"))?;
    probe_search(&i.node, &prep.node_modules)?;
    std::fs::write(&prep.plist, plist_text)
        .map_err(|e| format!("write {}: {e}", prep.plist.display()))?;
    let lint = run(Command::new(&i.tools.plutil).arg("-lint").arg(&prep.plist))?;
    if !lint.status.success() {
        return Err(format!(
            "plutil -lint rejects the plist: {}",
            String::from_utf8_lossy(&lint.stdout).trim()
        ));
    }
    // Harmless for a running agent, and launchd will not make it.
    make_log_dir(log_dir)
}

/// The installed `node` finds `rg` from desktop-commander's real entry
/// point and runs it ([`SEARCH_PROBE`]). Returns where it found it.
pub fn probe_search(node: &Path, node_modules: &Path) -> Result<PathBuf> {
    let entry = node_modules.join(layout::DC_PACKAGE).join(layout::DC_ENTRY);
    let entry =
        std::fs::canonicalize(&entry).map_err(|e| format!("no {}: {e}", entry.display()))?;
    let probe = output_within(
        Command::new(node)
            .args(["--input-type=module", "-e", SEARCH_PROBE])
            .arg(&entry),
        PROBE_TIMEOUT,
        1 << 16,
    )
    .map_err(|e| format!("cannot run {}: {e}", node.display()))?
    .ok_or_else(|| {
        format!(
            "the search check did not finish in {} s",
            PROBE_TIMEOUT.as_secs()
        )
    })?;
    if !probe.status.success() {
        return Err(format!(
            "desktop-commander's search would not work: node could not find or run \
             ripgrep from the installed package: {}",
            String::from_utf8_lossy(&probe.stderr).trim()
        ));
    }
    Ok(PathBuf::from(
        String::from_utf8_lossy(&probe.stdout).trim().to_string(),
    ))
}

/// After the old agent is stopped: move the staged copy into place, write
/// `bridge.json`, and load the agent.
fn finish(i: &Install, p: &Paths, prep: &Prepared) -> Result<()> {
    std::fs::rename(&prep.bin, &p.bin)
        .map_err(|e| format!("move {} into place: {e}", p.bin.display()))?;
    let old = p.share.join("node_modules.old");
    remove_path(&old)?;
    if std::fs::symlink_metadata(&p.node_modules).is_ok() {
        std::fs::rename(&p.node_modules, &old)
            .map_err(|e| format!("move the old {} aside: {e}", p.node_modules.display()))?;
    }
    std::fs::rename(&prep.node_modules, &p.node_modules)
        .map_err(|e| format!("move {} into place: {e}", p.node_modules.display()))?;
    remove_path(&old)?;
    let bridge = serde_json::json!({"node": utf8(&i.node)?, "entry": utf8(&p.entry)?});
    write_private(&p.bridge_json, format!("{bridge:#}\n").as_bytes())?;
    let plist_dir = p.plist.parent().expect("the plist has a folder");
    std::fs::create_dir_all(plist_dir)
        .map_err(|e| format!("create {}: {e}", plist_dir.display()))?;
    std::fs::rename(&prep.plist, &p.plist)
        .map_err(|e| format!("move {} into place: {e}", p.plist.display()))?;

    let domain = format!("gui/{}", i.uid);
    let service = format!("{domain}/{LABEL}");
    // Enable first: bootstrap refuses a service someone once disabled.
    let enable = run(Command::new(&i.tools.launchctl).args(["enable", &service]))?;
    if !enable.status.success() {
        return Err(format!(
            "launchctl enable {service} failed: {}",
            String::from_utf8_lossy(&enable.stderr).trim()
        ));
    }
    let boot = run(Command::new(&i.tools.launchctl)
        .args(["bootstrap", &domain])
        .arg(&p.plist))?;
    if !boot.status.success() {
        return Err(format!(
            "launchctl bootstrap {domain} {} failed: {}",
            p.plist.display(),
            String::from_utf8_lossy(&boot.stderr).trim()
        ));
    }
    if !loaded(&i.tools, &service) {
        return Err(format!(
            "{LABEL} did not stay loaded; see {}",
            p.log.display()
        ));
    }
    Ok(())
}

fn find_identity(tools: &Tools) -> Result<Identity> {
    let listing =
        run(Command::new(&tools.security).args(["find-identity", "-v", "-p", "codesigning"]))?;
    developer_id_identity(&String::from_utf8_lossy(&listing.stdout)).ok_or_else(|| {
        "no Developer ID Application identity to sign vrelay with \
         (`security find-identity -v -p codesigning` lists none). To get one: in Xcode, \
         Settings > Accounts > your team > Manage Certificates > + > Developer ID \
         Application (needs Apple Developer Program membership), which puts it in your \
         login keychain. Or install without signing: \
         bazel run //apps/suites/vitruvian-relay/connector/scripts:install -- --unsigned"
            .to_string()
    })
}

/// Signs as the Mac apps are signed (`codesign_with_timestamp_retry` in
/// apps/desktop/vitruvian-atrium/build.sh: `--strip-disallowed-xattrs`,
/// hardened runtime, secure timestamp, 3 tries with a growing wait), then
/// verifies.
fn sign(tools: &Tools, id: &Identity, bin: &Path, backoff: Duration) -> Result<()> {
    let mut last = String::new();
    for attempt in 1..=SIGN_ATTEMPTS {
        let signed = run(Command::new(&tools.codesign)
            .args(["--force", "--strip-disallowed-xattrs"])
            .args(["--options", "runtime", "--timestamp"])
            .args(["--identifier", IDENTIFIER, "--sign", &id.hash])
            .arg(bin))?;
        if signed.status.success() {
            let verify = run(Command::new(&tools.codesign)
                .args(["--verify", "--strict"])
                .arg(bin))?;
            if !verify.status.success() {
                return Err(format!(
                    "codesign --verify rejects {}: {}",
                    bin.display(),
                    String::from_utf8_lossy(&verify.stderr).trim()
                ));
            }
            return Ok(());
        }
        last = String::from_utf8_lossy(&signed.stderr).trim().to_string();
        if attempt < SIGN_ATTEMPTS {
            std::thread::sleep(backoff * attempt);
        }
    }
    Err(format!(
        "codesign with \"{}\" failed {SIGN_ATTEMPTS} times: {last}",
        id.name
    ))
}

fn loaded(tools: &Tools, service: &str) -> bool {
    run(Command::new(&tools.launchctl).args(["print", service])).is_ok_and(|o| o.status.success())
}

/// Stops and unloads the agent, if loaded, and waits up to `wait` for it
/// to go.
fn bootout(tools: &Tools, uid: u32, wait: Duration) -> Result<()> {
    let service = format!("gui/{uid}/{LABEL}");
    // Fails when it is not loaded, which is fine.
    run(Command::new(&tools.launchctl).args(["bootout", &service]))?;
    let deadline = Instant::now() + wait;
    while loaded(tools, &service) {
        if Instant::now() >= deadline {
            return Err(format!(
                "the running {LABEL} did not stop within {:.1} s",
                wait.as_secs_f32()
            ));
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    Ok(())
}

/// The log folder, mode 0700 (tightened if it already exists).
fn make_log_dir(dir: &Path) -> Result<()> {
    vitruvian_relay_connector::state::ensure_dir(dir)
}

/// Removes a file, link or folder; nothing there is fine.
fn remove_path(p: &Path) -> Result<()> {
    let r = match std::fs::symlink_metadata(p) {
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(e) => Err(e),
        Ok(m) if m.is_dir() => std::fs::remove_dir_all(p),
        Ok(_) => std::fs::remove_file(p),
    };
    r.map_err(|e| format!("remove {}: {e}", p.display()))
}

fn say(out: &mut dyn Write, line: &str) {
    let _ = writeln!(out, "{line}");
}

/// For `launchctl`, `codesign`, `security` and `plutil`, which return at
/// once. `node` goes through [`output_within`], which has a time limit.
fn run(cmd: &mut Command) -> Result<Output> {
    cmd.stdin(Stdio::null())
        .output()
        .map_err(|e| format!("cannot run {}: {e}", cmd.get_program().to_string_lossy()))
}

/// Stops and unloads the agent and removes `~/.local/share/vrelay` and the
/// plist. Keeps the sign-in, the device key, the rules and the logs.
pub fn uninstall(home: &Path, uid: u32, tools: &Tools, out: &mut dyn Write) -> Result<()> {
    let p = Paths::for_home(home);
    bootout(tools, uid, Timing::default().bootout_wait)?;
    remove_path(&p.plist)?;
    remove_path(&p.share)?;
    let state = Config::from_lookup(|k| (k == "HOME").then(|| home.to_string_lossy().into()));
    say(
        out,
        &format!("Removed the LaunchAgent {LABEL} and {}.", p.share.display()),
    );
    say(
        out,
        &format!(
            "Kept the sign-in, device key and rules in {} and the logs in {}.",
            state.dir.display(),
            p.log_dir.display()
        ),
    );
    Ok(())
}

#[cfg(test)]
mod tests;
