// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

use std::fs;
use std::process::Command;

fn extract_protocol_version(json_path: &str) -> Option<String> {
    let content = fs::read_to_string(json_path).ok()?;
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("\"protocol\":") || trimmed.starts_with("\"protocol\" :") {
            // Match:   "protocol": N,
            if let Some(rest) = line.strip_prefix("  \"protocol\": ") {
                let rest = rest.trim_end_matches(',').trim();
                if rest.chars().all(|c| c.is_ascii_digit()) && !rest.is_empty() {
                    return Some(rest.to_string());
                }
            }
        }
    }
    None
}

fn extract_swift_protocol_version(swift_path: &str) -> Option<String> {
    let content = fs::read_to_string(swift_path).ok()?;
    for line in content.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("public static let version = ") {
            let rest = rest.trim();
            if rest.chars().all(|c| c.is_ascii_digit()) && !rest.is_empty() {
                return Some(rest.to_string());
            }
        }
    }
    None
}

pub fn run(args: &[String]) -> i32 {
    if args.len() < 4 {
        eprintln!("Usage: engine-contract <courier-engine> <EngineSupervisor.swift> <Protocol.swift> <protocol files>...");
        return 2;
    }

    let engine = &args[1];
    let supervisor = &args[2];
    let swift_protocol = &args[3];

    let mut protocol_json = None;
    for path in &args[4..] {
        if path.ends_with("/protocol.json") || path == "protocol.json" {
            protocol_json = Some(path.as_str());
        }
    }

    let protocol_json = match protocol_json {
        Some(p) => p,
        None => {
            eprintln!("FAIL: no protocol.json among: {}", args[4..].join(" "));
            return 2;
        }
    };

    let mut failed = 0;

    // Check supervisor source for expected arguments
    let supervisor_content = match fs::read_to_string(supervisor) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("FAIL: cannot read {}: {}", supervisor, e);
            return 1;
        }
    };

    if supervisor_content.contains("\"--data\", dataDir.path, \"--parent-fd\", \"0\"") {
        println!("ok: the supervisor starts the engine with --data DIR --parent-fd 0");
    } else {
        eprintln!("FAIL: EngineSupervisor.swift no longer passes --data DIR --parent-fd 0; update this test with it");
        failed = 1;
    }

    // Run engine --help
    let output = Command::new(engine).arg("--help").output();

    match output {
        Ok(out) => {
            let status = out.status.code().unwrap_or(-1);
            let combined = format!(
                "{}{}",
                String::from_utf8_lossy(&out.stdout),
                String::from_utf8_lossy(&out.stderr)
            );
            if status == 2 && combined.contains("--data DIR") && combined.contains("--parent-fd N")
            {
                println!("ok: the engine takes --data DIR and --parent-fd N");
            } else {
                eprintln!(
                    "FAIL: the engine's usage (exit {}) does not name --data DIR and --parent-fd N: {}",
                    status, combined.trim()
                );
                failed = 1;
            }
        }
        Err(e) => {
            eprintln!("FAIL: cannot run {}: {}", engine, e);
            failed = 1;
        }
    }

    // Protocol version check
    let want = extract_protocol_version(protocol_json);
    let got = extract_swift_protocol_version(swift_protocol);

    match (&want, &got) {
        (Some(w), Some(g)) if w == g => {
            println!(
                "ok: Protocol.swift speaks protocol {}, as protocol.json says",
                g
            );
        }
        _ => {
            eprintln!(
                "FAIL: Protocol.swift speaks protocol '{}', protocol.json says '{}'",
                got.as_deref().unwrap_or(""),
                want.as_deref().unwrap_or("")
            );
            failed = 1;
        }
    }

    failed
}
