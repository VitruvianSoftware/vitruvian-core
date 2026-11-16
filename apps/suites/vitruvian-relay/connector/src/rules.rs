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

//! The local rules: which `desktop-commander` tools the relay may see, which
//! run without asking, and which ask first. The file lives on this Mac, is
//! read at start and on `SIGHUP`, and nothing received from the relay can
//! change it. The default is to ask: a tool runs silently only if it is named
//! in `no_prompt`.

use std::path::{Path, PathBuf};

use serde::Deserialize;
use vitruvian_relay_protocol::ToolDef;

use crate::state::write_private;
use crate::Result;

pub const DEFAULT_RULES: &str = r#"paused = false
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
}

pub fn rules_path(dir: &Path) -> PathBuf {
    dir.join("rules.toml")
}

/// Reads `rules.toml`, writing the defaults first if there is none.
///
/// A file that does not parse, or lacks `hidden` or `no_prompt`, is an error,
/// never a silent fall back to defaults: the caller decides (refuse to start;
/// on a reload, keep the rules it already has).
pub fn load(dir: &Path) -> Result<Rules> {
    let path = rules_path(dir);
    if !path.exists() {
        write_private(&path, DEFAULT_RULES.as_bytes())?;
    }
    let text =
        std::fs::read_to_string(&path).map_err(|e| format!("read {}: {e}", path.display()))?;
    toml::from_str(&text).map_err(|e| format!("{}: {e}", path.display()))
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
    let rules = load(dir)?;
    let visible_changed = rules.visible(tools) != current.visible(tools);
    Ok(Reloaded {
        rules,
        visible_changed,
    })
}

impl Rules {
    /// Never shown and never callable: named in `hidden`, or any other tool
    /// whose name contains "config" unless `config_allow` names it. The
    /// explicit list wins over `config_allow`.
    pub fn is_hidden(&self, tool: &str) -> bool {
        if self.hidden.iter().any(|h| h == tool) {
            return true;
        }
        tool.to_ascii_lowercase().contains("config") && !self.config_allow.iter().any(|a| a == tool)
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
    /// `no_prompt`; everything else, including a tool nobody has heard of,
    /// asks first.
    pub fn decide(&self, tool: &str) -> Decision {
        if self.paused {
            return Decision::Refuse("paused on this Mac");
        }
        if self.is_hidden(tool) {
            return Decision::Refuse("this tool is not available remotely");
        }
        if self.no_prompt.iter().any(|t| t == tool) {
            Decision::Run
        } else {
            Decision::AskFirst
        }
    }
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
            assert_eq!(r.decide(t), Decision::Run, "{t}");
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
            assert_eq!(r.decide(t), Decision::AskFirst, "{t}");
        }
    }

    #[test]
    fn unknown_tool_asks_first() {
        let r = defaults();
        assert_eq!(r.decide("brand_new_tool"), Decision::AskFirst);
        assert_eq!(r.decide(""), Decision::AskFirst);
        // Close to a read tool but not it: still asks.
        assert_eq!(r.decide("read_file2"), Decision::AskFirst);
        assert_eq!(r.decide("Read_File"), Decision::AskFirst);
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
        assert!(matches!(r.decide("set_config_value"), Decision::Refuse(_)));
        assert!(matches!(r.decide("get_config"), Decision::Refuse(_)));
        // Hidden wins even if the same tool is also listed as no_prompt.
        let mut r2 = r.clone();
        r2.no_prompt.push("get_config".into());
        assert!(matches!(r2.decide("get_config"), Decision::Refuse(_)));
    }

    #[test]
    fn paused_refuses_everything() {
        let mut r = defaults();
        r.paused = true;
        for t in ["read_file", "start_process", "brand_new_tool", "get_config"] {
            assert!(matches!(r.decide(t), Decision::Refuse(_)), "{t}");
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
            assert!(matches!(r.decide(t), Decision::Refuse(_)), "{t}");
            // Even listed as no_prompt, a config tool stays hidden.
            r.no_prompt.push(t.into());
            assert!(matches!(r.decide(t), Decision::Refuse(_)), "{t}");
        }
        // config_allow opens one tool; it then asks first (not in no_prompt).
        r.config_allow.push("update_config".into());
        r.no_prompt.retain(|t| t != "update_config");
        assert!(!r.is_hidden("update_config"));
        assert_eq!(r.decide("update_config"), Decision::AskFirst);
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
        assert_eq!(r.rules.decide("start_process"), Decision::Run);
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
}
