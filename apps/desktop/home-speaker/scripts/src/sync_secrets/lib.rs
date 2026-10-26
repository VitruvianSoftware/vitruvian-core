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

use std::collections::HashMap;
use std::fs;
use std::io::Write;
use std::path::Path;

const REQUIRED_KEYS: &[&str] = &[
    "GOOGLE_OAUTH_CLIENT_ID",
    "GOOGLE_OAUTH_CLIENT_SECRET",
    "CAST_CERT_P12_BASE64",
    "CAST_CERT_PASSWORD",
];

const OPTIONAL_KEYS: &[&str] = &["GOOGLE_ENTERPRISE_PROJECT_ID"];

const USAGE: &str = "\
Usage: sync-secrets [--out <path>] (--from-env | --env-file <path>) [-h|--help]

Reads secrets and generates GeneratedSecrets.swift.

Options:
  --out <path>       Output file path (default: <workspace>/apps/desktop/home-speaker/Sources/HomeSpeakerCore/GeneratedSecrets.swift)
  --from-env         Read secrets from environment variables
  --env-file <path>  Read secrets from a dotenv-style file
  -h, --help         Show this help message";

#[derive(Debug)]
enum Source {
    Env,
    EnvFile(String),
}

#[derive(Debug)]
struct Config {
    out_path: Option<String>,
    source: Source,
}

fn parse_args(args: &[String]) -> Result<Config, String> {
    let mut out_path: Option<String> = None;
    let mut from_env = false;
    let mut env_file: Option<String> = None;
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "-h" | "--help" => return Err("__HELP__".to_string()),
            "--out" => {
                i += 1;
                if i >= args.len() {
                    return Err("error: --out requires a value".to_string());
                }
                out_path = Some(args[i].clone());
            }
            "--from-env" => {
                from_env = true;
            }
            "--env-file" => {
                i += 1;
                if i >= args.len() {
                    return Err("error: --env-file requires a value".to_string());
                }
                env_file = Some(args[i].clone());
            }
            other => {
                return Err(format!("error: unknown flag: {other}"));
            }
        }
        i += 1;
    }
    if from_env && env_file.is_some() {
        return Err("error: --from-env and --env-file are mutually exclusive".to_string());
    }
    if !from_env && env_file.is_none() {
        return Err("error: one of --from-env or --env-file is required".to_string());
    }
    let source = if from_env {
        Source::Env
    } else {
        Source::EnvFile(env_file.unwrap())
    };
    Ok(Config { out_path, source })
}

pub fn read_env_file(path: &Path) -> Result<HashMap<String, String>, String> {
    let content = fs::read_to_string(path)
        .map_err(|e| format!("error: cannot read {}: {e}", path.display()))?;
    let mut map = HashMap::new();
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        if let Some(pos) = trimmed.find('=') {
            let key = trimmed[..pos].trim().to_string();
            let mut val = trimmed[pos + 1..].trim().to_string();
            if val.len() >= 2 {
                let first = val.as_bytes()[0];
                let last = val.as_bytes()[val.len() - 1];
                if (first == b'"' && last == b'"') || (first == b'\'' && last == b'\'') {
                    val = val[1..val.len() - 1].to_string();
                }
            }
            map.insert(key, val);
        }
    }
    Ok(map)
}

pub fn read_from_env(keys: &[&str]) -> HashMap<String, String> {
    let mut map = HashMap::new();
    for &key in keys {
        if let Ok(val) = std::env::var(key) {
            map.insert(key.to_string(), val);
        }
    }
    map
}

pub fn validate_keys(values: &HashMap<String, String>) -> Result<(), Vec<String>> {
    let mut missing = Vec::new();
    for &key in REQUIRED_KEYS {
        match values.get(key) {
            Some(v) if !v.is_empty() => {}
            _ => missing.push(key.to_string()),
        }
    }
    if missing.is_empty() {
        Ok(())
    } else {
        Err(missing)
    }
}

pub fn escape_swift_string(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            _ => out.push(c),
        }
    }
    out
}

pub fn to_lower_camel_case(s: &str) -> String {
    let parts: Vec<&str> = s.split('_').filter(|p| !p.is_empty()).collect();
    let mut result = String::new();
    for (i, part) in parts.iter().enumerate() {
        if i == 0 {
            result.push_str(&part.to_ascii_lowercase());
        } else {
            let mut chars = part.chars();
            if let Some(first) = chars.next() {
                result.push(first.to_ascii_uppercase());
                for c in chars {
                    result.push(c.to_ascii_lowercase());
                }
            }
        }
    }
    result
}

pub fn render_swift(values: &HashMap<String, String>) -> String {
    let all_keys: Vec<&str> = REQUIRED_KEYS
        .iter()
        .chain(OPTIONAL_KEYS.iter())
        .copied()
        .collect();
    let mut lines = Vec::new();
    lines.push("// Generated by sync-secrets \u{2014} do not edit.".to_string());
    lines.push("import Foundation".to_string());
    lines.push(String::new());
    lines.push("enum GeneratedSecrets {".to_string());
    for key in &all_keys {
        let prop = to_lower_camel_case(key);
        let raw_val = values.get(*key).map(|s| s.as_str()).unwrap_or("");
        let escaped = escape_swift_string(raw_val);
        lines.push(format!("    static let {prop} = \"{escaped}\""));
    }
    lines.push("}".to_string());
    let mut out = lines.join("\n");
    out.push('\n');
    out
}

fn resolve_out_path(config: &Config) -> Result<String, String> {
    if let Some(ref p) = config.out_path {
        return Ok(p.clone());
    }
    let ws = std::env::var("BUILD_WORKSPACE_DIRECTORY").map_err(|_| {
        "error: BUILD_WORKSPACE_DIRECTORY not set and --out not provided".to_string()
    })?;
    Ok(format!(
        "{ws}/apps/desktop/home-speaker/Sources/HomeSpeakerCore/GeneratedSecrets.swift"
    ))
}

pub fn run(args: &[String]) -> i32 {
    let config = match parse_args(args) {
        Ok(c) => c,
        Err(e) if e == "__HELP__" => {
            println!("{USAGE}");
            return 0;
        }
        Err(e) => {
            eprintln!("{e}");
            return 1;
        }
    };

    let out_path = match resolve_out_path(&config) {
        Ok(p) => p,
        Err(e) => {
            eprintln!("{e}");
            return 1;
        }
    };

    let all_keys: Vec<&str> = REQUIRED_KEYS
        .iter()
        .chain(OPTIONAL_KEYS.iter())
        .copied()
        .collect();

    let (values, source_label) = match &config.source {
        Source::Env => (read_from_env(&all_keys), "environment".to_string()),
        Source::EnvFile(path) => {
            let p = Path::new(path);
            match read_env_file(p) {
                Ok(v) => (v, path.clone()),
                Err(e) => {
                    eprintln!("{e}");
                    return 1;
                }
            }
        }
    };

    if let Err(missing) = validate_keys(&values) {
        for key in &missing {
            eprintln!("error: missing required key: {key}");
        }
        return 1;
    }

    let swift = render_swift(&values);

    let out = Path::new(&out_path);
    if let Some(parent) = out.parent() {
        if !parent.exists() {
            if let Err(e) = fs::create_dir_all(parent) {
                eprintln!("error: cannot create directory {}: {e}", parent.display());
                return 1;
            }
        }
    }

    let result = (|| -> Result<(), String> {
        let mut f = fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .open(out)
            .map_err(|e| format!("error: cannot write {}: {e}", out.display()))?;
        f.write_all(swift.as_bytes())
            .map_err(|e| format!("error: write failed: {e}"))?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(out, fs::Permissions::from_mode(0o600))
                .map_err(|e| format!("error: cannot set permissions: {e}"))?;
        }
        Ok(())
    })();

    if let Err(e) = result {
        eprintln!("{e}");
        return 1;
    }

    println!("Synced HomeSpeaker secrets -> {out_path} (source: {source_label})");
    0
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    #[cfg(unix)]
    use std::os::unix::fs::PermissionsExt;

    fn temp_dir(name: &str) -> std::path::PathBuf {
        let p = std::env::temp_dir().join(format!("hs_sync_test_{name}_{}", std::process::id()));
        let _ = fs::remove_dir_all(&p);
        fs::create_dir_all(&p).unwrap();
        p
    }

    fn write_env_file(dir: &Path, content: &str) -> std::path::PathBuf {
        let p = dir.join(".env");
        fs::write(&p, content).unwrap();
        p
    }

    #[test]
    fn from_env() {
        let dir = temp_dir("from_env");
        let out = dir.join("GeneratedSecrets.swift");
        std::env::set_var("GOOGLE_OAUTH_CLIENT_ID", "cid-test");
        std::env::set_var("GOOGLE_OAUTH_CLIENT_SECRET", "csec-test");
        std::env::set_var("CAST_CERT_P12_BASE64", "p12-test");
        std::env::set_var("CAST_CERT_PASSWORD", "pw-test");
        std::env::set_var("GOOGLE_ENTERPRISE_PROJECT_ID", "proj-test");
        let args: Vec<String> = vec![
            "prog".into(),
            "--from-env".into(),
            "--out".into(),
            out.to_str().unwrap().into(),
        ];
        let rc = run(&args);
        assert_eq!(rc, 0, "run should succeed");
        assert!(out.exists(), "output file should exist");
        let content = fs::read_to_string(&out).unwrap();
        assert!(content.contains("\"cid-test\""), "should contain client id");
        assert!(
            content.contains("\"csec-test\""),
            "should contain client secret"
        );
        assert!(
            content.contains("\"p12-test\""),
            "should contain p12 base64"
        );
        assert!(content.contains("\"pw-test\""), "should contain password");
        assert!(
            content.contains("\"proj-test\""),
            "should contain project id"
        );
        #[cfg(unix)]
        {
            let mode = fs::metadata(&out).unwrap().permissions().mode() & 0o777;
            assert_eq!(mode, 0o600, "should be 0600");
        }
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn optional_key_omission() {
        let dir = temp_dir("opt_omit");
        let out = dir.join("GeneratedSecrets.swift");
        std::env::set_var("GOOGLE_OAUTH_CLIENT_ID", "cid2");
        std::env::set_var("GOOGLE_OAUTH_CLIENT_SECRET", "csec2");
        std::env::set_var("CAST_CERT_P12_BASE64", "p122");
        std::env::set_var("CAST_CERT_PASSWORD", "pw2");
        std::env::remove_var("GOOGLE_ENTERPRISE_PROJECT_ID");
        let args: Vec<String> = vec![
            "prog".into(),
            "--from-env".into(),
            "--out".into(),
            out.to_str().unwrap().into(),
        ];
        let rc = run(&args);
        assert_eq!(rc, 0);
        let content = fs::read_to_string(&out).unwrap();
        assert!(
            content.contains("static let googleEnterpriseProjectId = \"\""),
            "optional key should be empty string, got:\n{content}",
        );
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn env_file_with_quotes_comments_blanks() {
        let dir = temp_dir("envfile");
        let env_content = r#"
# This is a comment
GOOGLE_OAUTH_CLIENT_ID="double-quoted"
GOOGLE_OAUTH_CLIENT_SECRET='single-quoted'
CAST_CERT_P12_BASE64=unquoted

CAST_CERT_PASSWORD="pw-val"
GOOGLE_ENTERPRISE_PROJECT_ID='proj-val'
"#;
        let env_path = write_env_file(&dir, env_content);
        let out = dir.join("out.swift");
        let args: Vec<String> = vec![
            "prog".into(),
            "--env-file".into(),
            env_path.to_str().unwrap().into(),
            "--out".into(),
            out.to_str().unwrap().into(),
        ];
        let rc = run(&args);
        assert_eq!(rc, 0, "should succeed");
        let content = fs::read_to_string(&out).unwrap();
        assert!(content.contains("\"double-quoted\""), "double-quoted value");
        assert!(content.contains("\"single-quoted\""), "single-quoted value");
        assert!(content.contains("\"unquoted\""), "unquoted value");
        assert!(content.contains("\"pw-val\""), "password value");
        assert!(content.contains("\"proj-val\""), "project id value");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn missing_required_keys() {
        let dir = temp_dir("missing_req");
        let env_content = "GOOGLE_OAUTH_CLIENT_ID=only-one\n";
        let env_path = write_env_file(&dir, env_content);
        let out = dir.join("out.swift");
        let args: Vec<String> = vec![
            "prog".into(),
            "--env-file".into(),
            env_path.to_str().unwrap().into(),
            "--out".into(),
            out.to_str().unwrap().into(),
        ];
        let rc = run(&args);
        assert_ne!(rc, 0, "should fail with missing required keys");
        assert!(!out.exists(), "should not create output on failure");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn missing_env_file() {
        let args: Vec<String> = vec![
            "prog".into(),
            "--env-file".into(),
            "/tmp/nonexistent_hs_sync_test_file_xyz".into(),
            "--out".into(),
            "/tmp/should_not_exist.swift".into(),
        ];
        let rc = run(&args);
        assert_ne!(rc, 0, "should fail for missing env file");
    }

    #[test]
    fn swift_string_escaping() {
        assert_eq!(escape_swift_string(r#"a\b"c"#), r#"a\\b\"c"#);

        let dir = temp_dir("escape");
        let env_content = "GOOGLE_OAUTH_CLIENT_ID=has\\\\slash\nGOOGLE_OAUTH_CLIENT_SECRET=has\\\"quote\nCAST_CERT_P12_BASE64=normal\nCAST_CERT_PASSWORD=also\\\\normal\n";
        let env_path = write_env_file(&dir, env_content);
        let out = dir.join("out.swift");
        let args: Vec<String> = vec![
            "prog".into(),
            "--env-file".into(),
            env_path.to_str().unwrap().into(),
            "--out".into(),
            out.to_str().unwrap().into(),
        ];
        let rc = run(&args);
        assert_eq!(rc, 0);
        let content = fs::read_to_string(&out).unwrap();
        assert!(
            content.contains(r#"\\\\slash"#),
            "backslashes should be escaped in Swift output, got:\n{content}"
        );
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn unknown_flag() {
        let rc = parse_args(&["prog".to_string(), "--bogus".to_string()]);
        assert!(rc.is_err());
        let e = rc.unwrap_err();
        assert!(
            e.contains("unknown flag"),
            "error should mention unknown flag: {e}"
        );
    }

    #[test]
    fn out_without_value() {
        let rc = parse_args(&["prog".to_string(), "--out".to_string()]);
        assert!(rc.is_err());
        let e = rc.unwrap_err();
        assert!(e.contains("--out"), "error should mention --out: {e}");
    }

    #[test]
    fn help_flag() {
        let rc = parse_args(&["prog".to_string(), "--help".to_string()]);
        assert!(rc.is_err());
        assert_eq!(rc.unwrap_err(), "__HELP__");
    }

    #[test]
    fn to_lower_camel_case_conversion() {
        assert_eq!(
            to_lower_camel_case("GOOGLE_OAUTH_CLIENT_ID"),
            "googleOauthClientId"
        );
        assert_eq!(
            to_lower_camel_case("CAST_CERT_P12_BASE64"),
            "castCertP12Base64"
        );
        assert_eq!(
            to_lower_camel_case("CAST_CERT_PASSWORD"),
            "castCertPassword"
        );
    }

    #[test]
    fn render_swift_output_structure() {
        let mut vals = HashMap::new();
        vals.insert("GOOGLE_OAUTH_CLIENT_ID".to_string(), "cid".to_string());
        vals.insert("GOOGLE_OAUTH_CLIENT_SECRET".to_string(), "cs".to_string());
        vals.insert("CAST_CERT_P12_BASE64".to_string(), "p12".to_string());
        vals.insert("CAST_CERT_PASSWORD".to_string(), "pw".to_string());
        vals.insert(
            "GOOGLE_ENTERPRISE_PROJECT_ID".to_string(),
            "proj".to_string(),
        );
        let out = render_swift(&vals);
        assert!(out.starts_with("// Generated by sync-secrets"));
        assert!(out.contains("import Foundation"));
        assert!(out.contains("enum GeneratedSecrets {"));
        assert!(
            out.contains("static let googleOauthClientId = \"cid\""),
            "got:\n{out}"
        );
        assert!(
            out.contains("static let castCertPassword = \"pw\""),
            "got:\n{out}"
        );
        assert!(out.ends_with("}\n"));
    }
}
