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

//! The local rules: which `desktop-commander` tools the relay may see, which
//! run without asking, and which ask first. The file lives on this Mac, is
//! read at start and on `SIGHUP`, and nothing received from the relay can
//! change it. The default is to ask: a tool runs silently only if it is named
//! in `no_prompt`.

use std::path::{Path, PathBuf};

use serde::Deserialize;
use serde_json::Value;
use vitruvian_relay_protocol::ToolDef;

use crate::config::Config;
use crate::state::write_private;
use crate::Result;

/// The arguments that name a file or folder, in desktop-commander 0.3.1's
/// tools (`paths` is a list of them).
const PATH_ARGS: &[&str] = &["path", "file_path", "source", "destination", "outputPath"];
/// The tools that read what is under their `path`, however deep: one rooted
/// at or above a guarded folder would reach it.
const SEARCH_TOOLS: &[&str] = &["start_search"];

/// Folders a remote call may never touch: vrelay's own sign-in, device key,
/// logs and install, and desktop-commander's own folder (its log holds
/// every call's arguments). Ruling R17. A path is resolved the way the call
/// would see it (`~`, relative to the working folder, `..`, symlinks)
/// before it is checked; a search rooted at or above one of these asks
/// first. The folders the file tools *may* use are `allowed_folders`
/// (Rules::decide), resolved by the same code.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Guard {
    /// Each folder as written and as resolved, lowercased (APFS ignores
    /// case by default; erring that way only refuses more).
    roots: Vec<PathBuf>,
    home: PathBuf,
    cwd: PathBuf,
    /// Whether upper and lower case are the same folder: paths are compared
    /// lowercased when so, exactly when not. True for the guard (it only
    /// refuses more), as measured on the volume for the allowed folders.
    fold: bool,
}

impl Guard {
    /// The folders for this configuration, relative paths from this
    /// process's working folder (desktop-commander inherits it).
    pub fn new(cfg: &Config) -> Guard {
        let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("/"));
        Guard::for_config(cfg, &cwd)
    }

    pub fn for_config(cfg: &Config, cwd: &Path) -> Guard {
        let h = &cfg.home;
        Guard::with_roots(
            h,
            cwd,
            &[
                cfg.dir.clone(),
                cfg.log_dir.clone(),
                h.join("Library/Application Support/vrelay"),
                h.join("Library/Logs/vrelay"),
                h.join(".local/share/vrelay"),
                h.join(crate::bridge::DC_CONFIG_DIR),
            ],
        )
    }

    /// A guard of the same home and working folders whose roots are the
    /// folders a person allowed (`~` and relative paths as in a call).
    ///
    /// Compared exactly on a case-sensitive volume: lowercasing there would
    /// let `~/work` through for an allowed `~/Work`, a different folder.
    fn limited_to(&self, folders: &[String]) -> Guard {
        let roots: Vec<PathBuf> = folders.iter().map(PathBuf::from).collect();
        let probe = Guard::build(&self.home, &self.cwd, &roots, false);
        // Folding is right only if every allowed folder is on a volume that
        // ignores case (an unknown mix compares exactly: refuses more).
        let fold = !roots.is_empty()
            && roots
                .iter()
                .all(|r| volume_ignores_case(&probe.real_part(&r.to_string_lossy())));
        Guard::build(&self.home, &self.cwd, &roots, fold)
    }

    /// The part of `raw` that exists, with symlinks resolved.
    fn real_part(&self, raw: &str) -> PathBuf {
        let mut head = normalize(&self.absolute(raw));
        loop {
            if let Ok(real) = std::fs::canonicalize(&head) {
                return real;
            }
            if !head.pop() {
                return PathBuf::from("/");
            }
        }
    }

    fn case(&self, p: &Path) -> PathBuf {
        if self.fold {
            lower(p)
        } else {
            p.to_path_buf()
        }
    }

    pub fn with_roots(home: &Path, cwd: &Path, roots: &[PathBuf]) -> Guard {
        Guard::build(home, cwd, roots, true)
    }

    fn build(home: &Path, cwd: &Path, roots: &[PathBuf], fold: bool) -> Guard {
        let mut g = Guard {
            roots: Vec::new(),
            home: home.to_path_buf(),
            cwd: cwd.to_path_buf(),
            fold,
        };
        let mut all = Vec::new();
        for r in roots {
            all.push(g.case(&normalize(&g.absolute(&r.to_string_lossy()))));
            all.push(g.resolve(&r.to_string_lossy()));
        }
        all.sort();
        all.dedup();
        g.roots = all;
        g
    }

    /// `raw` as an absolute path: `~` is home, a relative path is from the
    /// working folder.
    fn absolute(&self, raw: &str) -> PathBuf {
        let raw = raw.trim();
        if raw == "~" {
            return self.home.clone();
        }
        if let Some(rest) = raw.strip_prefix("~/") {
            return self.home.join(rest);
        }
        let p = Path::new(raw);
        if p.is_absolute() {
            p.to_path_buf()
        } else {
            self.cwd.join(p)
        }
    }

    /// Where `raw` really points: the longest part that exists with its
    /// symlinks and `..` resolved by the system, the rest cleaned of `.`
    /// and `..`. Lowercased.
    fn resolve(&self, raw: &str) -> PathBuf {
        let abs = normalize(&self.absolute(raw));
        let mut head = abs.clone();
        let mut tail = Vec::new();
        loop {
            if let Ok(real) = std::fs::canonicalize(&head) {
                let mut out = real;
                for part in tail.iter().rev() {
                    out.push(part);
                }
                return self.case(&normalize(&out));
            }
            match (head.file_name().map(|n| n.to_os_string()), head.parent()) {
                (Some(name), Some(parent)) => {
                    tail.push(name);
                    head = parent.to_path_buf();
                }
                _ => return self.case(&abs),
            }
        }
    }

    fn under(&self, raw: &str) -> bool {
        let p = self.resolve(raw);
        self.roots.iter().any(|r| p.starts_with(r))
    }

    fn at_or_above(&self, raw: &str) -> bool {
        let p = self.resolve(raw);
        self.roots.iter().any(|r| r.starts_with(&p))
    }
}

/// `.` and `..` taken out without touching the disk (a `..` above the root
/// stays at the root).
fn normalize(p: &Path) -> PathBuf {
    use std::path::Component;
    let mut out = PathBuf::new();
    for c in p.components() {
        match c {
            Component::CurDir => {}
            Component::ParentDir => {
                out.pop();
            }
            other => out.push(other.as_os_str()),
        }
    }
    out
}

fn lower(p: &Path) -> PathBuf {
    PathBuf::from(p.to_string_lossy().to_lowercase())
}

/// Whether the volume holding `path` (an existing path) treats names that
/// differ only in case as the same: looks up a name with its case swapped
/// and asks if it is the very same file. A name with no letters says
/// nothing, so the next one up is tried.
fn volume_ignores_case(path: &Path) -> bool {
    use std::os::unix::fs::MetadataExt;
    for anc in path.ancestors() {
        let Some(name) = anc.file_name().map(|n| n.to_string_lossy().into_owned()) else {
            continue;
        };
        let swapped: String = name
            .chars()
            .map(|c| {
                if c.is_lowercase() {
                    c.to_uppercase().next().unwrap_or(c)
                } else {
                    c.to_lowercase().next().unwrap_or(c)
                }
            })
            .collect();
        if swapped == name {
            continue;
        }
        let Ok(a) = std::fs::metadata(anc) else {
            continue;
        };
        return match std::fs::metadata(anc.with_file_name(&swapped)) {
            Ok(b) => a.dev() == b.dev() && a.ino() == b.ino(),
            Err(_) => false,
        };
    }
    false
}

/// The path-like string arguments of a call.
fn path_args(args: &Value) -> Vec<&str> {
    let mut out: Vec<&str> = PATH_ARGS
        .iter()
        .filter_map(|k| args.get(*k).and_then(Value::as_str))
        .collect();
    if let Some(list) = args.get("paths").and_then(Value::as_array) {
        out.extend(list.iter().filter_map(Value::as_str));
    }
    out
}

pub const DEFAULT_RULES: &str = r#"# What the relay may do on this Mac. vrelay reads this file when it starts.
# After an edit, run `vrelay reload`: until then the rules it loaded stay in
# use (`vrelay status` says when this file has changed since). `vrelay pause`
# and `vrelay resume` set `paused` and reload in one step.
paused = false
hidden = ["set_config_value", "get_config",    # never exposed remotely
          "get_recent_tool_calls",               # earlier calls' arguments
          "give_feedback_to_desktop_commander",  # opens a browser form
          "track_ui_event"]                      # desktop-commander's own UI
config_allow = []    # settings tools to expose anyway; any other tool whose
                     # name contains "config" is hidden
# While paused, no tools are visible and every call is refused.
# Run without asking: reads only. Every other tool, including any tool a
# future desktop-commander adds, asks first.
no_prompt = ["read_file", "read_multiple_files", "list_directory",
             "get_file_info", "start_search", "get_more_search_results",
             "stop_search", "list_searches"]
# Keep this Mac from sleeping while vrelay runs, so a call from Claude does not
# find it asleep. The screen may still sleep. Set it to false to stop.
keep_awake = true
# The file tools (read, write, move, search) may only touch these folders and
# what is inside them; `~` is your home folder. Terminal commands are not
# limited by this list.
allowed_folders = ["~"]
"#;

/// Arguments that turn a tool listed in `no_prompt` into something that must
/// ask first, whatever the rules file says: present with any value but
/// `false`. `read_file` with `isUrl` fetches the URL from this Mac, which can
/// reach localhost and the homelab. (desktop-commander 0.3.1's other
/// `no_prompt` tools have no such argument; see the Task 7 report.)
pub const ASK_FIRST_ARGS: &[(&str, &str)] = &[("read_file", "isUrl")];

/// Earlier versions of [`DEFAULT_RULES`]. A rules.toml that is exactly one
/// of these was never edited, so `load` replaces it with the current
/// defaults; any edit, however small, makes the file the person's own.
const PREVIOUS_DEFAULTS: &[&str] = &[
    // Before `keep_awake` and `allowed_folders` (Relay P2).
    r#"# What the relay may do on this Mac. vrelay reads this file when it starts.
# After an edit, run `vrelay reload`: until then the rules it loaded stay in
# use (`vrelay status` says when this file has changed since). `vrelay pause`
# and `vrelay resume` set `paused` and reload in one step.
paused = false
hidden = ["set_config_value", "get_config",    # never exposed remotely
          "get_recent_tool_calls",               # earlier calls' arguments
          "give_feedback_to_desktop_commander",  # opens a browser form
          "track_ui_event"]                      # desktop-commander's own UI
config_allow = []    # settings tools to expose anyway; any other tool whose
                     # name contains "config" is hidden
# While paused, no tools are visible and every call is refused.
# Run without asking: reads only. Every other tool, including any tool a
# future desktop-commander adds, asks first.
no_prompt = ["read_file", "read_multiple_files", "list_directory",
             "get_file_info", "start_search", "get_more_search_results",
             "stop_search", "list_searches"]
"#,
    // Before the header that says how to reload (final fix wave).
    r#"paused = false
hidden = ["set_config_value", "get_config",    # never exposed remotely
          "get_recent_tool_calls",               # earlier calls' arguments
          "give_feedback_to_desktop_commander",  # opens a browser form
          "track_ui_event"]                      # desktop-commander's own UI
config_allow = []    # settings tools to expose anyway; any other tool whose
                     # name contains "config" is hidden
# While paused, no tools are visible and every call is refused.
# Run without asking: reads only. Every other tool, including any tool a
# future desktop-commander adds, asks first.
no_prompt = ["read_file", "read_multiple_files", "list_directory",
             "get_file_info", "start_search", "get_more_search_results",
             "stop_search", "list_searches"]
"#,
    // Before R13 hid the history, feedback and UI tools (Task 6, Task 7's
    // first commit).
    r#"paused = false
hidden = ["set_config_value", "get_config"]   # never exposed remotely
config_allow = []    # settings tools to expose anyway; any other tool whose
                     # name contains "config" is hidden
# While paused, no tools are visible and every call is refused.
# Run without asking: reads only. Every other tool, including any tool a
# future desktop-commander adds, asks first.
no_prompt = ["read_file", "read_multiple_files", "list_directory",
             "get_file_info", "start_search", "get_more_search_results",
             "stop_search", "list_searches"]
"#,
];

/// The refusal for a path outside `allowed_folders`.
pub const OUTSIDE_ALLOWED: &str =
    "outside your allowed folders; change them in Vitruvian Relay's settings";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Decision {
    Run,
    AskFirst,
    Refuse(&'static str),
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Rules {
    #[serde(default)]
    pub paused: bool,
    pub hidden: Vec<String>,
    #[serde(default)]
    pub config_allow: Vec<String>,
    pub no_prompt: Vec<String>,
    /// Hold the Mac awake while `vrelay run` is up (awake.rs).
    #[serde(default = "default_keep_awake")]
    pub keep_awake: bool,
    /// The folders the file tools may touch (a call's path must resolve to
    /// one of them or below); `~` is the home folder.
    #[serde(default = "default_allowed_folders")]
    pub allowed_folders: Vec<String>,
    /// SHA-256 of the file's text as [`load`] read it (empty if these
    /// rules came from elsewhere), so `vrelay status` can tell when the
    /// file has changed since.
    #[serde(skip)]
    pub source_sha256: String,
    /// The folders no call may touch. Not in the file: `vrelay run` sets
    /// it from its configuration, and a reload keeps it.
    #[serde(skip)]
    pub guard: Guard,
    /// `allowed_folders` resolved the way a call's paths are, once
    /// [`Rules::set_guard`] has the home and working folders. `None` until
    /// then: no limit is applied (the tests' rules, which have no home).
    #[serde(skip)]
    limit: Option<Guard>,
}

fn default_keep_awake() -> bool {
    true
}

fn default_allowed_folders() -> Vec<String> {
    vec!["~".to_string()]
}

/// The file's text with its `paused = …` line (if any) set to `paused`.
fn with_paused(text: &str, paused: bool) -> Option<String> {
    let mut found = false;
    let out: Vec<String> = text
        .split_inclusive('\n')
        .map(|line| {
            let body = line.trim_end_matches(['\n', '\r']);
            let key = body.split('=').next().unwrap_or("").trim();
            if !found && key == "paused" && body.contains('=') {
                found = true;
                let end = &line[body.len()..];
                format!("paused = {paused}{end}")
            } else {
                line.to_string()
            }
        })
        .collect();
    found.then(|| out.concat())
}

/// A file that is one of [`PREVIOUS_DEFAULTS`], or one with only its
/// `paused` line changed (as `vrelay pause` leaves it): the current
/// defaults, with its `paused` kept. `None` for a file the person edited.
fn upgraded(text: &str) -> Option<String> {
    if PREVIOUS_DEFAULTS.contains(&text) {
        return Some(DEFAULT_RULES.to_string());
    }
    // Paused, but otherwise an older default.
    let unpaused = with_paused(text, false)?;
    PREVIOUS_DEFAULTS
        .contains(&unpaused.as_str())
        .then(|| with_paused(DEFAULT_RULES, true))
        .flatten()
}

/// Sets `paused` in `rules.toml` (writing the defaults first if there is no
/// file), changing that one line and nothing else, so an untouched default
/// file still reads as untouched. The file must load afterwards.
pub fn set_paused(dir: &Path, paused: bool) -> Result<()> {
    let path = rules_path(dir);
    if !path.exists() {
        write_private(&path, DEFAULT_RULES.as_bytes())?;
    }
    let text =
        std::fs::read_to_string(&path).map_err(|e| format!("read {}: {e}", path.display()))?;
    let new = match with_paused(&text, paused) {
        Some(t) => t,
        // No `paused` line: add one at the top.
        None => format!("paused = {paused}\n{text}"),
    };
    toml::from_str::<Rules>(&new).map_err(|e| format!("{}: {e}", path.display()))?;
    if new != text {
        write_private(&path, new.as_bytes())?;
    }
    Ok(())
}

/// The rules file as it is now, without writing anything (`load` may write
/// the defaults); `None` if there is none or it does not load.
pub fn load_quietly(dir: &Path) -> Option<Rules> {
    let text = std::fs::read_to_string(rules_path(dir)).ok()?;
    toml::from_str(&text).ok()
}

/// SHA-256 of `rules.toml` as it is now, if it can be read.
pub fn file_sha256(dir: &Path) -> Option<String> {
    std::fs::read_to_string(rules_path(dir))
        .ok()
        .map(|t| crate::keys::sha256_hex(&t))
}

pub fn rules_path(dir: &Path) -> PathBuf {
    dir.join("rules.toml")
}

/// Reads `rules.toml`, writing the defaults first if there is none (or if
/// it is an untouched copy of older defaults).
///
/// A file that does not parse, or lacks `hidden` or `no_prompt`, is an error,
/// never a silent fall back to defaults: the caller decides (refuse to start;
/// on a reload, keep the rules it already has).
pub fn load(dir: &Path) -> Result<Rules> {
    let path = rules_path(dir);
    if !path.exists() {
        write_private(&path, DEFAULT_RULES.as_bytes())?;
    }
    let mut text =
        std::fs::read_to_string(&path).map_err(|e| format!("read {}: {e}", path.display()))?;
    if let Some(new) = upgraded(&text) {
        write_private(&path, new.as_bytes())?;
        text = new;
    }
    let mut rules: Rules = toml::from_str(&text).map_err(|e| format!("{}: {e}", path.display()))?;
    rules.source_sha256 = crate::keys::sha256_hex(&text);
    Ok(rules)
}

/// The result of re-reading the rules file (on `SIGHUP`).
pub struct Reloaded {
    pub rules: Rules,
    pub visible_changed: bool,
}

/// Re-reads the file. `visible_changed` says whether the tools the relay may
/// see differ from `current`'s, so the caller knows to send `tools_changed`.
/// On an error the caller keeps `current`.
pub fn reload(dir: &Path, current: &Rules, tools: &[ToolDef]) -> Result<Reloaded> {
    let mut rules = load(dir)?;
    if current.limit.is_some() {
        rules.set_guard(current.guard.clone());
    } else {
        rules.guard = current.guard.clone();
    }
    let visible_changed = rules.visible(tools) != current.visible(tools);
    Ok(Reloaded {
        rules,
        visible_changed,
    })
}

impl Rules {
    /// Sets the folders no call may touch, and resolves `allowed_folders`
    /// with the same home and working folder.
    pub fn set_guard(&mut self, guard: Guard) {
        self.limit = Some(guard.limited_to(&self.allowed_folders));
        self.guard = guard;
    }

    /// Never shown and never callable: named in `hidden` (ignoring case and
    /// surrounding spaces), or any other tool whose name contains "config"
    /// unless `config_allow` names it exactly. The explicit list wins over
    /// `config_allow`. `no_prompt` and `config_allow` stay exact-match: a
    /// near-miss there is the safe direction (it asks, or stays hidden).
    pub fn is_hidden(&self, tool: &str) -> bool {
        let norm = tool.trim().to_lowercase();
        if self.hidden.iter().any(|h| h.trim().to_lowercase() == norm) {
            return true;
        }
        norm.contains("config") && !self.config_allow.iter().any(|a| a == tool)
    }

    /// The tools the relay may see. While paused, none.
    pub fn visible(&self, tools: &[ToolDef]) -> Vec<ToolDef> {
        if self.paused {
            return Vec::new();
        }
        tools
            .iter()
            .filter(|t| !self.is_hidden(&t.name))
            .cloned()
            .collect()
    }

    /// What to do with a call. `Run` only for a visible tool named in
    /// `no_prompt` whose arguments do not trip [`ASK_FIRST_ARGS`];
    /// everything else, including a tool nobody has heard of, asks first.
    /// Apart from that one check, decisions go by the tool's name.
    pub fn decide(&self, tool: &str, args: &Value) -> Decision {
        if self.paused {
            return Decision::Refuse("paused on this Mac");
        }
        if self.is_hidden(tool) {
            return Decision::Refuse("this tool is not available remotely");
        }
        let paths = path_args(args);
        if paths.iter().any(|p| self.guard.under(p)) {
            return Decision::Refuse(
                "that path is in a folder holding vrelay's own sign-in, keys or logs",
            );
        }
        // Only the folders the person chose. A search is a path argument
        // too: its root must be inside them. Terminal commands are not
        // path-checked: a command line can name a path in too many ways.
        if let Some(limit) = &self.limit {
            if paths.iter().any(|p| !limit.under(p)) {
                return Decision::Refuse(OUTSIDE_ALLOWED);
            }
        }
        if SEARCH_TOOLS.contains(&tool) && paths.iter().any(|p| self.guard.at_or_above(p)) {
            return Decision::AskFirst;
        }
        let risky_arg = ASK_FIRST_ARGS
            .iter()
            .any(|(t, a)| *t == tool && args.get(*a).is_some_and(|v| *v != Value::Bool(false)));
        if risky_arg {
            return Decision::AskFirst;
        }
        if self.no_prompt.iter().any(|t| t == tool) {
            Decision::Run
        } else {
            Decision::AskFirst
        }
    }
}

/// What is worth telling the person about their rules file, without
/// changing it: a file that does not load, or an edited file that no longer
/// hides a tool the current defaults hide (a newer default the person never
/// got, because [`load`] only upgrades an untouched file). No file, or an
/// untouched copy of older defaults (`load` upgrades it at the next start),
/// gives nothing. The installer and `vrelay status` print these.
pub fn file_warnings(dir: &Path) -> Vec<String> {
    let path = rules_path(dir);
    let text = match std::fs::read_to_string(&path) {
        Ok(t) => t,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Vec::new(),
        Err(e) => return vec![format!("cannot read {}: {e}", path.display())],
    };
    if upgraded(&text).is_some() {
        return Vec::new();
    }
    let rules: Rules = match toml::from_str(&text) {
        Ok(r) => r,
        Err(e) => {
            return vec![format!(
                "{} does not load, so vrelay will not start: {e}",
                path.display()
            )]
        }
    };
    let missing = missing_default_hidden(&rules);
    if missing.is_empty() {
        return Vec::new();
    }
    vec![format!(
        "{} does not hide {}, which the current defaults hide. It was edited, \
         so it is never changed for you: add them to `hidden` (or keep them \
         visible on purpose).",
        path.display(),
        missing.join(", ")
    )]
}

/// The tools [`DEFAULT_RULES`] hides that `rules` does not (by the same
/// test calls use, [`Rules::is_hidden`]).
pub fn missing_default_hidden(rules: &Rules) -> Vec<String> {
    let defaults: Rules = toml::from_str(DEFAULT_RULES).expect("the default rules parse");
    defaults
        .hidden
        .into_iter()
        .filter(|t| !rules.is_hidden(t))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::state::test_dir;
    use serde_json::json;

    fn tool(name: &str) -> ToolDef {
        ToolDef {
            name: name.into(),
            description: String::new(),
            input_schema: json!({"type": "object"}),
        }
    }

    fn defaults() -> Rules {
        toml::from_str(DEFAULT_RULES).unwrap()
    }

    #[test]
    fn first_run_writes_the_default_file_privately() {
        use std::os::unix::fs::PermissionsExt;
        let dir = test_dir("rules-first");
        let r = load(&dir).unwrap();
        assert_eq!(
            std::fs::read_to_string(rules_path(&dir)).unwrap(),
            DEFAULT_RULES
        );
        let mode = std::fs::metadata(rules_path(&dir))
            .unwrap()
            .permissions()
            .mode()
            & 0o777;
        assert_eq!(mode, 0o600);
        assert!(!r.paused);
        assert!(r.config_allow.is_empty());
        // A second load reads the same file back.
        assert_eq!(load(&dir).unwrap(), r);
    }

    #[test]
    fn reads_run_without_asking() {
        let r = defaults();
        for t in [
            "read_file",
            "read_multiple_files",
            "list_directory",
            "get_file_info",
            "start_search",
            "get_more_search_results",
            "stop_search",
            "list_searches",
        ] {
            assert_eq!(r.decide(t, &json!({})), Decision::Run, "{t}");
        }
        for t in [
            "start_process",
            "write_file",
            "edit_block",
            "move_file",
            "create_directory",
            "kill_process",
            "force_terminate",
            "interact_with_process",
            "write_pdf",
        ] {
            assert_eq!(r.decide(t, &json!({})), Decision::AskFirst, "{t}");
        }
    }

    #[test]
    fn unknown_tool_asks_first() {
        let r = defaults();
        assert_eq!(r.decide("brand_new_tool", &json!({})), Decision::AskFirst);
        assert_eq!(r.decide("", &json!({})), Decision::AskFirst);
        // Close to a read tool but not it: still asks.
        assert_eq!(r.decide("read_file2", &json!({})), Decision::AskFirst);
        assert_eq!(r.decide("Read_File", &json!({})), Decision::AskFirst);
    }

    #[test]
    fn hidden_tools_never_visible_or_callable() {
        let r = defaults();
        let tools = vec![
            tool("read_file"),
            tool("set_config_value"),
            tool("get_config"),
        ];
        let names: Vec<_> = r.visible(&tools).into_iter().map(|t| t.name).collect();
        assert_eq!(names, vec!["read_file"]);
        assert!(matches!(
            r.decide("set_config_value", &json!({})),
            Decision::Refuse(_)
        ));
        assert!(matches!(
            r.decide("get_config", &json!({})),
            Decision::Refuse(_)
        ));
        // Hidden wins even if the same tool is also listed as no_prompt.
        let mut r2 = r.clone();
        r2.no_prompt.push("get_config".into());
        assert!(matches!(
            r2.decide("get_config", &json!({})),
            Decision::Refuse(_)
        ));
    }

    #[test]
    fn paused_refuses_everything() {
        let mut r = defaults();
        r.paused = true;
        for t in ["read_file", "start_process", "brand_new_tool", "get_config"] {
            assert!(
                matches!(r.decide(t, &json!({})), Decision::Refuse(_)),
                "{t}"
            );
        }
    }

    #[test]
    fn config_tools_are_hidden() {
        let mut r = defaults();
        for t in [
            "update_config",
            "get_server_config",
            "set_config_value",
            "CONFIG_reset",
        ] {
            assert!(r.is_hidden(t), "{t}");
            assert!(
                matches!(r.decide(t, &json!({})), Decision::Refuse(_)),
                "{t}"
            );
            // Even listed as no_prompt, a config tool stays hidden.
            r.no_prompt.push(t.into());
            assert!(
                matches!(r.decide(t, &json!({})), Decision::Refuse(_)),
                "{t}"
            );
        }
        // config_allow opens one tool; it then asks first (not in no_prompt).
        r.config_allow.push("update_config".into());
        r.no_prompt.retain(|t| t != "update_config");
        assert!(!r.is_hidden("update_config"));
        assert_eq!(r.decide("update_config", &json!({})), Decision::AskFirst);
        assert!(r.is_hidden("get_server_config"));
        // config_allow does not override the explicit hidden list.
        r.config_allow.push("get_config".into());
        assert!(r.is_hidden("get_config"));
    }

    #[test]
    fn paused_shows_no_tools() {
        let mut r = defaults();
        let tools = vec![tool("read_file"), tool("start_process")];
        assert_eq!(r.visible(&tools).len(), 2);
        r.paused = true;
        assert!(r.visible(&tools).is_empty());
    }

    #[test]
    fn reload_reports_whether_the_visible_set_changed() {
        let dir = test_dir("rules-reload");
        let tools = vec![tool("read_file"), tool("start_process")];
        let cur = load(&dir).unwrap();
        let same = reload(&dir, &cur, &tools).unwrap();
        assert!(!same.visible_changed);
        // Pausing changes what is visible.
        let paused = DEFAULT_RULES.replace("paused = false", "paused = true");
        std::fs::write(rules_path(&dir), paused).unwrap();
        let r = reload(&dir, &cur, &tools).unwrap();
        assert!(r.visible_changed);
        assert!(r.rules.paused);
        // Changing only no_prompt changes decisions but not visibility.
        let edited =
            DEFAULT_RULES.replace("\"list_searches\"", "\"list_searches\", \"start_process\"");
        std::fs::write(rules_path(&dir), edited).unwrap();
        let r = reload(&dir, &cur, &tools).unwrap();
        assert!(!r.visible_changed);
        assert_eq!(r.rules.decide("start_process", &json!({})), Decision::Run);
        // A broken file is an error, and the caller keeps its current rules.
        std::fs::write(rules_path(&dir), "paused = [").unwrap();
        assert!(reload(&dir, &cur, &tools).is_err());
    }

    #[test]
    fn a_bad_or_incomplete_file_is_an_error_not_a_default() {
        let dir = test_dir("rules-bad");
        std::fs::create_dir_all(&dir).unwrap();
        for bad in [
            "paused = [",
            "paused = false\n",
            "bogus = 1\nhidden=[]\nno_prompt=[]\n",
        ] {
            std::fs::write(rules_path(&dir), bad).unwrap();
            assert!(load(&dir).is_err(), "{bad}");
        }
    }

    #[test]
    fn hidden_list_ignores_case_and_whitespace() {
        let mut r = defaults();
        r.hidden.push("start_process".into());
        for t in [
            "start_process",
            "Start_Process",
            " start_process ",
            "START_PROCESS\t",
        ] {
            assert!(r.is_hidden(t), "{t:?}");
            assert!(
                matches!(r.decide(t, &json!({})), Decision::Refuse(_)),
                "{t:?}"
            );
        }
        assert!(r.visible(&[tool("Start_Process")]).is_empty());
        // A hidden entry written with odd case or spaces still matches.
        let mut r = defaults();
        r.hidden = vec!["  Edit_Block ".into()];
        assert!(r.is_hidden("edit_block"));
        // The no_prompt list stays exact: a near-miss still asks.
        assert_eq!(r.decide(" read_file", &json!({})), Decision::AskFirst);
    }

    #[test]
    fn a_url_read_asks_first() {
        let r = defaults();
        // A plain file read runs; the same tool fetching a URL from this Mac
        // (it can reach localhost and the homelab) asks first.
        assert_eq!(
            r.decide("read_file", &json!({"path": "/tmp/a"})),
            Decision::Run
        );
        assert_eq!(
            r.decide("read_file", &json!({"path": "/tmp/a", "isUrl": false})),
            Decision::Run
        );
        for odd in [json!(true), json!("true"), json!(1), json!(null), json!({})] {
            assert_eq!(
                r.decide(
                    "read_file",
                    &json!({"path": "http://localhost:8080/", "isUrl": odd})
                ),
                Decision::AskFirst,
                "isUrl={odd}"
            );
        }
        // Even if the person listed read_file in no_prompt (it is by default),
        // and whatever the case of the key's value, the URL rule holds.
        let mut r2 = r.clone();
        r2.no_prompt.push("read_file".into());
        assert_eq!(
            r2.decide("read_file", &json!({"path": "http://x", "isUrl": true})),
            Decision::AskFirst
        );
        // Hidden and paused still win.
        let mut r3 = r.clone();
        r3.paused = true;
        assert!(matches!(
            r3.decide("read_file", &json!({"isUrl": true})),
            Decision::Refuse(_)
        ));
        // Arguments that are not an object change nothing for other tools.
        assert_eq!(r.decide("list_directory", &json!(null)), Decision::Run);
        assert_eq!(
            r.decide("list_directory", &json!({"isUrl": true})),
            Decision::Run
        );
    }

    #[test]
    fn history_feedback_and_ui_tools_are_hidden_by_default() {
        let r = defaults();
        for t in [
            "get_recent_tool_calls",
            "give_feedback_to_desktop_commander",
            "track_ui_event",
        ] {
            assert!(r.is_hidden(t), "{t}");
            assert!(
                matches!(r.decide(t, &json!({})), Decision::Refuse(_)),
                "{t}"
            );
        }
        assert_eq!(
            r.hidden,
            [
                "set_config_value",
                "get_config",
                "get_recent_tool_calls",
                "give_feedback_to_desktop_commander",
                "track_ui_event"
            ]
        );
        // Unhiding is an edit of rules.toml: then it asks first.
        let mut r2 = r.clone();
        r2.hidden.retain(|h| h != "get_recent_tool_calls");
        assert_eq!(
            r2.decide("get_recent_tool_calls", &json!({})),
            Decision::AskFirst
        );
    }

    /// The defaults before R13 (Tasks 6 and 7, first commit), exactly as
    /// written to rules.toml.
    const R6_DEFAULTS: &str = r#"paused = false
hidden = ["set_config_value", "get_config"]   # never exposed remotely
config_allow = []    # settings tools to expose anyway; any other tool whose
                     # name contains "config" is hidden
# While paused, no tools are visible and every call is refused.
# Run without asking: reads only. Every other tool, including any tool a
# future desktop-commander adds, asks first.
no_prompt = ["read_file", "read_multiple_files", "list_directory",
             "get_file_info", "start_search", "get_more_search_results",
             "stop_search", "list_searches"]
"#;

    #[test]
    fn an_untouched_old_default_file_gets_the_new_defaults() {
        let dir = test_dir("rules-migrate");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(rules_path(&dir), R6_DEFAULTS).unwrap();
        let r = load(&dir).unwrap();
        assert!(r.is_hidden("get_recent_tool_calls"));
        assert!(r.is_hidden("give_feedback_to_desktop_commander"));
        assert!(r.is_hidden("track_ui_event"));
        assert_eq!(
            std::fs::read_to_string(rules_path(&dir)).unwrap(),
            DEFAULT_RULES
        );
        // A file the person edited, even by one character, is theirs.
        let edited = R6_DEFAULTS.replace("\"stop_search\"", "\"stop_search\" ");
        std::fs::write(rules_path(&dir), &edited).unwrap();
        let r = load(&dir).unwrap();
        assert!(!r.is_hidden("get_recent_tool_calls"));
        assert_eq!(std::fs::read_to_string(rules_path(&dir)).unwrap(), edited);
    }

    /// `vrelay pause` changes only the `paused` line: such a file is still
    /// an untouched default, upgraded with its pause kept.
    #[test]
    fn a_paused_old_default_is_upgraded_and_stays_paused() {
        let dir = test_dir("rules-migrate-paused");
        std::fs::create_dir_all(&dir).unwrap();
        let paused = R6_DEFAULTS.replace("paused = false", "paused = true");
        std::fs::write(rules_path(&dir), &paused).unwrap();
        assert!(file_warnings(&dir).is_empty());
        let r = load(&dir).unwrap();
        assert!(r.paused);
        assert!(r.is_hidden("get_recent_tool_calls"));
        assert_eq!(
            std::fs::read_to_string(rules_path(&dir)).unwrap(),
            DEFAULT_RULES.replace("paused = false", "paused = true")
        );
    }

    /// Final review I5: pause and resume change one line, so the file
    /// stays the untouched default, and what is loaded can be told apart
    /// from what is on disk.
    #[test]
    fn pause_and_resume_change_only_the_paused_line() {
        let dir = test_dir("rules-pause");
        set_paused(&dir, true).unwrap();
        let text = std::fs::read_to_string(rules_path(&dir)).unwrap();
        assert_eq!(
            text,
            DEFAULT_RULES.replace("paused = false", "paused = true")
        );
        let r = load(&dir).unwrap();
        assert!(r.paused);
        assert_eq!(Some(r.source_sha256.clone()), file_sha256(&dir));
        set_paused(&dir, false).unwrap();
        assert_eq!(
            std::fs::read_to_string(rules_path(&dir)).unwrap(),
            DEFAULT_RULES
        );
        assert_ne!(Some(r.source_sha256), file_sha256(&dir));
        // An edited file keeps its edits; one without the line gets it.
        std::fs::write(
            rules_path(&dir),
            "hidden = [\"x\"]  # mine\nno_prompt = []\n",
        )
        .unwrap();
        set_paused(&dir, true).unwrap();
        assert_eq!(
            std::fs::read_to_string(rules_path(&dir)).unwrap(),
            "paused = true\nhidden = [\"x\"]  # mine\nno_prompt = []\n"
        );
        assert!(load(&dir).unwrap().paused);
        // A file that does not load is not touched.
        std::fs::write(rules_path(&dir), "paused = [").unwrap();
        assert!(set_paused(&dir, false).is_err());
        assert_eq!(
            std::fs::read_to_string(rules_path(&dir)).unwrap(),
            "paused = ["
        );
    }

    #[test]
    fn the_defaults_say_how_to_reload() {
        assert!(DEFAULT_RULES.contains("vrelay reload"), "{DEFAULT_RULES}");
        assert!(DEFAULT_RULES.contains("vrelay pause"), "{DEFAULT_RULES}");
        // Every earlier default upgrades to these.
        for old in PREVIOUS_DEFAULTS {
            assert_eq!(upgraded(old).as_deref(), Some(DEFAULT_RULES));
        }
        assert_eq!(upgraded(DEFAULT_RULES), None);
    }

    #[test]
    fn an_edited_file_missing_new_hidden_defaults_is_warned_about_not_edited() {
        let dir = test_dir("rules-warn-edited");
        std::fs::create_dir_all(&dir).unwrap();
        let edited = R6_DEFAULTS.replace("no_prompt = [", "no_prompt = [\"start_process\", ");
        std::fs::write(rules_path(&dir), &edited).unwrap();
        let w = file_warnings(&dir);
        assert_eq!(w.len(), 1, "{w:?}");
        for t in [
            "get_recent_tool_calls",
            "give_feedback_to_desktop_commander",
            "track_ui_event",
        ] {
            assert!(w[0].contains(t), "{w:?}");
        }
        // get_config is hidden by the "config" rule anyway: not missing.
        assert!(!w[0].contains("get_config"), "{w:?}");
        assert!(w[0].contains("rules.toml"), "{w:?}");
        // Never edited.
        assert_eq!(std::fs::read_to_string(rules_path(&dir)).unwrap(), edited);
    }

    #[test]
    fn no_warning_for_current_untouched_old_or_missing_files() {
        let dir = test_dir("rules-warn-none");
        // No file: nothing to say, and nothing written.
        assert!(file_warnings(&dir).is_empty());
        assert!(!rules_path(&dir).exists());
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(rules_path(&dir), DEFAULT_RULES).unwrap();
        assert!(file_warnings(&dir).is_empty());
        // An untouched old default is upgraded by `load` at start: no
        // warning, and not upgraded here either.
        std::fs::write(rules_path(&dir), R6_DEFAULTS).unwrap();
        assert!(file_warnings(&dir).is_empty());
        assert_eq!(
            std::fs::read_to_string(rules_path(&dir)).unwrap(),
            R6_DEFAULTS
        );
    }

    #[test]
    fn missing_default_hidden_follows_the_hiding_rules() {
        assert!(missing_default_hidden(&defaults()).is_empty());
        let mut r = defaults();
        r.hidden = vec!["SET_CONFIG_VALUE ".into()];
        assert_eq!(
            missing_default_hidden(&r),
            vec![
                "get_recent_tool_calls",
                "give_feedback_to_desktop_commander",
                "track_ui_event"
            ]
        );
        // Exposing a settings tool through config_allow takes it out of
        // hiding: that is missing too.
        r.config_allow = vec!["get_config".into()];
        assert!(missing_default_hidden(&r).contains(&"get_config".to_string()));
    }

    #[test]
    fn a_file_that_does_not_load_is_warned_about() {
        let dir = test_dir("rules-warn-bad");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(rules_path(&dir), "hidden = [").unwrap();
        let w = file_warnings(&dir);
        assert_eq!(w.len(), 1, "{w:?}");
        assert!(w[0].contains("does not load"), "{w:?}");
    }

    /// Ruling R17: remote calls never touch vrelay's own folders, however
    /// the path is written, and a search that would reach them asks first.
    #[test]
    fn calls_never_reach_vrelays_own_folders() {
        let root = test_dir("rules-guard");
        let home = root.join("home");
        let state = home.join("Library/Application Support/vrelay");
        let dc = home.join(".claude-server-commander");
        std::fs::create_dir_all(&state).unwrap();
        std::fs::create_dir_all(&dc).unwrap();
        std::fs::create_dir_all(home.join("work")).unwrap();
        std::fs::write(state.join("token.json"), "{}").unwrap();
        let cfg = Config::from_lookup(|k| (k == "HOME").then(|| home.display().to_string()));
        let mut r = defaults();
        r.guard = Guard::for_config(&cfg, &home.join("work"));
        let refused = |r: &Rules, tool: &str, args: Value| matches!(r.decide(tool, &args), Decision::Refuse(why) if why.contains("vrelay's own"));
        let token = state.join("token.json").display().to_string();
        // Directly, and through `~`, `..`, a relative path and odd case.
        for p in [
            token.clone(),
            "~/Library/Application Support/vrelay/token.json".into(),
            "~/work/../Library/Application Support/vrelay/device.key".into(),
            "../Library/Application Support/vrelay/token.json".into(),
            "~/LIBRARY/Application Support/VRELAY/token.json".into(),
            "~/Library/Logs/vrelay/calls.log".into(),
            "~/.local/share/vrelay/bridge.json".into(),
            "~/.claude-server-commander/claude_tool_call.log".into(),
            "~/Library/Application Support/vrelay".into(),
        ] {
            assert!(refused(&r, "read_file", json!({ "path": p })), "{p}");
        }
        // Through a symlink that looks harmless.
        let link = home.join("work/notes");
        std::os::unix::fs::symlink(&state, &link).unwrap();
        assert!(refused(
            &r,
            "read_file",
            json!({"path": "~/work/notes/token.json"})
        ));
        assert!(refused(
            &r,
            "get_file_info",
            json!({"path": link.display().to_string()})
        ));
        // Every path argument, every tool: lists, writes, moves.
        assert!(refused(
            &r,
            "read_multiple_files",
            json!({"paths": ["/tmp/a", token.clone()]})
        ));
        assert!(refused(
            &r,
            "write_file",
            json!({"path": token.clone(), "content": "x"})
        ));
        assert!(refused(
            &r,
            "edit_block",
            json!({"file_path": token.clone()})
        ));
        assert!(refused(
            &r,
            "move_file",
            json!({"source": "/tmp/a", "destination": "~/.claude-server-commander/x"})
        ));
        assert!(refused(
            &r,
            "list_directory",
            json!({"path": "~/.local/share/vrelay"})
        ));
        // A search rooted inside is refused; at or above, it asks first.
        assert!(refused(
            &r,
            "start_search",
            json!({"path": "~/Library/Logs/vrelay", "pattern": "x"})
        ));
        for above in ["~", "~/Library", "/", "~/work/.."] {
            assert_eq!(
                r.decide("start_search", &json!({"path": above, "pattern": "token"})),
                Decision::AskFirst,
                "{above}"
            );
        }
        // Elsewhere nothing changes.
        assert_eq!(
            r.decide("read_file", &json!({"path": "~/work/a.txt"})),
            Decision::Run
        );
        assert_eq!(
            r.decide("start_search", &json!({"path": "~/work", "pattern": "x"})),
            Decision::Run
        );
        assert_eq!(
            r.decide(
                "read_file",
                &json!({"path": "~/Library/Application Support/vrelay-other/x"})
            ),
            Decision::Run
        );
        // A reload keeps the guard (it is not in the file).
        let dir = root.join("rules");
        load(&dir).unwrap();
        let again = reload(&dir, &r, &[]).unwrap().rules;
        assert!(refused(&again, "read_file", json!({ "path": token })));
    }

    /// Rules for a pretend home with a work folder, the folder limits applied.
    fn limited(home: &Path, allowed: &[&str]) -> Rules {
        let cfg = Config::from_lookup(|k| (k == "HOME").then(|| home.display().to_string()));
        let mut r = defaults();
        r.allowed_folders = allowed.iter().map(|s| s.to_string()).collect();
        r.set_guard(Guard::for_config(&cfg, &home.join("work")));
        r
    }

    fn refused_outside(r: &Rules, tool: &str, args: Value) -> bool {
        r.decide(tool, &args) == Decision::Refuse(OUTSIDE_ALLOWED)
    }

    /// Relay P2: the file tools stay inside the folders the person chose
    /// (home by default), however the path is written.
    #[test]
    fn file_tool_outside_allowed_folders_is_refused() {
        let root = test_dir("rules-limit");
        let home = root.join("home");
        std::fs::create_dir_all(home.join("work")).unwrap();
        let r = limited(&home, &["~"]);
        assert_eq!(
            OUTSIDE_ALLOWED,
            "outside your allowed folders; change them in Vitruvian Relay's settings"
        );
        // Outside home: refused, for every path argument and every tool.
        for (tool, args) in [
            ("read_file", json!({"path": "/etc/hosts"})),
            ("read_file", json!({"path": "~/../other/x"})),
            ("read_file", json!({"path": "../../elsewhere"})),
            (
                "read_multiple_files",
                json!({"paths": ["~/work/a", "/etc/hosts"]}),
            ),
            ("write_file", json!({"path": "/etc/hosts", "content": "x"})),
            ("edit_block", json!({"file_path": "/etc/hosts"})),
            (
                "move_file",
                json!({"source": "~/work/a", "destination": "/tmp/a"}),
            ),
            ("get_file_info", json!({"path": "/"})),
            ("start_search", json!({"path": "/", "pattern": "x"})),
        ] {
            assert!(refused_outside(&r, tool, args.clone()), "{tool} {args}");
        }
        // Inside it: as before.
        for p in [
            "~",
            "~/work/a.txt",
            "a.txt",
            "../work/b",
            &format!("{}/c", home.display()),
        ] {
            assert_eq!(
                r.decide("read_file", &json!({"path": p})),
                Decision::Run,
                "{p}"
            );
        }
        assert_eq!(
            r.decide("write_file", &json!({"path": "~/work/a.txt"})),
            Decision::AskFirst
        );
        // A tool with no path (the terminal) is not path-checked.
        assert_eq!(
            r.decide("start_process", &json!({"command": "cat /etc/hosts"})),
            Decision::AskFirst
        );
        // Chosen folders replace the default; none allows no path at all.
        let narrow = limited(&home, &["~/work"]);
        assert_eq!(
            narrow.decide("read_file", &json!({"path": "~/work/a"})),
            Decision::Run
        );
        assert!(refused_outside(
            &narrow,
            "read_file",
            json!({"path": "~/notes"})
        ));
        assert!(refused_outside(
            &narrow,
            "read_file",
            json!({"path": "~/work2/a"})
        ));
        let none = limited(&home, &[]);
        assert!(refused_outside(
            &none,
            "read_file",
            json!({"path": "~/work/a"})
        ));
        // vrelay's own folders keep their own, older refusal.
        let own = r.decide(
            "read_file",
            &json!({"path": "~/Library/Application Support/vrelay/token.json"}),
        );
        assert!(
            matches!(own, Decision::Refuse(w) if w.contains("vrelay's own")),
            "{own:?}"
        );
        // A reload keeps the limit, and takes a changed list.
        let dir = root.join("rules");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(
            rules_path(&dir),
            DEFAULT_RULES.replace(
                "allowed_folders = [\"~\"]",
                "allowed_folders = [\"~/work\"]",
            ),
        )
        .unwrap();
        let again = reload(&dir, &r, &[]).unwrap().rules;
        assert!(refused_outside(
            &again,
            "read_file",
            json!({"path": "~/notes"})
        ));
        assert_eq!(
            again.decide("read_file", &json!({"path": "~/work/a"})),
            Decision::Run
        );
    }

    #[test]
    fn symlink_out_of_allowed_folder_is_refused() {
        let root = test_dir("rules-limit-link");
        let home = root.join("home");
        let outside = root.join("outside");
        std::fs::create_dir_all(home.join("work")).unwrap();
        std::fs::create_dir_all(&outside).unwrap();
        std::fs::write(outside.join("secret"), "s").unwrap();
        std::os::unix::fs::symlink(&outside, home.join("work/escape")).unwrap();
        let r = limited(&home, &["~"]);
        assert!(refused_outside(
            &r,
            "read_file",
            json!({"path": "~/work/escape/secret"})
        ));
        assert!(refused_outside(
            &r,
            "read_file",
            json!({"path": "~/work/escape"})
        ));
        // Not yet there, but under the link: still outside.
        assert!(refused_outside(
            &r,
            "write_file",
            json!({"path": "~/work/escape/new/f"})
        ));
        assert!(refused_outside(
            &r,
            "start_search",
            json!({"path": "~/work/escape", "pattern": "s"})
        ));
        // A link that stays inside is fine; so is an allowed folder that is itself a link.
        std::os::unix::fs::symlink(home.join("work"), home.join("again")).unwrap();
        assert_eq!(
            r.decide("read_file", &json!({"path": "~/again/x"})),
            Decision::Run
        );
        let via_link = limited(&home, &["~/again"]);
        assert_eq!(
            via_link.decide("read_file", &json!({"path": "~/work/x"})),
            Decision::Run
        );
        assert!(refused_outside(
            &via_link,
            "read_file",
            json!({"path": "~/work/escape/secret"})
        ));
    }

    /// An untouched P1 file takes the new defaults; a paused one stays
    /// paused; an edited one is the person's own and only gains the defaults
    /// of the settings it never had.
    #[test]
    fn p1_rules_file_upgrades_with_new_defaults() {
        let p1 = PREVIOUS_DEFAULTS[0];
        assert!(!p1.contains("keep_awake") && !p1.contains("allowed_folders"));
        let dir = test_dir("rules-p1");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(rules_path(&dir), p1).unwrap();
        let r = load(&dir).unwrap();
        assert_eq!(
            std::fs::read_to_string(rules_path(&dir)).unwrap(),
            DEFAULT_RULES
        );
        assert!(r.keep_awake);
        assert_eq!(r.allowed_folders, vec!["~".to_string()]);
        // Paused with `vrelay pause` before the upgrade: still paused after.
        let dir = test_dir("rules-p1-paused");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(rules_path(&dir), with_paused(p1, true).unwrap()).unwrap();
        let r = load(&dir).unwrap();
        assert!(r.paused && r.keep_awake);
        assert_eq!(
            std::fs::read_to_string(rules_path(&dir)).unwrap(),
            with_paused(DEFAULT_RULES, true).unwrap()
        );
        // The older defaults still upgrade, straight to the current ones.
        let dir = test_dir("rules-p0");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(rules_path(&dir), PREVIOUS_DEFAULTS[1]).unwrap();
        load(&dir).unwrap();
        assert_eq!(
            std::fs::read_to_string(rules_path(&dir)).unwrap(),
            DEFAULT_RULES
        );
        // An edited P1 file is left alone, and the new settings take their defaults.
        let dir = test_dir("rules-p1-edited");
        std::fs::create_dir_all(&dir).unwrap();
        let edited = format!("{p1}# mine\n");
        std::fs::write(rules_path(&dir), &edited).unwrap();
        let r = load(&dir).unwrap();
        assert_eq!(std::fs::read_to_string(rules_path(&dir)).unwrap(), edited);
        assert!(r.keep_awake);
        assert_eq!(r.allowed_folders, vec!["~".to_string()]);
        // The current defaults say both out loud.
        let d = defaults();
        assert!(d.keep_awake);
        assert_eq!(d.allowed_folders, vec!["~".to_string()]);
        let off: Rules =
            toml::from_str(&DEFAULT_RULES.replace("keep_awake = true", "keep_awake = false"))
                .unwrap();
        assert!(!off.keep_awake);
    }

    /// Review: the allowed folders are compared exactly on a case-sensitive
    /// volume (`~/work` is not `~/Work` there) and ignoring case on one that
    /// ignores it (APFS by default), the guard erring only towards refusing.
    #[test]
    fn allowed_folders_follow_the_volumes_case_rules() {
        let root = test_dir("rules-limit-case");
        let home = root.join("home");
        std::fs::create_dir_all(home.join("Work")).unwrap();
        let work = home.join("Work");
        // The probe agrees with asking the volume directly.
        let ignores = std::fs::metadata(home.join("wORK")).is_ok();
        assert_eq!(volume_ignores_case(&work), ignores);
        // Exact mode: the same spelling always; another one only where the
        // volume itself says it is the same folder (the system then hands
        // back the folder's real spelling).
        let exact = Guard::build(&home, &home, std::slice::from_ref(&work), false);
        assert!(exact.under("~/Work/a"));
        assert_eq!(exact.under("~/work/a"), ignores);
        assert_eq!(exact.under("~/WORK"), ignores);
        // Folding mode (a volume that ignores case): any spelling.
        let fold = Guard::build(&home, &home, std::slice::from_ref(&work), true);
        assert!(fold.under("~/Work/a") && fold.under("~/work/a") && fold.under("~/WORK"));
        // The rules pick the mode from the volume.
        let r = limited(&home, &["~/Work"]);
        assert_eq!(
            r.decide("read_file", &json!({"path": "~/Work/a"})),
            Decision::Run
        );
        let other_case = r.decide("read_file", &json!({"path": "~/work/a"}));
        if ignores {
            assert_eq!(other_case, Decision::Run);
        } else {
            assert_eq!(other_case, Decision::Refuse(OUTSIDE_ALLOWED));
        }
        // No allowed folder at all never folds into allowing something.
        assert!(!limited(&home, &[]).limit.unwrap().fold);
    }
}
