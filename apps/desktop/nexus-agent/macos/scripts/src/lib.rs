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

pub mod bazel_app_holds_mermaid;
pub mod bundle;
pub mod check_packaged_app;

// --- Pure-Rust SHA-256 (FIPS 180-4) ------------------------------------------

const K: [u32; 64] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

const H0: [u32; 8] = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
];

fn sha256_pad(data: &[u8]) -> Vec<u8> {
    let bit_len = (data.len() as u64).wrapping_mul(8);
    let mut buf = data.to_vec();
    buf.push(0x80);
    while buf.len() % 64 != 56 {
        buf.push(0);
    }
    buf.extend_from_slice(&bit_len.to_be_bytes());
    buf
}

fn sha256_compress(state: &mut [u32; 8], block: &[u8]) {
    let mut w = [0u32; 64];
    for i in 0..16 {
        w[i] = u32::from_be_bytes([
            block[i * 4],
            block[i * 4 + 1],
            block[i * 4 + 2],
            block[i * 4 + 3],
        ]);
    }
    for i in 16..64 {
        let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
        let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16]
            .wrapping_add(s0)
            .wrapping_add(w[i - 7])
            .wrapping_add(s1);
    }

    let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut h] = *state;

    for i in 0..64 {
        let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
        let ch = (e & f) ^ ((!e) & g);
        let temp1 = h
            .wrapping_add(s1)
            .wrapping_add(ch)
            .wrapping_add(K[i])
            .wrapping_add(w[i]);
        let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
        let maj = (a & b) ^ (a & c) ^ (b & c);
        let temp2 = s0.wrapping_add(maj);

        h = g;
        g = f;
        f = e;
        e = d.wrapping_add(temp1);
        d = c;
        c = b;
        b = a;
        a = temp1.wrapping_add(temp2);
    }

    state[0] = state[0].wrapping_add(a);
    state[1] = state[1].wrapping_add(b);
    state[2] = state[2].wrapping_add(c);
    state[3] = state[3].wrapping_add(d);
    state[4] = state[4].wrapping_add(e);
    state[5] = state[5].wrapping_add(f);
    state[6] = state[6].wrapping_add(g);
    state[7] = state[7].wrapping_add(h);
}

pub fn sha256_hex(data: &[u8]) -> String {
    let padded = sha256_pad(data);
    let mut state = H0;
    for block in padded.chunks_exact(64) {
        sha256_compress(&mut state, block);
    }
    state
        .iter()
        .map(|v| format!("{:08x}", v))
        .collect::<String>()
}

pub fn sha256_hex_file(path: &std::path::Path) -> std::io::Result<String> {
    let data = std::fs::read(path)?;
    Ok(sha256_hex(&data))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::io::Write;
    use std::os::unix::fs::PermissionsExt;
    use std::path::PathBuf;

    // --- SHA-256 -----------------------------------------------------------------

    #[test]
    fn sha256_empty() {
        assert_eq!(
            sha256_hex(b""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
    }

    #[test]
    fn sha256_abc() {
        assert_eq!(
            sha256_hex(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[test]
    fn sha256_hello() {
        assert_eq!(
            sha256_hex(b"hello"),
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        );
    }

    #[test]
    fn sha256_448_bits() {
        // "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
        assert_eq!(
            sha256_hex(b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        );
    }

    #[test]
    fn sha256_file() {
        let dir = std::env::temp_dir().join("sha256_file_test");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let p = dir.join("test.txt");
        fs::write(&p, b"hello").unwrap();
        assert_eq!(
            sha256_hex_file(&p).unwrap(),
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        );
        let _ = fs::remove_dir_all(&dir);
    }

    // --- bazel_app_holds_mermaid -------------------------------------------------

    fn make_zip(dir: &std::path::Path, zip_name: &str, entries: &[(&str, &[u8])]) -> PathBuf {
        let zip_path = dir.join(zip_name);
        let staging = dir.join("zip_staging");
        let _ = fs::remove_dir_all(&staging);
        for (name, content) in entries {
            let p = staging.join(name);
            fs::create_dir_all(p.parent().unwrap()).unwrap();
            fs::write(&p, content).unwrap();
        }
        let status = std::process::Command::new("zip")
            .arg("-qr")
            .arg(&zip_path)
            .arg(".")
            .current_dir(&staging)
            .status()
            .unwrap();
        assert!(status.success(), "zip failed");
        let _ = fs::remove_dir_all(&staging);
        zip_path
    }

    #[test]
    fn bazel_app_holds_mermaid_match() {
        let dir = std::env::temp_dir().join("bahm_match_test");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();

        let script_content = b"mermaid-content-here";
        let licence_content = b"licence-text";
        let script_src = dir.join("mermaid.min.js");
        let licence_src = dir.join("mermaid-LICENSE.txt");
        fs::write(&script_src, script_content).unwrap();
        fs::write(&licence_src, licence_content).unwrap();

        let zip_path = make_zip(
            &dir,
            "TestApp.zip",
            &[
                (
                    "TestApp.app/Contents/Resources/mermaid.min.js",
                    script_content,
                ),
                (
                    "TestApp.app/Contents/Resources/mermaid-LICENSE.txt",
                    licence_content,
                ),
            ],
        );

        let tmpdir = dir.join("tmp");
        fs::create_dir_all(&tmpdir).unwrap();
        std::env::set_var("TEST_TMPDIR", &tmpdir);

        let args: Vec<String> = vec![
            "bazel-app-holds-mermaid".into(),
            "TestApp".into(),
            zip_path.to_str().unwrap().into(),
            script_src.to_str().unwrap().into(),
            licence_src.to_str().unwrap().into(),
        ];
        let rc = bazel_app_holds_mermaid::run(&args);
        assert_eq!(rc, 0, "expected success for matching files");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn bazel_app_holds_mermaid_mismatch() {
        let dir = std::env::temp_dir().join("bahm_mismatch_test");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();

        let script_src = dir.join("mermaid.min.js");
        let licence_src = dir.join("mermaid-LICENSE.txt");
        fs::write(&script_src, b"source-version").unwrap();
        fs::write(&licence_src, b"licence-text").unwrap();

        let zip_path = make_zip(
            &dir,
            "TestApp.zip",
            &[
                (
                    "TestApp.app/Contents/Resources/mermaid.min.js",
                    b"DIFFERENT-content",
                ),
                (
                    "TestApp.app/Contents/Resources/mermaid-LICENSE.txt",
                    b"licence-text",
                ),
            ],
        );

        let tmpdir = dir.join("tmp");
        fs::create_dir_all(&tmpdir).unwrap();
        std::env::set_var("TEST_TMPDIR", &tmpdir);

        let args: Vec<String> = vec![
            "bazel-app-holds-mermaid".into(),
            "TestApp".into(),
            zip_path.to_str().unwrap().into(),
            script_src.to_str().unwrap().into(),
            licence_src.to_str().unwrap().into(),
        ];
        let rc = bazel_app_holds_mermaid::run(&args);
        assert_ne!(rc, 0, "expected failure for mismatched content");
        let _ = fs::remove_dir_all(&dir);
    }

    // --- bundle ------------------------------------------------------------------

    fn make_fake_tool(dir: &std::path::Path, name: &str, script: &str) {
        let p = dir.join(name);
        fs::write(&p, script).unwrap();
        fs::set_permissions(&p, fs::Permissions::from_mode(0o755)).unwrap();
    }

    #[test]
    fn bundle_creates_structure() {
        let dir = std::env::temp_dir().join("bundle_test");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();

        let fake_bin = dir.join("fake_bin");
        fs::create_dir_all(&fake_bin).unwrap();
        make_fake_tool(&fake_bin, "codesign", "#!/bin/sh\nexit 0\n");

        let exe_dir = dir.join("exe_dir");
        fs::create_dir_all(&exe_dir).unwrap();
        let exe = exe_dir.join("NexusAgent");
        fs::write(&exe, b"fake-executable").unwrap();
        fs::set_permissions(&exe, fs::Permissions::from_mode(0o755)).unwrap();

        let ui_bundle = exe_dir.join("NexusAgent_NexusAgentUI.bundle");
        fs::create_dir_all(&ui_bundle).unwrap();
        fs::write(ui_bundle.join("mermaid.min.js"), b"mermaid").unwrap();

        let output = dir.join("output");
        fs::create_dir_all(&output).unwrap();

        let orig_path = std::env::var("PATH").unwrap_or_default();
        std::env::set_var("PATH", format!("{}:{}", fake_bin.display(), orig_path));

        let args: Vec<String> = vec![
            "bundle-app".into(),
            exe.to_str().unwrap().into(),
            "1.2.3".into(),
            output.to_str().unwrap().into(),
        ];
        let rc = bundle::run(&args);

        std::env::set_var("PATH", &orig_path);

        assert_eq!(rc, 0, "bundle should succeed");
        let app = output.join("NexusAgent.app");
        assert!(app.join("Contents/MacOS/NexusAgent").exists());
        assert!(app.join("Contents/Resources").exists());
        assert!(app.join("Contents/Info.plist").exists());
        assert!(app.join("Contents/PkgInfo").exists());

        let pkginfo = fs::read_to_string(app.join("Contents/PkgInfo")).unwrap();
        assert_eq!(pkginfo, "APPL????");

        let plist = fs::read_to_string(app.join("Contents/Info.plist")).unwrap();
        assert!(plist.contains("<string>1.2.3</string>"));
        assert!(plist.contains("com.vitruviansoftware.nexusagent"));

        let _ = fs::remove_dir_all(&dir);
    }

    // --- check_packaged_app ------------------------------------------------------

    #[test]
    fn check_packaged_app_valid() {
        let dir = std::env::temp_dir().join("check_pkg_test");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();

        let fake_bin = dir.join("fake_bin");
        fs::create_dir_all(&fake_bin).unwrap();
        make_fake_tool(&fake_bin, "lipo", "#!/bin/sh\necho \"arm64\"\n");
        make_fake_tool(&fake_bin, "codesign", "#!/bin/sh\nexit 0\n");

        // Create app structure
        let app = dir.join("NexusAgent.app");
        let contents = app.join("Contents");
        let resources = contents.join("Resources");
        let ui_bundle = resources.join("NexusAgent_NexusAgentUI.bundle");
        fs::create_dir_all(&ui_bundle).unwrap();
        fs::create_dir_all(contents.join("MacOS")).unwrap();

        let mermaid_content = b"mermaid-js-content";
        fs::write(ui_bundle.join("mermaid.min.js"), mermaid_content).unwrap();
        fs::write(ui_bundle.join("mermaid-LICENSE.txt"), b"licence").unwrap();

        let exe = contents.join("MacOS/NexusAgent");
        fs::write(&exe, b"fake-exe").unwrap();
        fs::set_permissions(&exe, fs::Permissions::from_mode(0o755)).unwrap();

        // Create THIRD_PARTY_NOTICES.md two levels up from the "script dir".
        // The Rust binary resolves this relative to its own exe; for tests we
        // set up the structure so the function can find it. The check_packaged_app
        // module reads notices relative to the app path's ../../THIRD_PARTY_NOTICES.md,
        // but actually the shell script uses SCRIPT_DIR/../../THIRD_PARTY_NOTICES.md.
        // For a unit test we'll pass the notices path via a helper or just test
        // the SHA comparison logic directly. Actually the run() function needs
        // the notices file relative to the binary. Let's put it where the function
        // will look.
        let sha = sha256_hex(mermaid_content);
        let notices_dir = dir.join("notices");
        fs::create_dir_all(&notices_dir).unwrap();
        let notices = notices_dir.join("THIRD_PARTY_NOTICES.md");
        fs::write(&notices, format!("| SHA-256 of the file | `{}` |\n", sha)).unwrap();

        // For the run() function, SCRIPT_DIR is the exe's dir. The notices
        // are at SCRIPT_DIR/../../THIRD_PARTY_NOTICES.md. We can't easily
        // control current_exe in a test, so we test the inner logic directly.

        // Test the SHA extraction helper
        let content = fs::read_to_string(&notices).unwrap();
        let extracted = check_packaged_app::extract_sha256_from_notices(&content);
        assert_eq!(extracted, Some(sha.clone()));

        // Test the mermaid search
        let found = check_packaged_app::find_mermaid(app.to_str().unwrap(), "mermaid.min.js");
        assert!(found.is_some(), "should find mermaid.min.js");

        let _ = fs::remove_dir_all(&dir);
    }
}
