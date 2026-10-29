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

//! registry.py: the multi-marketplace registry. Scans plugin manifests
//! across the monorepo, without copying release-please's version numbers,
//! and writes `_data/extensions.yml`, `ai/catalog.json` and both copies of
//! `.claude-plugin/marketplace.json`.

use crate::json::{self, list_of_str, obj, s, Value};
use crate::pyerr::PyErr;
use crate::pyfs;
use crate::pystr::PyStr;

pub const DATA_YML: &str = "apps/web/vitruviansoftware-dev/_data/extensions.yml";
pub const AI_CATALOG_JSON: &str = "apps/web/vitruviansoftware-dev/ai/catalog.json";
pub const CLAUDE_MARKETPLACE_ROOT: &str = ".claude-plugin/marketplace.json";
pub const CLAUDE_MARKETPLACE_WEB: &str =
    "apps/web/vitruviansoftware-dev/.claude-plugin/marketplace.json";

pub const ANTIGRAVITY_PLUGINS_DIR: &str = "apps/desktop/antigravity/plugins";
pub const CLAUDE_CODE_PLUGINS_DIR: &str = "apps/claude-code/plugins";

/// The order first-party plugins are shown in; others follow, by id.
pub const PREFERRED_PLUGIN_ORDER: &[&str] = &[
    "ext-marketplace",
    "gh-watch",
    "worktree-band",
    "ralph-loop",
    "hookify",
    "security-guidance",
    "receipts-report",
    "live-context",
    "savvy-fleet",
];

/// Titles and notes for a plugin whose manifest has no `marketplace` block.
struct Known {
    id: &'static str,
    title: &'static str,
    category: &'static str,
    status: &'static str,
    needs: &'static str,
    note: Option<&'static str>,
}

const NEEDS_DEFAULT: &str = "Antigravity desktop or Claude Code CLI";

const KNOWN_PLUGIN_META: &[Known] = &[
    Known {
        id: "ext-marketplace",
        title: "ext-marketplace",
        category: "Marketplace & Manager",
        status: "in-development",
        needs: "Antigravity desktop (or Claude Code CLI for skill/hook inspection)",
        note: Some("Opens the Extensions Marketplace & Live Plugin Manager sidecar to toggle installed plugins and 1-click install any extension in this catalog."),
    },
    Known {
        id: "gh-watch",
        title: "gh-watch",
        category: "CI & GitHub",
        status: "mirror",
        needs: "Antigravity desktop or Claude Code CLI, and the GitHub CLI signed in",
        note: None,
    },
    Known {
        id: "worktree-band",
        title: "worktree-band",
        category: "Git & Workspaces",
        status: "in-development",
        needs: "Antigravity desktop or Claude Code CLI, git, and GitHub CLI",
        note: None,
    },
    Known {
        id: "ralph-loop",
        title: "ralph-loop",
        category: "Autonomous Loops",
        status: "in-development",
        needs: NEEDS_DEFAULT,
        note: None,
    },
    Known {
        id: "hookify",
        title: "hookify",
        category: "Guardrails & Hooks",
        status: "in-development",
        needs: NEEDS_DEFAULT,
        note: None,
    },
    Known {
        id: "security-guidance",
        title: "security-guidance",
        category: "Security & AppSec",
        status: "in-development",
        needs: NEEDS_DEFAULT,
        note: None,
    },
    Known {
        id: "receipts-report",
        title: "receipts-report",
        category: "Telemetry & Audit",
        status: "in-development",
        needs: NEEDS_DEFAULT,
        note: None,
    },
    Known {
        id: "live-context",
        title: "live-context",
        category: "Context & Anti-Drift",
        status: "in-development",
        needs: NEEDS_DEFAULT,
        note: None,
    },
    Known {
        id: "savvy-fleet",
        title: "savvy-fleet",
        category: "Subagent Orchestration",
        status: "in-development",
        needs: NEEDS_DEFAULT,
        note: None,
    },
];

/// ECOSYSTEMS, in its order, each key present only where registry.py has it.
pub fn ecosystems() -> Vec<Value> {
    let eco =
        |id: &str, title: &str, badge: &str, blurb: &str, rest: Option<(&str, &str, &str)>| {
            let mut pairs = vec![
                ("id", s(id)),
                ("title", s(title)),
                ("badge", s(badge)),
                ("blurb", s(blurb)),
            ];
            if let Some((label, command, feed)) = rest {
                pairs.push(("bootstrap_label", s(label)));
                pairs.push(("bootstrap_command", s(command)));
                pairs.push(("feed_url", s(feed)));
            }
            obj(pairs)
        };
    vec![
        eco(
            "all",
            "All Ecosystems",
            "All",
            "Every first-party plugin, MCP server, agent skill, and signed desktop/mobile extension across the Vitruvian monorepo.",
            None,
        ),
        eco(
            "antigravity",
            "Antigravity Desktop",
            "Antigravity",
            "Native plugins with sidecar web panels, lifecycle hooks, rules, and skills for Antigravity Desktop.",
            Some((
                "Install the Antigravity Extensions Marketplace",
                "agy plugin install https://github.com/VitruvianSoftware/ext-marketplace",
                "/ai/catalog.json",
            )),
        ),
        eco(
            "claude-code",
            "Claude Code",
            "Claude Code",
            "Installable via the root .claude-plugin/marketplace.json catalog: hooks, guardrails, skills, and MCP servers.",
            Some((
                "Add the Vitruvian marketplace in Claude Code",
                "claude plugin marketplace add VitruvianSoftware/vitruvian-core",
                "/.claude-plugin/marketplace.json",
            )),
        ),
        eco(
            "codex-opencode",
            "Codex & OpenCode",
            "Codex / OpenCode",
            "Portable SKILL.md agent workflows and standard stdio/HTTP Model Context Protocol servers.",
            Some(("Bootstrap project skills", "devx agent init", "/ai/catalog.json")),
        ),
        eco(
            "mcp",
            "MCP Servers",
            "MCP",
            "Model Context Protocol servers that work across Claude Code, Antigravity, OpenCode, Codex, and Cursor.",
            Some((
                "Add Slack MCP server",
                "claude mcp add slack -- npx -y @vitruviansoftware/mcp-slack@latest",
                "/ai/catalog.json",
            )),
        ),
        eco(
            "vitruvian-desktop",
            "Vitruvian Desktop (macOS)",
            "Vitruvian macOS",
            "Ed25519-signed JSON-RPC 2.0 extensions for the macOS notch island, Command Bar, and Radial menu.",
            Some((
                "In-app catalog",
                "Vitruvian › Settings › Extensions",
                "/tools/catalog/tools.json",
            )),
        ),
        eco(
            "vitruvian-remote",
            "Vitruvian Remote (Android)",
            "Android Remote",
            "Foldable Android remote, Tailscale bridge, Sony Google TV control, and live host observability companions.",
            Some((
                "Download Android APK",
                "https://vitruviansoftware.dev/downloads/",
                "/tools/catalog/tools.json",
            )),
        ),
    ]
}

/// EXTENSION_KINDS.
pub fn extension_kinds() -> Vec<(&'static str, &'static str, &'static str)> {
    vec![
        (
            "plugin",
            "Agent Plugins & Marketplaces",
            "Installed into Antigravity Desktop or Claude Code as a unit. A plugin can add sidecar web panels, background watchers, lifecycle hooks, rules, and skills.",
        ),
        (
            "mcp",
            "MCP Servers",
            "Model Context Protocol servers. They give any MCP-compatible agent structured, reviewable access to external systems and hardware.",
        ),
        (
            "skill",
            "Portable Agent Skills",
            "SKILL.md instructions an agent loads on demand across Antigravity, Claude Code, OpenCode, and Codex.",
        ),
    ]
}

/// One extension, as registry.py's dicts hold it. A field a manifest can
/// set is a Value, of whatever type the manifest gave it.
#[derive(Clone, Debug)]
pub struct Ext {
    pub id: Value,
    pub name: Value,
    pub kind: Value,
    pub category: Value,
    pub status: Value,
    pub summary: Value,
    pub repo: Value,
    pub mirror_repo: Value,
    pub source: Value,
    pub ecosystems: Vec<Value>,
    pub capabilities: Vec<PyStr>,
    pub skills: Vec<PyStr>,
    pub hooks: Vec<PyStr>,
    pub rules: Vec<PyStr>,
    pub keywords: Value,
    pub needs: Value,
    pub note: Value,
    pub installs: Vec<Value>,
    pub claude_marketplace_source: Value,
}

fn strs(items: &[PyStr]) -> Value {
    Value::List(items.iter().cloned().map(Value::Str).collect())
}

/// What inspect_capabilities finds in a plugin's folder.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Caps {
    pub capabilities: Vec<PyStr>,
    pub skills: Vec<PyStr>,
    pub hooks: Vec<PyStr>,
    pub rules: Vec<PyStr>,
    pub has_sidecar: bool,
    pub has_claude_plugin: bool,
}

pub fn inspect_capabilities(plugin_dir: &PyStr) -> Result<Caps, PyErr> {
    let mut caps = Caps {
        has_claude_plugin: pyfs::is_file(&pyfs::path_join(
            plugin_dir,
            ".claude-plugin/plugin.json",
        ))?,
        ..Caps::default()
    };

    let sidecars_dir = pyfs::path_join(plugin_dir, "sidecars");
    if pyfs::is_dir(&sidecars_dir)? {
        for (child, _) in pyfs::sorted_children(&sidecars_dir)? {
            if pyfs::is_dir(&child)? && pyfs::is_file(&pyfs::path_join(&child, "sidecar.json"))? {
                caps.has_sidecar = true;
                break;
            }
        }
    }
    if caps.has_sidecar {
        caps.capabilities.push(PyStr::from("Sidecar UI"));
    }

    let hooks_json = pyfs::path_join(plugin_dir, "hooks.json");
    if pyfs::is_file(&hooks_json)? {
        // `except Exception`: any failure to read or parse it.
        match pyfs::read_text(&hooks_json).and_then(|text| json::loads(&text)) {
            Ok(Value::Dict(pairs)) => {
                let mut keys: Vec<PyStr> = pairs.into_iter().map(|(k, _)| k).collect();
                keys.sort();
                caps.hooks = keys;
            }
            Ok(_) => {}
            Err(_) => caps.hooks = vec![PyStr::from("hooks")],
        }
        caps.capabilities.push(PyStr::from("Lifecycle Hooks"));
    }

    let skills_dir = pyfs::path_join(plugin_dir, "skills");
    if pyfs::is_dir(&skills_dir)? {
        for (child, name) in pyfs::sorted_children(&skills_dir)? {
            if pyfs::is_dir(&child)? && pyfs::is_file(&pyfs::path_join(&child, "SKILL.md"))? {
                caps.skills.push(name);
            }
        }
        if !caps.skills.is_empty() {
            let n = caps.skills.len();
            caps.capabilities.push(PyStr::from(format!(
                "{} Skill{}",
                n,
                if n != 1 { "s" } else { "" }
            )));
        }
    }

    let rules_dir = pyfs::path_join(plugin_dir, "rules");
    if pyfs::is_dir(&rules_dir)? {
        for (child, name) in pyfs::sorted_children(&rules_dir)? {
            if pyfs::is_file(&child)? && name.ends_with(".md") {
                caps.rules.push(name);
            }
        }
        if !caps.rules.is_empty() {
            caps.capabilities.push(PyStr::from("Rules"));
        }
    }

    if pyfs::is_file(&pyfs::path_join(plugin_dir, ".mcp.json"))?
        || pyfs::is_file(&pyfs::path_join(plugin_dir, "mcp.json"))?
    {
        caps.capabilities.push(PyStr::from("MCP Server"));
    }
    Ok(caps)
}

/// `a or b`: the first truthy value, else the last.
fn or(a: Value, b: impl FnOnce() -> Result<Value, PyErr>) -> Result<Value, PyErr> {
    if a.truthy() {
        Ok(a)
    } else {
        b()
    }
}

fn str_cat(parts: &[&str], value: &PyStr) -> PyStr {
    let mut out = PyStr::from(parts[0]);
    out.push(value);
    for part in &parts[1..] {
        out.push_str(part);
    }
    out
}

fn in_list(items: &[Value], text: &str) -> bool {
    items.iter().any(|item| item.eq_str(text))
}

fn is_released(status: &Value) -> bool {
    status.eq_str("released") || status.eq_str("mirror")
}

fn install(
    tool: &str,
    ecosystem: &str,
    label: Value,
    command: Value,
) -> Vec<(&'static str, Value)> {
    vec![
        ("tool", s(tool)),
        ("ecosystem", s(ecosystem)),
        ("label", label),
        ("command", command),
    ]
}

/// `discover_plugin_dir(root, plugin_dir, default_host)`.
pub fn discover_plugin_dir(
    root: &PyStr,
    rel_source: &PyStr,
    default_host: &str,
) -> Result<Option<Ext>, PyErr> {
    let plugin_dir = pyfs::path_str(&pyfs::join_s(root, rel_source));
    let plugin_json_path = pyfs::path_join(&plugin_dir, "plugin.json");
    let claude_json_path = pyfs::path_join(&plugin_dir, ".claude-plugin/plugin.json");
    let manifest = if pyfs::is_file(&plugin_json_path)? {
        json::loads(&pyfs::read_text(&plugin_json_path)?)?
    } else if pyfs::is_file(&claude_json_path)? {
        json::loads(&pyfs::read_text(&claude_json_path)?)?
    } else {
        return Ok(None);
    };

    let ext_id = manifest.subscript("name")?.clone();
    let custom = or(manifest.get_value("marketplace")?, || {
        or(manifest.get_value("x-vitruvian")?, || {
            Ok(Value::Dict(Vec::new()))
        })
    })?;
    ext_id.check_hashable()?;
    let known = KNOWN_PLUGIN_META.iter().find(|k| ext_id.eq_str(k.id));
    let caps = inspect_capabilities(&plugin_dir)?;

    let ext_id_str = ext_id.py_str();
    let repo_url = or(custom.get_value("repo")?, || {
        manifest.get_or(
            "repository",
            Value::Str(str_cat(
                &["https://github.com/VitruvianSoftware/"],
                &ext_id_str,
            )),
        )
    })?;
    let status = or(custom.get_value("status")?, || {
        Ok(s(known.map_or("in-development", |k| k.status)))
    })?;
    let public_repo = if is_released(&status) {
        repo_url.clone()
    } else {
        s("")
    };

    let mut ecosystems = or(custom.get_value("ecosystems")?, || {
        Ok(Value::List(Vec::new()))
    })?
    .iterate()?;
    if ecosystems.is_empty() {
        if pyfs::is_file(&plugin_json_path)? || default_host == "antigravity" {
            ecosystems.push(s("antigravity"));
        }
        if caps.has_claude_plugin || default_host == "claude-code" {
            ecosystems.push(s("claude-code"));
        }
        if !caps.skills.is_empty() {
            ecosystems.push(s("codex-opencode"));
        }
    }

    let mut installs = or(custom.get_value("installs")?, || {
        Ok(Value::List(Vec::new()))
    })?
    .iterate()?;
    if installs.is_empty() {
        if in_list(&ecosystems, "antigravity") {
            let install_target = if is_released(&status) {
                repo_url.py_str()
            } else {
                str_cat(
                    &["https://github.com/VitruvianSoftware/vitruvian-core/tree/main/"],
                    rel_source,
                )
            };
            let mut pairs = install(
                "Antigravity",
                "antigravity",
                s("Install in Antigravity"),
                Value::Str(str_cat(&["agy plugin install "], &repo_url.py_str())),
            );
            pairs.push((
                "monorepo_command",
                Value::Str(str_cat(&["agy plugin install "], &install_target)),
            ));
            installs.push(obj(pairs));
        }
        if in_list(&ecosystems, "claude-code") {
            installs.push(obj(install(
                "Claude Code",
                "claude-code",
                s("Install in Claude Code (after adding marketplace)"),
                Value::Str(str_cat(&["claude plugin install "], &ext_id_str)),
            )));
        }
        if in_list(&ecosystems, "codex-opencode") && !caps.skills.is_empty() {
            let shown: Vec<PyStr> = caps
                .skills
                .iter()
                .map(|skill| str_cat(&["/"], skill))
                .collect();
            let skill_list = PyStr::join(", ", &shown);
            installs.push(obj(install(
                "Codex / OpenCode",
                "codex-opencode",
                Value::Str(str_cat(&["Load portable SKILL.md (", ")"], &skill_list)),
                Value::Str(str_cat(
                    &["cp -R ", "/skills/* ~/.agents/skills/"],
                    rel_source,
                )),
            )));
        }
    }

    let name = or(custom.get_value("title")?, || {
        Ok(match known {
            Some(k) => s(k.title),
            None => ext_id.clone(),
        })
    })?;
    let category = or(custom.get_value("category")?, || {
        Ok(s(known.map_or("Agent Plugin", |k| k.category)))
    })?;
    let summary = or(custom.get_value("summary")?, || {
        manifest.get_or("description", s(""))
    })?;
    let keywords = manifest.get_or("keywords", Value::List(Vec::new()))?;
    let needs = or(custom.get_value("needs")?, || {
        Ok(s(known.map_or(NEEDS_DEFAULT, |k| k.needs)))
    })?;
    let note = or(custom.get_value("note")?, || {
        Ok(s(known.and_then(|k| k.note).unwrap_or("")))
    })?;
    let claude_marketplace_source = if caps.has_claude_plugin {
        Value::Str(str_cat(&["./"], rel_source))
    } else {
        s("")
    };

    Ok(Some(Ext {
        id: ext_id,
        name,
        kind: s("plugin"),
        category,
        status,
        summary,
        repo: public_repo,
        mirror_repo: repo_url,
        source: Value::Str(rel_source.clone()),
        ecosystems,
        capabilities: caps.capabilities,
        skills: caps.skills,
        hooks: caps.hooks,
        rules: caps.rules,
        keywords,
        needs,
        note,
        installs,
        claude_marketplace_source,
    }))
}

/// `(order_map.get(id, 999), id) < (other's)`, as CPython's
/// unsafe_tuple_compare decides it.
fn key_lt(a: &(i64, Value), b: &(i64, Value)) -> Result<bool, PyErr> {
    if a.0 != b.0 {
        return Ok(a.0 < b.0);
    }
    if a.1.py_eq(&b.1) {
        return Ok(false);
    }
    a.1.py_lt(&b.1)
}

/// `list.sort(key=...)` as CPython 3.12 runs it on a list shorter than 64:
/// one run found by count_run, the rest by binary insertion, so the same
/// pairs are compared in the same order and a comparison that raises
/// raises the same error. Longer lists are sorted by a stable binary
/// insertion, which agrees wherever the ids are totally ordered.
fn py_sort<T: Clone>(
    items: &mut Vec<T>,
    lt: impl Fn(&T, &T) -> Result<bool, PyErr>,
) -> Result<(), PyErr> {
    let n = items.len();
    if n < 2 {
        return Ok(());
    }
    if n >= 64 {
        let mut error = None;
        let mut sorted: Vec<T> = Vec::with_capacity(n);
        for item in items.iter() {
            let mut lo = 0;
            let mut hi = sorted.len();
            while lo < hi {
                let mid = (lo + hi) / 2;
                match lt(item, &sorted[mid]) {
                    Ok(true) => hi = mid,
                    Ok(false) => lo = mid + 1,
                    Err(e) => {
                        error = Some(e);
                        break;
                    }
                }
            }
            if let Some(e) = error.take() {
                return Err(e);
            }
            sorted.insert(lo, item.clone());
        }
        *items = sorted;
        return Ok(());
    }
    // count_run
    let mut run = 2;
    if lt(&items[1], &items[0])? {
        while run < n && lt(&items[run], &items[run - 1])? {
            run += 1;
        }
        items[..run].reverse();
    } else {
        while run < n && !lt(&items[run], &items[run - 1])? {
            run += 1;
        }
    }
    // binarysort(lo, hi, start = lo + run)
    for start in run..n {
        let pivot = items[start].clone();
        let mut l = 0;
        let mut r = start;
        loop {
            let p = l + ((r - l) >> 1);
            if lt(&pivot, &items[p])? {
                r = p;
            } else {
                l = p + 1;
            }
            if l >= r {
                break;
            }
        }
        let moved = items.remove(start);
        items.insert(l, moved);
    }
    Ok(())
}

fn additional() -> Vec<Ext> {
    let install = |tool: &str, ecosystem: &str, label: &str, command: &str| {
        obj(vec![
            ("tool", s(tool)),
            ("ecosystem", s(ecosystem)),
            ("label", s(label)),
            ("command", s(command)),
        ])
    };
    let caps = |items: &[&str]| items.iter().map(|&c| PyStr::from(c)).collect::<Vec<_>>();
    let ecos = |items: &[&str]| items.iter().map(|&c| s(c)).collect::<Vec<_>>();
    vec![
        Ext {
            id: s("mcp-roborock"),
            name: s("mcp-roborock"),
            kind: s("plugin"),
            category: s("Home Automation & FastMCP"),
            status: s("mirror"),
            summary: s("A Roborock vacuum integration: a local daemon, a FastMCP server and plugins that let a coding agent check status, start room cleans or send the robot home."),
            repo: s("https://github.com/VitruvianSoftware/mcp-roborock"),
            mirror_repo: s("https://github.com/VitruvianSoftware/mcp-roborock"),
            source: s("apps/mcp/roborock"),
            ecosystems: ecos(&["claude-code", "antigravity", "codex-opencode", "mcp"]),
            capabilities: caps(&["MCP Server", "2 Skills", "CLI Daemon"]),
            skills: caps(&["roborock-control", "roborock-setup"]),
            hooks: vec![],
            rules: vec![],
            keywords: list_of_str(&["roborock", "vacuum", "home-automation", "mcp"]),
            needs: s("uv, and a Roborock account (the plugin walks you through logging in)"),
            note: s(""),
            installs: vec![
                install("Claude Code", "claude-code", "Claude Code, step 1: add the marketplace", "claude plugin marketplace add VitruvianSoftware/mcp-roborock"),
                install("Claude Code", "claude-code", "Claude Code, step 2: install", "claude plugin install vitruvian-roborock"),
                install("Antigravity", "antigravity", "Install in Antigravity", "agy plugin install https://github.com/VitruvianSoftware/mcp-roborock"),
            ],
            claude_marketplace_source: s("./apps/mcp/roborock/plugin"),
        },
        Ext {
            id: s("nexus-agent"),
            name: s("NexusAgent"),
            kind: s("plugin"),
            category: s("Remote Agent Bridge"),
            status: s("mirror"),
            summary: s("A macOS menu bar app and Telegram bot that forwards your messages to a locally installed AI coding CLI, so a full agent session is reachable from your phone."),
            repo: s("https://github.com/VitruvianSoftware/nexus-agent"),
            mirror_repo: s("https://github.com/VitruvianSoftware/nexus-agent"),
            source: s("apps/desktop/nexus-agent"),
            ecosystems: ecos(&["antigravity", "claude-code", "vitruvian-desktop"]),
            capabilities: caps(&["2 Skills", "macOS Menu Bar", "Telegram Bridge"]),
            skills: caps(&["configure", "access"]),
            hooks: vec![],
            rules: vec![],
            keywords: list_of_str(&["telegram", "remote-agent", "macos", "antigravity"]),
            needs: s("Node.js and a Telegram account"),
            note: s("Installing adds a setup guide to Antigravity. Then ask the agent to \"help me set up the Telegram bot\" and it walks you through creating the bot and starting it."),
            installs: vec![
                install("Antigravity", "antigravity", "Install in Antigravity", "agy plugin install https://github.com/VitruvianSoftware/nexus-agent"),
            ],
            claude_marketplace_source: s(""),
        },
        Ext {
            id: s("mcp-slack"),
            name: s("mcp-slack"),
            kind: s("mcp"),
            category: s("Team Communication MCP"),
            status: s("mirror"),
            summary: s("A Slack MCP server with dual-token auth: around forty tools covering channels, threads, search, files, user groups and Canvas editing, acting as the bot or as you."),
            repo: s("https://github.com/VitruvianSoftware/mcp-slack"),
            mirror_repo: s("https://github.com/VitruvianSoftware/mcp-slack"),
            source: s("apps/mcp/slack"),
            ecosystems: ecos(&["claude-code", "antigravity", "codex-opencode", "mcp"]),
            capabilities: caps(&["MCP Server", "40+ Slack Tools", "Dual-Token Auth"]),
            skills: vec![],
            hooks: vec![],
            rules: vec![],
            keywords: list_of_str(&["slack", "mcp", "typescript"]),
            needs: s("Slack bot and user tokens, passed to the server as environment variables (add an --env flag for each; the README lists them)"),
            note: s(""),
            installs: vec![
                install("Claude Code", "claude-code", "Install in Claude Code", "claude mcp add slack -- npx -y @vitruviansoftware/mcp-slack@latest"),
                install("Antigravity", "antigravity", "Install in Antigravity", "agy mcp add slack npx -y @vitruviansoftware/mcp-slack@latest"),
                install("Codex / OpenCode", "codex-opencode", "Run via npx (stdio MCP)", "npx -y @vitruviansoftware/mcp-slack@latest"),
            ],
            claude_marketplace_source: s(""),
        },
        Ext {
            id: s("devx"),
            name: s("devx"),
            kind: s("skill"),
            category: s("Local Dev & K3s Skills"),
            status: s("released"),
            summary: s("A local development orchestrator. One CLI provisions container VMs, ephemeral databases and cloud emulators, local K3s clusters and Cloudflare tunnel ingress, and starts everything in dependency order."),
            repo: s("https://github.com/VitruvianSoftware/devx"),
            mirror_repo: s("https://github.com/VitruvianSoftware/devx"),
            source: s("apps/cli/devx"),
            ecosystems: ecos(&["antigravity", "claude-code", "codex-opencode"]),
            capabilities: caps(&["Portable Agent Skills", "Homebrew CLI"]),
            skills: caps(&["devx"]),
            hooks: vec![],
            rules: vec![],
            keywords: list_of_str(&["devx", "k3s", "lima", "skills"]),
            needs: s("devx installed (`brew install VitruvianSoftware/tap/devx`)"),
            note: s(""),
            installs: vec![
                install("Any agent", "codex-opencode", "Add the skills to your project (Antigravity, Claude Code, Codex, OpenCode)", "devx agent init"),
            ],
            claude_marketplace_source: s(""),
        },
    ]
}

/// `discover_all(root)`.
pub fn discover_all(root: &PyStr) -> Result<Vec<Ext>, PyErr> {
    let mut discovered: Vec<Ext> = Vec::new();
    for (folder, host) in [
        (ANTIGRAVITY_PLUGINS_DIR, "antigravity"),
        (CLAUDE_CODE_PLUGINS_DIR, "claude-code"),
    ] {
        let dir = pyfs::path_join(root, folder);
        if pyfs::is_dir(&dir)? {
            for (child, name) in pyfs::sorted_children(&dir)? {
                if pyfs::is_dir(&child)? {
                    let mut rel = PyStr::from(folder);
                    rel.push_str("/");
                    rel.push(&name);
                    if let Some(item) = discover_plugin_dir(root, &rel, host)? {
                        discovered.push(item);
                    }
                }
            }
        }
    }

    let keyed: Vec<(i64, Value)> = discovered
        .iter()
        .map(|ext| {
            let order = PREFERRED_PLUGIN_ORDER
                .iter()
                .position(|name| ext.id.eq_str(name))
                .map_or(999, |i| i as i64);
            (order, ext.id.clone())
        })
        .collect();
    let mut indexed: Vec<(usize, &(i64, Value))> = keyed.iter().enumerate().collect();
    py_sort(&mut indexed, |a, b| key_lt(a.1, b.1))?;
    let mut out: Vec<Ext> = indexed
        .iter()
        .map(|(i, _)| discovered[*i].clone())
        .collect();
    out.extend(additional());
    Ok(out)
}

fn scalar(value: &Value) -> PyStr {
    json::dumps(value, false, None)
}

/// `render_extensions_yml(extensions)`.
pub fn render_extensions_yml(extensions: &[Ext]) -> Result<Vec<u8>, PyErr> {
    let mut lines: Vec<PyStr> = Vec::new();
    let lit = |lines: &mut Vec<PyStr>, text: &str| lines.push(PyStr::from(text));
    let field = |lines: &mut Vec<PyStr>, label: &str, value: &Value| {
        let mut line = PyStr::from(label);
        line.push(&scalar(value));
        lines.push(line);
    };
    lit(
        &mut lines,
        "# Written by tools/sync-site-tools from monorepo plugin manifests.",
    );
    lit(&mut lines, "# Do not edit by hand; run:");
    lit(&mut lines, "#   bazel run //tools/sync-site-tools:sync");
    lit(&mut lines, "ecosystems:");
    for eco in ecosystems() {
        for (label, key) in [
            ("  - id: ", "id"),
            ("    title: ", "title"),
            ("    badge: ", "badge"),
            ("    blurb: ", "blurb"),
        ] {
            field(&mut lines, label, eco.subscript(key)?);
        }
        for key in ["bootstrap_label", "bootstrap_command", "feed_url"] {
            if let Some(value) = eco.get(key)? {
                field(&mut lines, &format!("    {}: ", key), value);
            }
        }
    }

    lit(&mut lines, "extension_kinds:");
    for (id, title, blurb) in extension_kinds() {
        field(&mut lines, "  - id: ", &s(id));
        field(&mut lines, "    title: ", &s(title));
        field(&mut lines, "    blurb: ", &s(blurb));
    }

    lit(&mut lines, "extensions:");
    for ext in extensions {
        field(&mut lines, "  - id: ", &ext.id);
        field(&mut lines, "    name: ", &ext.name);
        field(&mut lines, "    kind: ", &ext.kind);
        field(&mut lines, "    category: ", &ext.category);
        field(&mut lines, "    status: ", &ext.status);
        field(&mut lines, "    summary: ", &ext.summary);
        field(&mut lines, "    repo: ", &ext.repo);
        field(&mut lines, "    mirror_repo: ", &ext.mirror_repo);
        field(&mut lines, "    source: ", &ext.source);
        if ext.needs.truthy() {
            field(&mut lines, "    needs: ", &ext.needs);
        }
        if ext.note.truthy() {
            field(&mut lines, "    note: ", &ext.note);
        }
        lit(&mut lines, "    ecosystems:");
        for eco_id in &ext.ecosystems {
            field(&mut lines, "      - ", eco_id);
        }
        if ext.capabilities.is_empty() {
            lit(&mut lines, "    capabilities: []");
        } else {
            lit(&mut lines, "    capabilities:");
            for cap in &ext.capabilities {
                field(&mut lines, "      - ", &Value::Str(cap.clone()));
            }
        }
        lit(&mut lines, "    installs:");
        for inst in &ext.installs {
            let tool = scalar(inst.subscript("tool")?);
            let ecosystem = scalar(inst.subscript("ecosystem")?);
            let label = scalar(inst.subscript("label")?);
            let command = scalar(inst.subscript("command")?);
            for (prefix, value) in [
                ("      - tool: ", tool),
                ("        ecosystem: ", ecosystem),
                ("        label: ", label),
                ("        command: ", command),
            ] {
                let mut line = PyStr::from(prefix);
                line.push(&value);
                lines.push(line);
            }
        }
    }
    let mut text = PyStr::join("\n", &lines);
    text.push_str("\n");
    text.encode_utf8()
}

fn dump_file(payload: &Value) -> Result<Vec<u8>, PyErr> {
    let mut text = json::dumps(payload, false, Some(2));
    text.push_str("\n");
    text.encode_utf8()
}

/// `render_ai_catalog_json(extensions)`.
pub fn render_ai_catalog_json(extensions: &[Ext]) -> Result<Vec<u8>, PyErr> {
    let entries: Vec<Value> = extensions
        .iter()
        .map(|ext| {
            obj(vec![
                ("id", ext.id.clone()),
                ("name", ext.name.clone()),
                ("kind", ext.kind.clone()),
                ("category", ext.category.clone()),
                ("status", ext.status.clone()),
                ("summary", ext.summary.clone()),
                ("repo", ext.repo.clone()),
                ("mirrorRepo", ext.mirror_repo.clone()),
                ("source", ext.source.clone()),
                ("ecosystems", Value::List(ext.ecosystems.clone())),
                ("capabilities", strs(&ext.capabilities)),
                ("skills", strs(&ext.skills)),
                ("hooks", strs(&ext.hooks)),
                ("rules", strs(&ext.rules)),
                ("needs", ext.needs.clone()),
                ("note", ext.note.clone()),
                ("installs", Value::List(ext.installs.clone())),
            ])
        })
        .collect();
    let payload = obj(vec![
        ("$schema", s("https://vitruviansoftware.dev/ai/catalog.schema.json")),
        ("name", s("vitruvian-ai-extensions")),
        ("title", s("Vitruvian Multi-Marketplace Extension Registry")),
        ("description", s("Convention-discovered plugins, MCP servers, portable agent skills, and signed desktop/mobile tools from VitruvianSoftware.")),
        ("homepage", s("https://vitruviansoftware.dev/ai/")),
        ("repository", s("https://github.com/VitruvianSoftware/vitruvian-core")),
        (
            "feeds",
            obj(vec![
                ("unified", s("https://vitruviansoftware.dev/ai/catalog.json")),
                ("claudeCodeMarketplace", s("https://vitruviansoftware.dev/.claude-plugin/marketplace.json")),
                ("vitruvianDesktopTools", s("https://vitruviansoftware.dev/tools/catalog/tools.json")),
                ("vitruvianDesktopSignature", s("https://vitruviansoftware.dev/tools/catalog/tools.json.sig")),
            ]),
        ),
        ("ecosystems", Value::List(ecosystems())),
        ("extensions", Value::List(entries)),
    ]);
    dump_file(&payload)
}

/// `render_claude_marketplace_json(extensions)`.
pub fn render_claude_marketplace_json(extensions: &[Ext]) -> Result<Vec<u8>, PyErr> {
    let author = || {
        obj(vec![
            ("name", s("VitruvianSoftware")),
            ("url", s("https://github.com/VitruvianSoftware")),
        ])
    };
    let plugins: Vec<Value> = extensions
        .iter()
        .filter(|ext| ext.claude_marketplace_source.truthy())
        .map(|ext| {
            obj(vec![
                ("name", ext.id.clone()),
                ("source", ext.claude_marketplace_source.clone()),
                ("description", ext.summary.clone()),
                ("author", author()),
                ("homepage", s("https://vitruviansoftware.dev/ai/")),
                ("repository", ext.mirror_repo.clone()),
                ("license", s("MIT")),
                ("keywords", ext.keywords.clone()),
            ])
        })
        .collect();
    let payload = obj(vec![
        ("$schema", s("https://anthropic.com/claude-code/marketplace.schema.json")),
        ("name", s("vitruvian-core")),
        ("description", s("Vitruvian Software multi-agent plugins, guardrails, FastMCP servers, and workflow skills for Claude Code and Antigravity")),
        ("owner", author()),
        ("plugins", Value::List(plugins)),
    ]);
    dump_file(&payload)
}

/// `outputs(root)`.
pub fn outputs(root: &PyStr) -> Result<Vec<(String, Vec<u8>)>, PyErr> {
    let extensions = discover_all(&pyfs::path_str(root))?;
    let claude = render_claude_marketplace_json(&extensions)?;
    Ok(vec![
        (DATA_YML.to_string(), render_extensions_yml(&extensions)?),
        (
            AI_CATALOG_JSON.to_string(),
            render_ai_catalog_json(&extensions)?,
        ),
        (CLAUDE_MARKETPLACE_ROOT.to_string(), claude.clone()),
        (CLAUDE_MARKETPLACE_WEB.to_string(), claude),
    ])
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    struct TempDir(std::path::PathBuf);

    impl TempDir {
        fn new(tag: &str) -> TempDir {
            let base = std::env::var_os("TEST_TMPDIR")
                .map(std::path::PathBuf::from)
                .unwrap_or_else(std::env::temp_dir);
            let dir = base.join(format!(
                "sync-site-tools-{}-{}-{}",
                tag,
                std::process::id(),
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map_or(0, |d| d.as_nanos())
            ));
            fs::create_dir_all(&dir).unwrap();
            TempDir(dir)
        }

        fn write(&self, rel: &str, text: &str) {
            let path = self.0.join(rel);
            fs::create_dir_all(path.parent().unwrap()).unwrap();
            fs::write(path, text).unwrap();
        }

        fn root(&self) -> PyStr {
            PyStr::from(self.0.to_str().unwrap())
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    /// sync_test.test_registry_ignores_release_please_version_bumps.
    #[test]
    fn a_version_bump_changes_nothing() {
        let tmp = TempDir::new("bump");
        let rel = "apps/desktop/antigravity/plugins/sample-ext";
        tmp.write(&format!("{}/skills/sample-ext/SKILL.md", rel), "# skill\n");
        tmp.write(
            &format!("{}/.claude-plugin/plugin.json", rel),
            r#"{"name": "sample-ext", "description": "Sample"}"#,
        );
        tmp.write(
            &format!("{}/plugin.json", rel),
            r#"{"name": "sample-ext", "version": "0.1.0", "description": "Sample"}"#,
        );
        let before = discover_plugin_dir(&tmp.root(), &PyStr::from(rel), "antigravity")
            .unwrap()
            .unwrap();
        tmp.write(
            &format!("{}/plugin.json", rel),
            r#"{"name": "sample-ext", "version": "0.2.0", "description": "Sample"}"#,
        );
        let after = discover_plugin_dir(&tmp.root(), &PyStr::from(rel), "antigravity")
            .unwrap()
            .unwrap();
        assert_eq!(format!("{:?}", before), format!("{:?}", after));
        assert_eq!(after.capabilities, vec![PyStr::from("1 Skill")]);
        assert!(after.installs.len() == 3);
        let commands: Vec<String> = after
            .installs
            .iter()
            .map(|inst| {
                inst.subscript("command")
                    .unwrap()
                    .py_str()
                    .to_string_lossy()
            })
            .collect();
        assert_eq!(
            commands,
            vec![
                "agy plugin install https://github.com/VitruvianSoftware/sample-ext",
                "claude plugin install sample-ext",
                "cp -R apps/desktop/antigravity/plugins/sample-ext/skills/* ~/.agents/skills/",
            ]
        );
    }

    #[test]
    fn plugins_sort_by_preferred_order_then_id() {
        let tmp = TempDir::new("order");
        for name in ["zeta", "gh-watch", "alpha", "ext-marketplace"] {
            tmp.write(
                &format!("apps/desktop/antigravity/plugins/{}/plugin.json", name),
                &format!(r#"{{"name": "{}"}}"#, name),
            );
        }
        let ids: Vec<String> = discover_all(&tmp.root())
            .unwrap()
            .iter()
            .map(|ext| ext.id.py_str().to_string_lossy())
            .collect();
        assert_eq!(
            ids,
            vec![
                "ext-marketplace",
                "gh-watch",
                "alpha",
                "zeta",
                "mcp-roborock",
                "nexus-agent",
                "mcp-slack",
                "devx"
            ]
        );
    }

    #[test]
    fn mixed_ids_fail_to_sort_as_python() {
        let tmp = TempDir::new("mixed");
        tmp.write(
            "apps/desktop/antigravity/plugins/a/plugin.json",
            r#"{"name": "zzz"}"#,
        );
        tmp.write(
            "apps/desktop/antigravity/plugins/b/plugin.json",
            r#"{"name": 5}"#,
        );
        assert_eq!(
            discover_all(&tmp.root()).unwrap_err().last_line(),
            "TypeError: '<' not supported between instances of 'int' and 'str'"
        );
    }

    #[test]
    fn py_sort_matches_a_stable_sort() {
        let mut items: Vec<i64> = vec![5, 3, 9, 1, 3, 7, 2, 8, 8, 0];
        py_sort(&mut items, |a, b| Ok(a < b)).unwrap();
        assert_eq!(items, vec![0, 1, 2, 3, 3, 5, 7, 8, 8, 9]);
        let mut desc: Vec<i64> = vec![9, 8, 7, 1, 2];
        py_sort(&mut desc, |a, b| Ok(a < b)).unwrap();
        assert_eq!(desc, vec![1, 2, 7, 8, 9]);
    }
}
