// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

//! Writes the Info.plist fragment that stamps the fan helper's version.
//!
//! The app compares this value with the registered daemon to decide whether the
//! privileged helper must be re-registered, so it has to change whenever the
//! helper binary or its launchd plist does. Same derivation as `build.sh`: a
//! SHA-256 over the two files' SHA-256 digests.

use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
    pub helper: PathBuf,
    pub launchd_plist: PathBuf,
    pub out: PathBuf,
}

pub fn parse_args(args: &[String]) -> Result<Config, String> {
    if args.len() != 3 || args.iter().any(|a| a == "-h" || a == "--help") {
        return Err(
            "usage: helper_version_plist <helper binary> <launchd plist> <out.plist>".into(),
        );
    }
    Ok(Config {
        helper: PathBuf::from(&args[0]),
        launchd_plist: PathBuf::from(&args[1]),
        out: PathBuf::from(&args[2]),
    })
}

pub fn sha256_hex(data: &[u8]) -> String {
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

/// Computes the combined SHA-256 over the two files' SHA-256 digests:
/// `shasum -a 256 "$helper" "$launchd_plist" | awk '{print $1}' | shasum -a 256 | awk '{print $1}'`
pub fn compute_helper_version_from_bytes(
    helper_bytes: &[u8],
    launchd_plist_bytes: &[u8],
) -> String {
    let d1 = sha256_hex(helper_bytes);
    let d2 = sha256_hex(launchd_plist_bytes);
    let combined = format!("{}\n{}\n", d1, d2);
    sha256_hex(combined.as_bytes())
}

pub fn compute_helper_version(helper: &Path, launchd_plist: &Path) -> Result<String, String> {
    let helper_bytes = fs::read(helper).map_err(|e| format!("read {}: {}", helper.display(), e))?;
    let plist_bytes =
        fs::read(launchd_plist).map_err(|e| format!("read {}: {}", launchd_plist.display(), e))?;
    Ok(compute_helper_version_from_bytes(
        &helper_bytes,
        &plist_bytes,
    ))
}

pub fn render_version_plist(version: &str) -> String {
    format!(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n\
<plist version=\"1.0\">\n\
<dict>\n\
\t<key>VitruvianFanControlHelperVersion</key>\n\
\t<string>{}</string>\n\
</dict>\n\
</plist>\n",
        version
    )
}

pub fn run(config: &Config) -> Result<(), String> {
    let version = compute_helper_version(&config.helper, &config.launchd_plist)?;
    let xml = render_version_plist(&version);
    if let Some(parent) = config.out.parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent).map_err(|e| format!("mkdir: {}", e))?;
        }
    }
    fs::write(&config.out, xml).map_err(|e| format!("write {}: {}", config.out.display(), e))
}

pub fn run_cli(args: &[String]) -> i32 {
    let config = match parse_args(args) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{}", e);
            return 2;
        }
    };
    match run(&config) {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("{}", e);
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;

    #[test]
    fn test_compute_helper_version_and_render_plist() {
        // Known SHA-256 of "abc": ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
        // Known SHA-256 of "": e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        assert_eq!(
            sha256_hex(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        assert_eq!(
            sha256_hex(b""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );

        let v = compute_helper_version_from_bytes(b"helper-bin", b"launchd-plist");
        assert_eq!(v.len(), 64);

        let xml = render_version_plist(&v);
        assert!(xml.contains("<key>VitruvianFanControlHelperVersion</key>"));
        assert!(xml.contains(&format!("<string>{}</string>", v)));
    }

    #[test]
    fn test_run_writes_output_plist() {
        let tmp = env::temp_dir().join(format!("test_helper_version_plist_{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&tmp).unwrap();

        let helper = tmp.join("helper");
        let plist = tmp.join("launchd.plist");
        let out = tmp.join("sub/Info.plist");

        fs::write(&helper, b"binary-bytes").unwrap();
        fs::write(&plist, b"<plist/>").unwrap();

        let rc = run_cli(&[
            helper.to_string_lossy().to_string(),
            plist.to_string_lossy().to_string(),
            out.to_string_lossy().to_string(),
        ]);
        assert_eq!(rc, 0);
        let written = fs::read_to_string(&out).unwrap();
        let expected_ver = compute_helper_version_from_bytes(b"binary-bytes", b"<plist/>");
        assert_eq!(written, render_version_plist(&expected_ver));

        let _ = fs::remove_dir_all(&tmp);
    }
}
