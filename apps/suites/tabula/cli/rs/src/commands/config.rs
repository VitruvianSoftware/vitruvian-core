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

use std::path::Path;

use crate::utils::config::{get_config_from, save_config_to, Config};

pub fn format_ascii_table(rows: &[Vec<String>]) -> String {
    if rows.is_empty() {
        return String::new();
    }
    let cols = rows.iter().map(|r| r.len()).max().unwrap_or(0);
    let mut widths = vec![0usize; cols];
    for row in rows {
        for (c, cell) in row.iter().enumerate() {
            if cell.len() > widths[c] {
                widths[c] = cell.len();
            }
        }
    }

    let mut out = String::new();
    let border = {
        let mut s = String::from("+");
        for w in &widths {
            s.push_str(&"-".repeat(w + 2));
            s.push('+');
        }
        s
    };

    out.push_str(&border);
    out.push('\n');
    for row in rows {
        out.push('|');
        for (c, w) in widths.iter().enumerate() {
            let val = row.get(c).map(String::as_str).unwrap_or("");
            out.push(' ');
            out.push_str(val);
            out.push_str(&" ".repeat(w.saturating_sub(val.len()) + 1));
            out.push('|');
        }
        out.push('\n');
        out.push_str(&border);
        out.push('\n');
    }
    out
}

pub fn format_config_list(config: &Config) -> String {
    let db_status = if config
        .database_url
        .as_ref()
        .map(|s| !s.is_empty())
        .unwrap_or(false)
    {
        "(set)"
    } else {
        "(not set)"
    };
    let rows = vec![
        vec!["Key".to_string(), "Value".to_string()],
        vec!["Project ID".to_string(), config.project_id.clone()],
        vec![
            "Environment".to_string(),
            config.environment.clone().unwrap_or_default(),
        ],
        vec!["Region".to_string(), config.region.clone()],
        vec!["Database URL".to_string(), db_status.to_string()],
        vec![
            "Created At".to_string(),
            config.created_at.clone().unwrap_or_default(),
        ],
    ];
    format!("\n{}", format_ascii_table(&rows))
}

pub fn run_config_command_at(base_dir: &Path, args: &[String]) -> Result<String, String> {
    if args.is_empty() || args[0] == "--help" || args[0] == "-h" {
        return Ok(
            "Usage: tabcli config <command>\n\nManage TabCLI configuration\n\nCommands:\n  list|ls            List all configuration values\n  set <key> <value>  Set a configuration value\n  get <key>          Get a configuration value\n  unset <key>        Unset a configuration value"
                .to_string(),
        );
    }

    match args[0].as_str() {
        "list" | "ls" => {
            let config = get_config_from(base_dir)?;
            Ok(format_config_list(&config))
        }
        "set" => {
            if args.len() < 3 {
                return Err("Usage: tabcli config set <key> <value>".to_string());
            }
            let key = &args[1];
            let value = &args[2];
            let mut config = get_config_from(base_dir)?;
            config.set_value(key, value.clone())?;
            save_config_to(base_dir, &config)?;
            Ok(format!("✓ Set {key} = {value}"))
        }
        "get" => {
            if args.len() < 2 {
                return Err("Usage: tabcli config get <key>".to_string());
            }
            let key = &args[1];
            let config = get_config_from(base_dir)?;
            if !config.has_key(key) {
                return Err(format!("Key not found: {key}"));
            }
            Ok(config.get_value(key).unwrap_or("").to_string())
        }
        "unset" => {
            if args.len() < 2 {
                return Err("Usage: tabcli config unset <key>".to_string());
            }
            let key = &args[1];
            let mut config = get_config_from(base_dir)?;
            config.unset_value(key)?;
            save_config_to(base_dir, &config)?;
            Ok(format!("✓ Unset {key}"))
        }
        other => Err(format!("Unknown config subcommand: {other}")),
    }
}

pub fn run_config_command(args: &[String]) -> Result<String, String> {
    let cwd = std::env::current_dir().map_err(|e| e.to_string())?;
    run_config_command_at(&cwd, args)
}
