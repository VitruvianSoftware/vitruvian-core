// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

use std::env;
use std::fs;
use std::path::{Path, PathBuf};

pub const PINS: &[(&str, &str, &str)] = &[(
    "tool_protocol",
    "The tool protocol's Swift code",
    "pin_tool_protocol",
)];

pub struct Config {
    pub check: Option<PathBuf>,
    pub name: String,
    pub sources: Vec<String>,
}

pub fn parse_args(args: &[String]) -> Result<Config, String> {
    let mut check = None;
    let mut name = "tool_protocol".to_string();
    let mut sources = Vec::new();
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--check" => {
                i += 1;
                if i >= args.len() {
                    return Err("--check requires a PIN_FILE".into());
                }
                check = Some(PathBuf::from(&args[i]));
            }
            "--name" => {
                i += 1;
                if i >= args.len() {
                    return Err("--name requires a value".into());
                }
                name = args[i].clone();
            }
            "-h" | "--help" => {
                return Err(
                    "usage: pin_nexus_agent_shared [--check PIN_FILE] [--name tool_protocol] sources..."
                        .into(),
                );
            }
            other if other.starts_with('-') => {
                return Err(format!("unknown argument: {}", other));
            }
            other => {
                for part in other.split_whitespace() {
                    sources.push(part.to_string());
                }
            }
        }
        i += 1;
    }
    if !PINS.iter().any(|(k, _, _)| *k == name) {
        return Err(format!("invalid --name {:?}", name));
    }
    if sources.is_empty() {
        return Err("missing source paths".into());
    }
    Ok(Config {
        check,
        name,
        sources,
    })
}

fn sha256_hex(data: &[u8]) -> String {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
        0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
        0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
        0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
        0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
        0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
        0xc67178f2,
    ];
    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
        0x5be0cd19,
    ];

    let bit_len = (data.len() as u64) * 8;
    let mut padded = data.to_vec();
    padded.push(0x80);
    while (padded.len() % 64) != 56 {
        padded.push(0x00);
    }
    padded.extend_from_slice(&bit_len.to_be_bytes());

    for chunk in padded.chunks_exact(64) {
        let mut w = [0u32; 64];
        for (i, word) in chunk.chunks_exact(4).enumerate() {
            w[i] = u32::from_be_bytes([word[0], word[1], word[2], word[3]]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16]
                .wrapping_add(s0)
                .wrapping_add(w[i - 7])
                .wrapping_add(s1);
        }

        let mut a = h[0];
        let mut b = h[1];
        let mut c = h[2];
        let mut d = h[3];
        let mut e = h[4];
        let mut f = h[5];
        let mut g = h[6];
        let mut hh = h[7];

        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let temp1 = hh
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[i])
                .wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let temp2 = s0.wrapping_add(maj);

            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(temp1);
            d = c;
            c = b;
            b = a;
            a = temp1.wrapping_add(temp2);
        }

        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e);
        h[5] = h[5].wrapping_add(f);
        h[6] = h[6].wrapping_add(g);
        h[7] = h[7].wrapping_add(hh);
    }

    let mut out = String::with_capacity(64);
    for word in h {
        out.push_str(&format!("{:08x}", word));
    }
    out
}

pub fn digest(paths: &[String]) -> Result<String, String> {
    let mut sorted = paths.to_vec();
    sorted.sort();
    let mut buf = Vec::new();
    for path in &sorted {
        buf.extend_from_slice(path.as_bytes());
        buf.push(0);
        let bytes = fs::read(path).map_err(|e| format!("failed to read {}: {}", path, e))?;
        buf.extend_from_slice(&bytes);
        buf.push(0);
    }
    Ok(sha256_hex(&buf))
}

pub fn run_cli(args: &[String]) -> i32 {
    let config = match parse_args(args) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{}", e);
            return 2;
        }
    };
    let current = match digest(&config.sources) {
        Ok(d) => d,
        Err(e) => {
            eprintln!("{}", e);
            return 1;
        }
    };
    let (_, what, target) = PINS
        .iter()
        .find(|(k, _, _)| *k == config.name)
        .copied()
        .unwrap();
    let pin = format!("apps/desktop/vitruvian/bazel/{}.sha256", config.name);

    if let Some(check_path) = config.check {
        let pinned = match fs::read_to_string(&check_path) {
            Ok(s) => s.trim().to_string(),
            Err(e) => {
                eprintln!("failed to read {}: {}", check_path.display(), e);
                return 1;
            }
        };
        if pinned == current {
            return 0;
        }
        eprintln!(
            "{} changed and this app's pin did not.\n  1. bazel run //apps/desktop/vitruvian:{}\n  2. add a line for the change to the log in apps/desktop/vitruvian/UPSTREAM.md\nBoth go in the same commit, so the change ships in Vitruvian's next release.",
            what, target
        );
        return 1;
    }

    let Ok(root) = env::var("BUILD_WORKSPACE_DIRECTORY") else {
        eprintln!("Run with: bazel run //apps/desktop/vitruvian:{}", target);
        return 2;
    };
    let out_path = Path::new(&root).join(&pin);
    if let Err(e) = fs::write(&out_path, format!("{}\n", current)) {
        eprintln!("failed to write {}: {}", out_path.display(), e);
        return 1;
    }
    println!("pinned {} in {}", &current[..12], pin);
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_digest_and_check_pin() {
        let tmp = env::temp_dir().join("test_pin_nexus_agent_shared_rs");
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&tmp).unwrap();

        let src_a = tmp.join("a.swift");
        let src_b = tmp.join("b.swift");
        let pin_file = tmp.join("tool_protocol.sha256");

        fs::write(&src_a, "public struct A {}\n").unwrap();
        fs::write(&src_b, "public struct B {}\n").unwrap();

        let sources = vec![
            src_b.to_string_lossy().to_string(),
            src_a.to_string_lossy().to_string(),
        ];
        let d = digest(&sources).unwrap();
        fs::write(&pin_file, format!("{}\n", d)).unwrap();

        assert_eq!(
            run_cli(&[
                "--check".to_string(),
                pin_file.to_string_lossy().to_string(),
                "--name".to_string(),
                "tool_protocol".to_string(),
                sources[0].clone(),
                sources[1].clone(),
            ]),
            0
        );

        fs::write(&src_a, "public struct A { let x = 1 }\n").unwrap();
        assert_eq!(
            run_cli(&[
                "--check".to_string(),
                pin_file.to_string_lossy().to_string(),
                "--name".to_string(),
                "tool_protocol".to_string(),
                sources[0].clone(),
                sources[1].clone(),
            ]),
            1
        );

        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_committed_tool_protocol_pin_if_present() {
        let Ok(pin_file) = env::var("TOOL_PROTOCOL_PIN_FILE") else {
            return;
        };
        let Ok(sources_str) = env::var("TOOL_PROTOCOL_SOURCES") else {
            return;
        };
        let mut args = vec![
            "--check".to_string(),
            pin_file,
            "--name".to_string(),
            "tool_protocol".to_string(),
        ];
        for s in sources_str.split_whitespace() {
            args.push(s.to_string());
        }
        assert_eq!(run_cli(&args), 0);
    }
}
