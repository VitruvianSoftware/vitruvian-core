// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

pub struct Config {
    pub template: PathBuf,
    pub version_env: PathBuf,
    pub output: PathBuf,
}

pub fn parse_args(args: &[String]) -> Result<Config, String> {
    let mut template = None;
    let mut version_env = None;
    let mut output = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--template" => {
                i += 1;
                if i >= args.len() {
                    return Err("--template requires a value".into());
                }
                template = Some(PathBuf::from(&args[i]));
            }
            "--version-env" => {
                i += 1;
                if i >= args.len() {
                    return Err("--version-env requires a value".into());
                }
                version_env = Some(PathBuf::from(&args[i]));
            }
            "--output" => {
                i += 1;
                if i >= args.len() {
                    return Err("--output requires a value".into());
                }
                output = Some(PathBuf::from(&args[i]));
            }
            "-h" | "--help" => {
                return Err(
                    "Usage: bundle_info_plist --template <path> --version-env <path> --output <path>"
                        .into(),
                );
            }
            other => return Err(format!("unknown argument: {}", other)),
        }
        i += 1;
    }
    Ok(Config {
        template: template.ok_or("missing --template")?,
        version_env: version_env.ok_or("missing --version-env")?,
        output: output.ok_or("missing --output")?,
    })
}

pub fn load_version_env(path: &Path) -> Result<BTreeMap<String, String>, String> {
    let content =
        fs::read_to_string(path).map_err(|e| format!("read {}: {}", path.display(), e))?;
    Ok(parse_version_env(&content))
}

pub fn parse_version_env(content: &str) -> BTreeMap<String, String> {
    let mut values = BTreeMap::new();
    for raw in content.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some((key, value)) = line.split_once('=') {
            let k = key.trim().to_string();
            let v = value
                .trim()
                .trim_matches(|c| c == '"' || c == '\'')
                .to_string();
            values.insert(k, v);
        }
    }
    values
}

pub fn render_info_plist(
    raw_template: &str,
    env_values: &BTreeMap<String, String>,
) -> Result<String, String> {
    let marketing = env_values
        .get("VITRUVIAN_MARKETING_VERSION")
        .ok_or("missing VITRUVIAN_MARKETING_VERSION in version.env")?;
    let build = env_values
        .get("VITRUVIAN_BUILD_NUMBER")
        .ok_or("missing VITRUVIAN_BUILD_NUMBER in version.env")?;

    let substituted = raw_template
        .replace("${VITRUVIAN_MARKETING_VERSION}", marketing)
        .replace("${VITRUVIAN_BUILD_NUMBER}", build);

    Ok(strip_key_from_plist(
        &substituted,
        "SMPrivilegedExecutables",
    ))
}

pub fn strip_key_from_plist(xml: &str, key_name: &str) -> String {
    let needle = format!("<key>{}</key>", key_name);
    let mut out = Vec::new();
    let lines: Vec<&str> = xml.lines().collect();
    let mut i = 0;
    while i < lines.len() {
        if lines[i].trim() == needle {
            i += 1;
            // Skip following value element (<dict>...</dict>, <string>...</string>, <true/>, etc.)
            let mut depth = 0i32;
            while i < lines.len() {
                let t = lines[i].trim();
                if t.starts_with("<dict>") || t.starts_with("<array>") {
                    depth += 1;
                }
                if t.ends_with("</dict>") || t.ends_with("</array>") {
                    depth -= 1;
                    if depth <= 0 {
                        i += 1;
                        break;
                    }
                } else if depth == 0 && !t.is_empty() {
                    i += 1;
                    break;
                }
                i += 1;
            }
            continue;
        }
        out.push(lines[i]);
        i += 1;
    }
    let mut result = out.join("\n");
    if xml.ends_with('\n') {
        result.push('\n');
    }
    result
}

pub fn run(config: &Config) -> Result<(), String> {
    let env_values = load_version_env(&config.version_env)?;
    let raw = fs::read_to_string(&config.template)
        .map_err(|e| format!("read {}: {}", config.template.display(), e))?;
    let rendered = render_info_plist(&raw, &env_values)?;
    if let Some(parent) = config.output.parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent).map_err(|e| format!("mkdir: {}", e))?;
        }
    }
    fs::write(&config.output, rendered)
        .map_err(|e| format!("write {}: {}", config.output.display(), e))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_version_env() {
        let env_text =
            "# Comment\nVITRUVIAN_MARKETING_VERSION=\"3.85.0\"\nVITRUVIAN_BUILD_NUMBER='96'\n";
        let map = parse_version_env(env_text);
        assert_eq!(map.get("VITRUVIAN_MARKETING_VERSION").unwrap(), "3.85.0");
        assert_eq!(map.get("VITRUVIAN_BUILD_NUMBER").unwrap(), "96");
    }

    #[test]
    fn test_render_substitutes_and_strips_privileged_executables() {
        let tpl = "\
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<plist version=\"1.0\">
<dict>
\t<key>CFBundleShortVersionString</key>
\t<string>${VITRUVIAN_MARKETING_VERSION}</string>
\t<key>CFBundleVersion</key>
\t<string>${VITRUVIAN_BUILD_NUMBER}</string>
\t<key>SMPrivilegedExecutables</key>
\t<dict>
\t\t<key>com.example.helper</key>
\t\t<string>identifier \"com.example.helper\"</string>
\t</dict>
\t<key>LSUIElement</key>
\t<true/>
</dict>
</plist>
";
        let map =
            parse_version_env("VITRUVIAN_MARKETING_VERSION=3.85.0\nVITRUVIAN_BUILD_NUMBER=96\n");
        let out = render_info_plist(tpl, &map).unwrap();
        assert!(out.contains("<string>3.85.0</string>"));
        assert!(out.contains("<string>96</string>"));
        assert!(!out.contains("SMPrivilegedExecutables"));
        assert!(!out.contains("com.example.helper"));
        assert!(out.contains("<key>LSUIElement</key>"));
    }

    #[test]
    fn test_parse_args() {
        let args = vec![
            "--template".to_string(),
            "a.plist".to_string(),
            "--version-env".to_string(),
            "v.env".to_string(),
            "--output".to_string(),
            "out.plist".to_string(),
        ];
        let cfg = parse_args(&args).unwrap();
        assert_eq!(cfg.template, PathBuf::from("a.plist"));
        assert_eq!(cfg.version_env, PathBuf::from("v.env"));
        assert_eq!(cfg.output, PathBuf::from("out.plist"));
    }
}
