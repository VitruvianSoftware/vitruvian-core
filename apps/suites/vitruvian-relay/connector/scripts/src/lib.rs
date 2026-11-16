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

use std::io::{Read, Write};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::time::{Duration, Instant};

use vitruvian_relay_connector::bridge::{check_node, find_on_path};
use vitruvian_relay_connector::config::Config;
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

/// Fills the template: `__BIN__`, `__LOG__` and `__PATH__` anywhere, and a
/// line that is only `__ARGS__` becomes one `<string>` per argument.
pub fn render_plist(
    template: &str,
    bin: &Path,
    args: &[&str],
    log: &Path,
    path_env: &str,
) -> String {
    let bin = xml_escape(&bin.to_string_lossy());
    let log = xml_escape(&log.to_string_lossy());
    let path_env = xml_escape(path_env);
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
        out.push_str(
            &line
                .replace("__BIN__", &bin)
                .replace("__LOG__", &log)
                .replace("__PATH__", &path_env),
        );
        out.push('\n');
    }
    out
}

/// The agent's `PATH`: `node`'s folder, then `/usr/bin:/bin`.
pub fn plist_path_env(node: &Path) -> String {
    const BASE: &str = "/usr/bin:/bin";
    match node.parent() {
        Some(d) if d != Path::new("/usr/bin") && d != Path::new("/bin") => {
            format!("{}:{BASE}", d.display())
        }
        _ => BASE.to_string(),
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

/// The `node` to write into `bridge.json` and the plist: `explicit`
/// (`--node`) if given, else the first on `PATH`. It must be an absolute
/// path to Node 22.12 or newer. Not resolved through symlinks: Homebrew's
/// `/opt/homebrew/bin/node` keeps working across `brew upgrade`.
pub fn resolve_node(explicit: Option<&Path>, path: Option<&str>) -> Result<PathBuf> {
    let node = match explicit {
        Some(p) => p.to_path_buf(),
        None => find_on_path("node", path).ok_or(
            "no `node` on PATH. desktop-commander needs Node.js 22.12 or newer: install it \
             (https://nodejs.org or `brew install node`), or pass --node /absolute/path/to/node",
        )?,
    };
    if !node.is_absolute() {
        return Err(format!(
            "{} is not an absolute path: launchd starts vrelay from /, so pass \
             --node /absolute/path/to/node",
            node.display()
        ));
    }
    check_node(&node)?;
    Ok(node)
}

pub struct Install {
    pub home: PathBuf,
    pub uid: u32,
    pub inputs: Inputs,
    pub tools: Tools,
    pub node: PathBuf,
    /// `--unsigned`: install without signing, with a warning.
    pub unsigned: bool,
}

/// How long the search check (`node` finding and running `rg`) may take.
const PROBE_TIMEOUT: Duration = Duration::from_secs(30);
/// How long a booted-out agent may take to go.
const BOOTOUT_WAIT: Duration = Duration::from_secs(10);

/// Run by the installed `node`: finds `rg` from desktop-commander's real
/// entry point exactly as desktop-commander 0.3.1 does
/// (`import('@vscode/ripgrep')`'s `rgPath`, `dist/utils/ripgrep-resolver.js`)
/// and runs it. Prints the path.
const SEARCH_PROBE: &str = r#"
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
const req = createRequire(process.argv[1]);
const { rgPath } = await import(pathToFileURL(req.resolve('@vscode/ripgrep')).href);
const r = spawnSync(rgPath, ['--version'], { encoding: 'utf8' });
if (r.status !== 0) {
  console.error(`${rgPath} --version failed: ${r.error ?? r.stderr}`);
  process.exit(1);
}
console.log(rgPath);
"#;

fn uninstall_hint() -> &'static str {
    "bazel run //apps/suites/vitruvian-relay/connector/scripts:uninstall"
}

pub fn install(i: &Install, out: &mut dyn Write) -> Result<()> {
    let platform = layout::rg_platform()
        .ok_or("@vscode/ripgrep has no rg for this platform, so search would not work")?;
    if !i.node.is_absolute() {
        return Err(format!("{} is not an absolute path", i.node.display()));
    }
    check_node(&i.node)?;
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
    let p = Paths::for_home(&i.home);
    std::fs::create_dir_all(&p.share).map_err(|e| format!("create {}: {e}", p.share.display()))?;

    // Stage the new copy beside the old one; nothing running is touched
    // until it is signed and its search works.
    let staged_bin = p.share.join("vrelay.new");
    let staged_nm = p.share.join("node_modules.new");
    remove_path(&staged_bin)?;
    remove_path(&staged_nm)?;
    if let Err(e) = stage(i, identity.as_ref(), &platform, &staged_bin, &staged_nm) {
        let _ = remove_path(&staged_bin);
        let _ = remove_path(&staged_nm);
        return Err(e);
    }

    bootout(&i.tools, i.uid)?;
    std::fs::rename(&staged_bin, &p.bin)
        .map_err(|e| format!("move {} into place: {e}", p.bin.display()))?;
    let old = p.share.join("node_modules.old");
    remove_path(&old)?;
    if std::fs::symlink_metadata(&p.node_modules).is_ok() {
        std::fs::rename(&p.node_modules, &old)
            .map_err(|e| format!("move the old {} aside: {e}", p.node_modules.display()))?;
    }
    std::fs::rename(&staged_nm, &p.node_modules)
        .map_err(|e| format!("move {} into place: {e}", p.node_modules.display()))?;
    remove_path(&old)?;
    let rg = layout::find_rg(&p.node_modules, &platform)?;
    let node = i
        .node
        .to_str()
        .ok_or_else(|| format!("{} is not UTF-8", i.node.display()))?;
    let entry = p
        .entry
        .to_str()
        .ok_or_else(|| format!("{} is not UTF-8", p.entry.display()))?;
    let bridge = serde_json::json!({"node": node, "entry": entry});
    write_private(&p.bridge_json, format!("{bridge:#}\n").as_bytes())?;

    make_log_dir(&p.log_dir)?;
    let template = std::fs::read_to_string(&i.inputs.plist_template)
        .map_err(|e| format!("read {}: {e}", i.inputs.plist_template.display()))?;
    let plist = render_plist(
        &template,
        &p.bin,
        &["run"],
        &p.log,
        &plist_path_env(&i.node),
    );
    let plist_dir = p.plist.parent().expect("the plist has a folder");
    std::fs::create_dir_all(plist_dir)
        .map_err(|e| format!("create {}: {e}", plist_dir.display()))?;
    std::fs::write(&p.plist, plist).map_err(|e| format!("write {}: {e}", p.plist.display()))?;
    let lint = run(Command::new(&i.tools.plutil).arg("-lint").arg(&p.plist))?;
    if !lint.status.success() {
        return Err(format!(
            "plutil -lint rejects {}: {}",
            p.plist.display(),
            String::from_utf8_lossy(&lint.stdout).trim()
        ));
    }
    let domain = format!("gui/{}", i.uid);
    let service = format!("{domain}/{LABEL}");
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
    let enable = run(Command::new(&i.tools.launchctl).args(["enable", &service]))?;
    if !enable.status.success() {
        return Err(format!(
            "launchctl enable {service} failed: {}",
            String::from_utf8_lossy(&enable.stderr).trim()
        ));
    }
    if !loaded(&i.tools, &service) {
        return Err(format!(
            "{LABEL} did not stay loaded; see {}",
            p.log.display()
        ));
    }

    say(
        out,
        &format!("Installed vrelay as the LaunchAgent {LABEL}."),
    );
    let signed = match &identity {
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
            "It waits for a sign-in until you run `{} login`. To remove it: {}",
            p.bin.display(),
            uninstall_hint()
        ),
    );
    let state = Config::from_lookup(|k| (k == "HOME").then(|| i.home.to_string_lossy().into()));
    for w in rules::file_warnings(&state.dir) {
        say(out, &format!("warning: {w}"));
    }
    Ok(())
}

/// Copies, signs and checks the new binary and package at the staged
/// paths: `rg` is where Node will look, and the installed `node` finds and
/// runs it from desktop-commander's entry point.
fn stage(
    i: &Install,
    identity: Option<&Identity>,
    platform: &str,
    bin: &Path,
    node_modules: &Path,
) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::copy(&i.inputs.vrelay, bin)
        .map_err(|e| format!("copy {}: {e}", i.inputs.vrelay.display()))?;
    std::fs::set_permissions(bin, std::fs::Permissions::from_mode(0o755))
        .map_err(|e| format!("make {} executable: {e}", bin.display()))?;
    if let Some(id) = identity {
        sign(&i.tools, id, bin)?;
    }
    layout::copy_tree(&i.inputs.node_modules, node_modules)?;
    layout::find_rg(node_modules, platform)
        .map_err(|e| format!("desktop-commander's search would not work: {e}"))?;
    let entry = node_modules.join(layout::DC_PACKAGE).join(layout::DC_ENTRY);
    let entry =
        std::fs::canonicalize(&entry).map_err(|e| format!("no {}: {e}", entry.display()))?;
    let probe = run_with_timeout(
        Command::new(&i.node)
            .args(["--input-type=module", "-e", SEARCH_PROBE])
            .arg(&entry),
        PROBE_TIMEOUT,
    )?;
    if !probe.status.success() {
        return Err(format!(
            "desktop-commander's search would not work: node could not find or run \
             ripgrep from the installed package: {}",
            String::from_utf8_lossy(&probe.stderr).trim()
        ));
    }
    Ok(())
}

fn find_identity(tools: &Tools) -> Result<Identity> {
    let listing =
        run(Command::new(&tools.security).args(["find-identity", "-v", "-p", "codesigning"]))?;
    developer_id_identity(&String::from_utf8_lossy(&listing.stdout)).ok_or_else(|| {
        ("no Developer ID Application identity to sign vrelay with \
             (`security find-identity -v -p codesigning` lists none). To get one: in Xcode, \
             Settings > Accounts > your team > Manage Certificates > + > Developer ID \
             Application (needs Apple Developer Program membership), which puts it in your \
             login keychain. Or install without signing: \
             bazel run //apps/suites/vitruvian-relay/connector/scripts:install -- --unsigned")
            .to_string()
    })
}

/// Signs as the Mac apps are signed (hardened runtime, secure timestamp),
/// with one retry for the timestamp server, then verifies.
fn sign(tools: &Tools, id: &Identity, bin: &Path) -> Result<()> {
    let attempt = || {
        run(Command::new(&tools.codesign)
            .args(["--force", "--options", "runtime", "--timestamp"])
            .args(["--identifier", IDENTIFIER, "--sign", &id.hash])
            .arg(bin))
    };
    let mut signed = attempt()?;
    if !signed.status.success() {
        std::thread::sleep(Duration::from_secs(2));
        signed = attempt()?;
    }
    if !signed.status.success() {
        return Err(format!(
            "codesign with \"{}\" failed: {}",
            id.name,
            String::from_utf8_lossy(&signed.stderr).trim()
        ));
    }
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
    Ok(())
}

fn loaded(tools: &Tools, service: &str) -> bool {
    run(Command::new(&tools.launchctl).args(["print", service])).is_ok_and(|o| o.status.success())
}

/// Stops and unloads the agent, if loaded, and waits for it to go.
fn bootout(tools: &Tools, uid: u32) -> Result<()> {
    let service = format!("gui/{uid}/{LABEL}");
    // Fails when it is not loaded, which is fine.
    run(Command::new(&tools.launchctl).args(["bootout", &service]))?;
    let deadline = Instant::now() + BOOTOUT_WAIT;
    while loaded(tools, &service) {
        if Instant::now() >= deadline {
            return Err(format!(
                "the running {LABEL} did not stop within {} s",
                BOOTOUT_WAIT.as_secs()
            ));
        }
        std::thread::sleep(Duration::from_millis(200));
    }
    Ok(())
}

/// The log folder, mode 0700 (tightened if it already exists).
fn make_log_dir(dir: &Path) -> Result<()> {
    use std::os::unix::fs::{DirBuilderExt, PermissionsExt};
    if let Some(parent) = dir.parent() {
        std::fs::create_dir_all(parent).map_err(|e| format!("create {}: {e}", parent.display()))?;
    }
    match std::fs::DirBuilder::new().mode(0o700).create(dir) {
        Ok(()) => {}
        Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {}
        Err(e) => return Err(format!("create {}: {e}", dir.display())),
    }
    let meta =
        std::fs::symlink_metadata(dir).map_err(|e| format!("read {}: {e}", dir.display()))?;
    if !meta.is_dir() {
        return Err(format!("{} is not a folder", dir.display()));
    }
    std::fs::set_permissions(dir, std::fs::Permissions::from_mode(0o700))
        .map_err(|e| format!("make {} private: {e}", dir.display()))
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

fn run(cmd: &mut Command) -> Result<Output> {
    cmd.stdin(Stdio::null())
        .output()
        .map_err(|e| format!("cannot run {}: {e}", cmd.get_program().to_string_lossy()))
}

/// [`run`], in its own process group, killed (group and all) after
/// `timeout`.
fn run_with_timeout(cmd: &mut Command, timeout: Duration) -> Result<Output> {
    let name = cmd.get_program().to_string_lossy().to_string();
    let mut child = cmd
        .process_group(0)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("cannot run {name}: {e}"))?;
    let drain = |r: Option<Box<dyn Read + Send>>| {
        std::thread::spawn(move || {
            let mut buf = Vec::new();
            if let Some(mut r) = r {
                let _ = r.by_ref().take(1 << 20).read_to_end(&mut buf);
            }
            buf
        })
    };
    let out = drain(
        child
            .stdout
            .take()
            .map(|r| Box::new(r) as Box<dyn Read + Send>),
    );
    let err = drain(
        child
            .stderr
            .take()
            .map(|r| Box::new(r) as Box<dyn Read + Send>),
    );
    let deadline = Instant::now() + timeout;
    let status = loop {
        match child.try_wait() {
            Ok(Some(st)) => break st,
            Ok(None) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(20)),
            _ => {
                // SAFETY: kill on our own child's process group.
                unsafe { libc::kill(-(child.id() as i32), libc::SIGKILL) };
                let _ = child.wait();
                return Err(format!("{name} did not finish in {} s", timeout.as_secs()));
            }
        }
    };
    Ok(Output {
        status,
        stdout: out.join().unwrap_or_default(),
        stderr: err.join().unwrap_or_default(),
    })
}

/// Stops and unloads the agent and removes `~/.local/share/vrelay` and the
/// plist. Keeps the sign-in, the device key, the rules and the logs.
pub fn uninstall(home: &Path, uid: u32, tools: &Tools, out: &mut dyn Write) -> Result<()> {
    let p = Paths::for_home(home);
    bootout(tools, uid)?;
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
