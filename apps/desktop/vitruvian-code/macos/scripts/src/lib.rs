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

pub mod bazel_app_holds_bot;
pub mod bazel_app_holds_mermaid;
pub mod bazel_app_holds_node;
pub mod bundle;
pub mod check_packaged_app;
pub mod record_acp_fixture;

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

    /// Tests that put fake tools first on PATH run one at a time: PATH is the
    /// process's, and another test's restore would hand this one the real tools.
    static PATH_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

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
        let exe = exe_dir.join("VitruvianCode");
        fs::write(&exe, b"fake-executable").unwrap();
        fs::set_permissions(&exe, fs::Permissions::from_mode(0o755)).unwrap();

        let ui_bundle = exe_dir.join("VitruvianCode_VitruvianCodeUI.bundle");
        fs::create_dir_all(&ui_bundle).unwrap();
        fs::write(ui_bundle.join("mermaid.min.js"), b"mermaid").unwrap();

        let bot_bin = exe_dir.join("bot-engine");
        fs::write(&bot_bin, b"fake-bot-engine").unwrap();
        fs::set_permissions(&bot_bin, fs::Permissions::from_mode(0o755)).unwrap();

        let node_bin = exe_dir.join("node");
        fs::write(&node_bin, b"fake-node").unwrap();
        fs::set_permissions(&node_bin, fs::Permissions::from_mode(0o755)).unwrap();

        let helper_dir = exe_dir.join("claude-helper");
        fs::create_dir_all(&helper_dir).unwrap();
        fs::write(helper_dir.join("claude-helper.mjs"), b"console.log(1);\n").unwrap();

        let output = dir.join("output");
        fs::create_dir_all(&output).unwrap();

        let _path_guard = PATH_LOCK.lock().unwrap_or_else(|e| e.into_inner());
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
        let app = output.join("Vitruvian Code.app");
        assert!(app.join("Contents/MacOS/VitruvianCode").exists());
        assert!(app.join("Contents/Helpers/bot-engine").exists());
        assert!(app.join("Contents/Helpers/node").exists());
        assert!(app
            .join("Contents/Resources/claude-helper/claude-helper.mjs")
            .exists());
        assert!(app.join("Contents/Resources").exists());
        assert!(app.join("Contents/Info.plist").exists());
        assert!(app.join("Contents/PkgInfo").exists());

        let pkginfo = fs::read_to_string(app.join("Contents/PkgInfo")).unwrap();
        assert_eq!(pkginfo, "APPL????");

        let plist = fs::read_to_string(app.join("Contents/Info.plist")).unwrap();
        assert!(plist.contains("<string>1.2.3</string>"));
        assert!(plist.contains("com.vitruviansoftware.code"));
        assert!(plist.contains("<key>NSAppleEventsUsageDescription</key>"));

        let _ = fs::remove_dir_all(&dir);
    }

    /// The recorded `codesign` calls of a bundle run: a fake that logs its arguments.
    fn bundle_fixture(name: &str, helpers: &[&str]) -> (PathBuf, PathBuf, PathBuf, PathBuf) {
        let dir = std::env::temp_dir().join(name);
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let fake_bin = dir.join("fake_bin");
        fs::create_dir_all(&fake_bin).unwrap();
        let log = dir.join("codesign.log");
        make_fake_tool(
            &fake_bin,
            "codesign",
            &format!("#!/bin/sh\necho \"$@\" >> \"{}\"\nexit 0\n", log.display()),
        );
        let exe_dir = dir.join("exe_dir");
        fs::create_dir_all(&exe_dir).unwrap();
        let exe = exe_dir.join("VitruvianCode");
        fs::write(&exe, b"fake-executable").unwrap();
        fs::set_permissions(&exe, fs::Permissions::from_mode(0o755)).unwrap();
        let ui_bundle = exe_dir.join("VitruvianCode_VitruvianCodeUI.bundle");
        fs::create_dir_all(&ui_bundle).unwrap();
        fs::write(ui_bundle.join("mermaid.min.js"), b"mermaid").unwrap();
        for h in helpers {
            fs::write(exe_dir.join(h), format!("fake {}", h)).unwrap();
            fs::set_permissions(exe_dir.join(h), fs::Permissions::from_mode(0o644)).unwrap();
        }
        fs::create_dir_all(exe_dir.join("claude-helper")).unwrap();
        fs::write(
            exe_dir.join("claude-helper/claude-helper.mjs"),
            b"console.log(1);\n",
        )
        .unwrap();
        let output = dir.join("output");
        fs::create_dir_all(&output).unwrap();
        (dir, fake_bin, exe, output)
    }

    fn run_bundle(
        fake_bin: &std::path::Path,
        exe: &std::path::Path,
        output: &std::path::Path,
    ) -> i32 {
        let _path_guard = PATH_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let orig_path = std::env::var("PATH").unwrap_or_default();
        std::env::set_var("PATH", format!("{}:{}", fake_bin.display(), orig_path));
        let rc = bundle::run(&[
            "bundle-app".into(),
            exe.to_str().unwrap().into(),
            "1.2.3".into(),
            output.to_str().unwrap().into(),
        ]);
        std::env::set_var("PATH", &orig_path);
        rc
    }

    #[test]
    fn bundle_copies_thin_helpers_per_architecture_when_they_sit_beside_the_executable() {
        // The universal app: a thin bot-engine and node per architecture, and
        // no fat file (XProtect refuses one).
        let (dir, fake_bin, exe, output) = bundle_fixture(
            "bundle_universal_test",
            &[
                "bot-engine-arm64",
                "bot-engine-x86_64",
                "node-arm64",
                "node-x86_64",
            ],
        );
        assert_eq!(run_bundle(&fake_bin, &exe, &output), 0);
        let helpers = output.join("Vitruvian Code.app/Contents/Helpers");
        let mut names: Vec<String> = fs::read_dir(&helpers)
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().to_string())
            .collect();
        names.sort();
        assert_eq!(
            names,
            [
                "bot-engine-arm64",
                "bot-engine-x86_64",
                "node-arm64",
                "node-x86_64"
            ]
        );
        for n in &names {
            let mode = fs::metadata(helpers.join(n)).unwrap().permissions().mode();
            assert_eq!(mode & 0o755, 0o755, "{n} is executable");
        }
        // Each is signed ad hoc, inside-out before the app: Node with the JIT
        // entitlements and its identifier, the bot engine with its own identifier.
        let log = fs::read_to_string(dir.join("codesign.log")).unwrap();
        for arch in ["arm64", "x86_64"] {
            let node = log
                .lines()
                .find(|l| l.ends_with(&format!("Contents/Helpers/node-{arch}")))
                .unwrap_or_else(|| panic!("node-{arch} is signed: {log}"));
            assert!(
                node.contains("--identifier com.vitruviansoftware.code.node"),
                "{node}"
            );
            assert!(
                node.contains("--entitlements") && node.contains("node.entitlements"),
                "{node}"
            );
            let bot = log
                .lines()
                .find(|l| l.ends_with(&format!("Contents/Helpers/bot-engine-{arch}")))
                .unwrap_or_else(|| panic!("bot-engine-{arch} is signed: {log}"));
            assert!(
                bot.contains("--identifier com.vitruviansoftware.code.bot-engine"),
                "{bot}"
            );
            assert!(!bot.contains("--entitlements"), "{bot}");
        }
        let _ = fs::remove_dir_all(&dir);

        // Both the plain and the per-architecture files beside the executable:
        // the per-architecture ones go in, the plain one stays out.
        let (dir, fake_bin, exe, output) = bundle_fixture(
            "bundle_universal_over_plain_test",
            &[
                "bot-engine",
                "bot-engine-arm64",
                "bot-engine-x86_64",
                "node",
                "node-arm64",
                "node-x86_64",
            ],
        );
        assert_eq!(run_bundle(&fake_bin, &exe, &output), 0);
        let helpers = output.join("Vitruvian Code.app/Contents/Helpers");
        assert!(!helpers.join("node").exists() && !helpers.join("bot-engine").exists());
        assert!(
            helpers.join("node-arm64").is_file() && helpers.join("bot-engine-x86_64").is_file()
        );
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn bundle_errors_when_a_helper_is_in_neither_form() {
        // No Node at all.
        let (dir, fake_bin, exe, output) = bundle_fixture(
            "bundle_no_node_test",
            &["bot-engine-arm64", "bot-engine-x86_64"],
        );
        assert_eq!(run_bundle(&fake_bin, &exe, &output), 1);
        let _ = fs::remove_dir_all(&dir);

        // No bot engine at all.
        let (dir, fake_bin, exe, output) = bundle_fixture("bundle_no_bot_test", &["node"]);
        assert_eq!(run_bundle(&fake_bin, &exe, &output), 1);
        let _ = fs::remove_dir_all(&dir);

        // Only one architecture's thin copy: neither the pair nor the plain file.
        let (dir, fake_bin, exe, output) =
            bundle_fixture("bundle_half_pair_test", &["bot-engine", "node-arm64"]);
        assert_eq!(run_bundle(&fake_bin, &exe, &output), 1);
        let _ = fs::remove_dir_all(&dir);
    }

    // --- packaged-app fixtures ---------------------------------------------------

    const JIT_PAIR_PLIST: &str = "<plist version=\"1.0\"><dict><key>com.apple.security.cs.allow-jit</key><true/><key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/></dict></plist>";

    /// A `codesign` that verifies everything and reports the JIT pair, except for
    /// a file that has a marker beside the fake: `weak-<file>` gives it one
    /// entitlement, `unsigned-<file>` makes `--verify` fail on it.
    fn fake_codesign() -> String {
        format!(
            "#!/bin/sh\nfor last; do :; done\nd=\"$(dirname \"$0\")\"\nb=\"$(basename \"$last\")\"\nif [ \"$1\" = \"-d\" ]; then\n  if [ -f \"$d/weak-$b\" ]; then echo '<plist><dict><key>com.apple.security.cs.allow-jit</key><true/></dict></plist>'; else echo '{}'; fi\nfi\nif [ \"$1\" = \"--verify\" ] && [ -f \"$d/unsigned-$b\" ]; then exit 1; fi\nexit 0\n",
            JIT_PAIR_PLIST
        )
    }

    /// A `lipo -archs` that answers from `archs/<file name>` beside it, and says
    /// "arm64 x86_64" (a fat file) for a file it has no answer for.
    const FAKE_LIPO: &str = "#!/bin/sh\nf=\"$(dirname \"$0\")/archs/$(basename \"$2\")\"\nif [ -f \"$f\" ]; then cat \"$f\"; else echo \"arm64 x86_64\"; fi\n";

    struct AppFixture {
        dir: PathBuf,
        fake_bin: PathBuf,
        app: PathBuf,
    }

    impl AppFixture {
        fn set_archs(&self, file_name: &str, archs: &str) {
            let d = self.fake_bin.join("archs");
            fs::create_dir_all(&d).unwrap();
            fs::write(d.join(file_name), format!("{}\n", archs)).unwrap();
        }

        fn add_executable(&self, rel: &str, archs: Option<&str>) {
            let p = self.app.join(rel);
            fs::create_dir_all(p.parent().unwrap()).unwrap();
            fs::write(&p, b"fake-macho").unwrap();
            fs::set_permissions(&p, fs::Permissions::from_mode(0o755)).unwrap();
            if let Some(a) = archs {
                self.set_archs(p.file_name().unwrap().to_str().unwrap(), a);
            }
        }

        fn remove(&self, rel: &str) {
            fs::remove_file(self.app.join(rel)).unwrap();
        }

        fn marker(&self, name: &str) {
            fs::write(self.fake_bin.join(name), b"").unwrap();
        }

        /// Runs check-packaged-app on the app, with the fakes first on PATH.
        fn check(&self, archs: &[&str]) -> i32 {
            let _path_guard = PATH_LOCK.lock().unwrap_or_else(|e| e.into_inner());
            let orig_path = std::env::var("PATH").unwrap_or_default();
            let orig_cwd = std::env::current_dir().unwrap();
            std::env::set_var("PATH", format!("{}:{}", self.fake_bin.display(), orig_path));
            std::env::set_current_dir(&self.dir).unwrap();
            let mut args: Vec<String> = vec![
                "check-packaged-app".into(),
                self.app.to_str().unwrap().into(),
            ];
            args.extend(archs.iter().map(|a| a.to_string()));
            let rc = check_packaged_app::run(&args);
            std::env::set_current_dir(&orig_cwd).unwrap();
            std::env::set_var("PATH", &orig_path);
            rc
        }
    }

    /// A packaged app, complete: mermaid and its notices, the program, both
    /// helpers and the Claude helper. `universal` gives it the release's
    /// universal layout (a thin bot-engine and node per architecture); otherwise
    /// it is the arm64 app with one thin `bot-engine` and `node`.
    fn app_fixture(test_name: &str, universal: bool) -> AppFixture {
        let dir = std::env::temp_dir().join(test_name);
        let _ = fs::remove_dir_all(&dir);
        let fake_bin = dir.join("fake_bin");
        fs::create_dir_all(&fake_bin).unwrap();
        make_fake_tool(&fake_bin, "lipo", FAKE_LIPO);
        make_fake_tool(&fake_bin, "codesign", &fake_codesign());

        let app = dir.join("Vitruvian Code.app");
        let ui_bundle = app.join("Contents/Resources/VitruvianCode_VitruvianCodeUI.bundle");
        fs::create_dir_all(&ui_bundle).unwrap();
        let mermaid_content = b"mermaid-js-content";
        fs::write(ui_bundle.join("mermaid.min.js"), mermaid_content).unwrap();
        fs::write(ui_bundle.join("mermaid-LICENSE.txt"), b"licence").unwrap();
        fs::write(
            dir.join("THIRD_PARTY_NOTICES.md"),
            format!(
                "| SHA-256 of the file | `{}` |\n",
                sha256_hex(mermaid_content)
            ),
        )
        .unwrap();
        fs::create_dir_all(app.join("Contents/Resources/claude-helper")).unwrap();
        fs::write(
            app.join("Contents/Resources/claude-helper/claude-helper.mjs"),
            b"export {};\n",
        )
        .unwrap();

        let fx = AppFixture { dir, fake_bin, app };
        if universal {
            fx.add_executable("Contents/MacOS/VitruvianCode", Some("arm64 x86_64"));
            for arch in ["arm64", "x86_64"] {
                fx.add_executable(&format!("Contents/Helpers/bot-engine-{arch}"), Some(arch));
                fx.add_executable(&format!("Contents/Helpers/node-{arch}"), Some(arch));
            }
        } else {
            fx.add_executable("Contents/MacOS/VitruvianCode", Some("arm64"));
            fx.add_executable("Contents/Helpers/bot-engine", Some("arm64"));
            fx.add_executable("Contents/Helpers/node", Some("arm64"));
        }
        fx
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
        let app = dir.join("Vitruvian Code.app");
        let contents = app.join("Contents");
        let resources = contents.join("Resources");
        let ui_bundle = resources.join("VitruvianCode_VitruvianCodeUI.bundle");
        fs::create_dir_all(&ui_bundle).unwrap();
        fs::create_dir_all(contents.join("MacOS")).unwrap();

        let mermaid_content = b"mermaid-js-content";
        fs::write(ui_bundle.join("mermaid.min.js"), mermaid_content).unwrap();
        fs::write(ui_bundle.join("mermaid-LICENSE.txt"), b"licence").unwrap();

        let exe = contents.join("MacOS/VitruvianCode");
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

    #[test]
    fn check_packaged_app_notarized_runs_spctl() {
        let fx = app_fixture("check_notarized_test", true);
        make_fake_tool(&fx.fake_bin, "spctl", "#!/bin/sh\nexit 1\n");

        let run = |fx: &AppFixture| {
            let _path_guard = PATH_LOCK.lock().unwrap_or_else(|e| e.into_inner());
            let orig_path = std::env::var("PATH").unwrap_or_default();
            let orig_cwd = std::env::current_dir().unwrap();
            std::env::set_var("PATH", format!("{}:{}", fx.fake_bin.display(), orig_path));
            std::env::set_current_dir(&fx.dir).unwrap();
            let rc = check_packaged_app::run(&[
                "check-packaged-app".into(),
                "--notarized".into(),
                fx.app.to_str().unwrap().into(),
                "arm64".into(),
                "x86_64".into(),
            ]);
            std::env::set_current_dir(&orig_cwd).unwrap();
            std::env::set_var("PATH", &orig_path);
            rc
        };
        let rejected = run(&fx);
        make_fake_tool(&fx.fake_bin, "spctl", "#!/bin/sh\nexit 0\n");
        let accepted = run(&fx);

        assert_eq!(rejected, 1, "--notarized must fail when spctl rejects");
        assert_eq!(accepted, 0, "--notarized must pass when spctl accepts");
        let _ = fs::remove_dir_all(&fx.dir);
    }
    #[test]
    fn bazel_app_holds_bot_wants_the_universal_layout_with_thin_helpers() {
        let fx = app_fixture("bazel_app_holds_bot_test", true);
        // The Bazel app's program may be one architecture; its helpers are
        // universal all the same.
        fx.set_archs("VitruvianCode", "arm64");
        let verify = |fx: &AppFixture| {
            let _path_guard = PATH_LOCK.lock().unwrap_or_else(|e| e.into_inner());
            let orig_path = std::env::var("PATH").unwrap_or_default();
            std::env::set_var("PATH", format!("{}:{}", fx.fake_bin.display(), orig_path));
            let r = bazel_app_holds_bot::verify_unpacked_app(&fx.app, &fx.dir);
            std::env::set_var("PATH", &orig_path);
            r
        };

        // 1. A thin bot-engine missing for one architecture.
        fx.remove("Contents/Helpers/bot-engine-x86_64");
        let missing = verify(&fx).unwrap_err();
        assert!(
            missing.contains("Contents/Helpers/bot-engine-x86_64"),
            "{missing}"
        );

        // 2. The copy for an architecture holds the other one.
        fx.add_executable("Contents/Helpers/bot-engine-x86_64", Some("arm64"));
        let wrong = verify(&fx).unwrap_err();
        assert!(
            wrong.contains("bot-engine-x86_64 is built for 'arm64', expected 'x86_64'"),
            "{wrong}"
        );

        // 3. A copy that is fat.
        fx.add_executable("Contents/Helpers/bot-engine-x86_64", Some("arm64 x86_64"));
        let fat = verify(&fx).unwrap_err();
        assert!(
            fat.contains("bot-engine-x86_64 is built for 'arm64 x86_64'"),
            "{fat}"
        );

        // 4. A plain bot-engine in the universal app, even a thin one.
        fx.add_executable("Contents/Helpers/bot-engine-x86_64", Some("x86_64"));
        fx.add_executable("Contents/Helpers/bot-engine", Some("arm64"));
        let plain = verify(&fx).unwrap_err();
        assert!(
            plain.contains("Contents/Helpers/bot-engine is in the universal app"),
            "{plain}"
        );

        let _ = fs::remove_dir_all(&fx.dir);
    }
    #[test]
    fn entitlements_plist_parsing_checks_true_values() {
        let valid = r#"<?xml version="1.0"?><plist version="1.0"><dict>
            <key>com.apple.security.cs.allow-jit</key>
            <true/>
            <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
            <true/>
        </dict></plist>"#;
        assert!(check_packaged_app::entitlements_plist_has_true(
            valid,
            "com.apple.security.cs.allow-jit"
        ));
        assert!(check_packaged_app::entitlements_plist_has_true(
            valid,
            "com.apple.security.cs.allow-unsigned-executable-memory"
        ));

        let disabled = "<dict><key>com.apple.security.cs.allow-jit</key><false/></dict>";
        assert!(!check_packaged_app::entitlements_plist_has_true(
            disabled,
            "com.apple.security.cs.allow-jit"
        ));
        assert!(!check_packaged_app::entitlements_plist_has_true(
            disabled,
            "com.apple.security.cs.allow-unsigned-executable-memory"
        ));
    }

    #[test]
    fn node_entitlements_must_be_exactly_the_jit_pair() {
        let exact = "<plist><dict><key>com.apple.security.cs.allow-jit</key><true/><key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/></dict></plist>";
        assert!(check_packaged_app::unexpected_entitlement_keys(exact).is_empty());
        let extra = "<plist><dict><key>com.apple.security.cs.allow-jit</key><true/><key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/><key>com.apple.security.cs.disable-library-validation</key><true/></dict></plist>";
        assert_eq!(
            check_packaged_app::unexpected_entitlement_keys(extra),
            vec!["com.apple.security.cs.disable-library-validation".to_string()]
        );
    }

    #[test]
    fn check_packaged_app_rejects_missing_bad_arch_unentitled_node_and_missing_helper() {
        let fx = app_fixture("check_pkg_node_failures_test", true);
        let both = ["arm64", "x86_64"];
        assert_eq!(fx.check(&both), 0, "the complete universal app passes");

        // 1. A thin Node missing for one architecture fails.
        fx.remove("Contents/Helpers/node-x86_64");
        assert_eq!(fx.check(&both), 1);
        fx.add_executable("Contents/Helpers/node-x86_64", Some("x86_64"));
        assert_eq!(fx.check(&both), 0);

        // 2. A thin bot-engine missing for one architecture fails.
        fx.remove("Contents/Helpers/bot-engine-arm64");
        assert_eq!(fx.check(&both), 1);
        fx.add_executable("Contents/Helpers/bot-engine-arm64", Some("arm64"));
        assert_eq!(fx.check(&both), 0);

        // 3. The Claude helper's file gone fails.
        let helper_mjs = fx
            .app
            .join("Contents/Resources/claude-helper/claude-helper.mjs");
        fs::remove_file(&helper_mjs).unwrap();
        assert_eq!(fx.check(&both), 1);
        fs::write(&helper_mjs, b"export {};\n").unwrap();
        assert_eq!(fx.check(&both), 0);

        // 4. One Node with a single entitlement fails, and so does a Node whose
        //    signature does not verify.
        fx.marker("weak-node-x86_64");
        assert_eq!(fx.check(&both), 1);
        fs::remove_file(fx.fake_bin.join("weak-node-x86_64")).unwrap();
        fx.marker("unsigned-node-arm64");
        assert_eq!(fx.check(&both), 1);
        fs::remove_file(fx.fake_bin.join("unsigned-node-arm64")).unwrap();
        fx.marker("unsigned-bot-engine-arm64");
        assert_eq!(fx.check(&both), 1);
        fs::remove_file(fx.fake_bin.join("unsigned-bot-engine-arm64")).unwrap();

        // 5. The thin copy for an architecture holds the other one fails.
        fx.set_archs("node-arm64", "x86_64");
        assert_eq!(fx.check(&both), 1);
        fx.set_archs("node-arm64", "arm64");
        assert_eq!(fx.check(&both), 0);

        let _ = fs::remove_dir_all(&fx.dir);
    }

    #[test]
    fn check_packaged_app_refuses_a_fat_helper_in_the_universal_app() {
        let both = ["arm64", "x86_64"];

        // A fat `node` (the layout that XProtect refuses): there is no `node-<arch>`
        // for it to be, so it is a stray fat file.
        let fx = app_fixture("check_pkg_fat_node_test", true);
        fx.add_executable("Contents/Helpers/node", Some("arm64 x86_64"));
        assert_eq!(
            fx.check(&both),
            1,
            "a fat node in the universal app is refused"
        );
        let _ = fs::remove_dir_all(&fx.dir);

        // A fat `bot-engine`, the Rust helper that the first refused app held.
        let fx = app_fixture("check_pkg_fat_bot_test", true);
        fx.add_executable("Contents/Helpers/bot-engine", Some("arm64 x86_64"));
        assert_eq!(
            fx.check(&both),
            1,
            "a fat bot-engine in the universal app is refused"
        );
        let _ = fs::remove_dir_all(&fx.dir);

        // A plain helper is refused even when it is thin: the universal app
        // ships `<name>-<arch>`, and a lone `node` would be run on the wrong one.
        for plain in ["node", "bot-engine"] {
            let fx = app_fixture("check_pkg_plain_thin_test", true);
            fx.add_executable(&format!("Contents/Helpers/{plain}"), Some("arm64"));
            assert_eq!(
                fx.check(&both),
                1,
                "a plain {plain} in the universal app is refused"
            );
            let _ = fs::remove_dir_all(&fx.dir);
        }

        // A thin copy that is fat.
        for (name, archs) in [
            ("node-arm64", "arm64 x86_64"),
            ("bot-engine-x86_64", "arm64 x86_64"),
        ] {
            let fx = app_fixture("check_pkg_fat_copy_test", true);
            fx.set_archs(name, archs);
            assert_eq!(fx.check(&both), 1, "a fat {name} is refused");
            let _ = fs::remove_dir_all(&fx.dir);
        }

        // Any other fat Mach-O in Contents/Helpers.
        let fx = app_fixture("check_pkg_fat_other_test", true);
        fx.add_executable("Contents/Helpers/another-helper", None);
        assert_eq!(
            fx.check(&both),
            1,
            "any fat file in Contents/Helpers is refused"
        );
        fx.add_executable("Contents/Helpers/another-helper", Some("arm64"));
        assert_eq!(fx.check(&both), 0, "a thin file there is not");
        let _ = fs::remove_dir_all(&fx.dir);
    }

    #[test]
    fn check_packaged_app_single_architecture_app_keeps_todays_layout() {
        // One thin `bot-engine` and `node`: passes.
        let fx = app_fixture("check_pkg_single_arch_test", false);
        assert_eq!(fx.check(&["arm64"]), 0);

        // The per-architecture names are the universal app's: not accepted here.
        fx.remove("Contents/Helpers/node");
        fx.add_executable("Contents/Helpers/node-arm64", Some("arm64"));
        assert_eq!(
            fx.check(&["arm64"]),
            1,
            "a single-architecture app holds `node`"
        );
        fx.remove("Contents/Helpers/node-arm64");
        fx.add_executable("Contents/Helpers/node", Some("arm64"));
        fx.remove("Contents/Helpers/bot-engine");
        fx.add_executable("Contents/Helpers/bot-engine-arm64", Some("arm64"));
        assert_eq!(
            fx.check(&["arm64"]),
            1,
            "a single-architecture app holds `bot-engine`"
        );
        fx.remove("Contents/Helpers/bot-engine-arm64");
        fx.add_executable("Contents/Helpers/bot-engine", Some("arm64"));
        assert_eq!(fx.check(&["arm64"]), 0);

        // Thin for the wrong architecture fails.
        fx.set_archs("node", "x86_64");
        assert_eq!(fx.check(&["arm64"]), 1);
        fx.set_archs("node", "arm64");

        // An app whose helpers are fat is not the single-architecture app either.
        fx.set_archs("bot-engine", "arm64 x86_64");
        assert_eq!(fx.check(&["arm64"]), 1);
        let _ = fs::remove_dir_all(&fx.dir);
    }
    #[test]
    fn check_packaged_app_tool_folder_rejects_missing_thin_unentitled_node_and_missing_helper() {
        let dir = std::env::temp_dir().join("check_pkg_tool_folder_test");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let fake_bin = dir.join("fake_bin");
        fs::create_dir_all(&fake_bin).unwrap();
        make_fake_tool(&fake_bin, "lipo", "#!/bin/sh\necho \"arm64 x86_64\"\n");
        let full_codesign = "#!/bin/sh\nif [ \"$1\" = \"-d\" ]; then\n  cat <<'PLIST'\n<plist version=\"1.0\"><dict><key>com.apple.security.cs.allow-jit</key><true/><key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/></dict></plist>\nPLIST\nfi\nexit 0\n";
        make_fake_tool(&fake_bin, "codesign", full_codesign);

        let folder = dir.join("vitruvian-code");
        fs::create_dir_all(folder.join("bin/claude-helper")).unwrap();
        fs::write(folder.join("vitruvian-tool.json"), b"{}").unwrap();
        fs::write(folder.join("bin/mermaid.min.js"), b"m").unwrap();
        for exe in ["bin/tool"] {
            fs::write(folder.join(exe), b"fake").unwrap();
            fs::set_permissions(folder.join(exe), fs::Permissions::from_mode(0o755)).unwrap();
        }
        let node = folder.join("bin/node");
        let helper = folder.join("bin/claude-helper/claude-helper.mjs");

        let _path_guard = PATH_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let orig_path = std::env::var("PATH").unwrap_or_default();
        std::env::set_var("PATH", format!("{}:{}", fake_bin.display(), orig_path));

        let args: Vec<String> = vec![
            "check-packaged-app".into(),
            "--tool-folder".into(),
            folder.to_str().unwrap().into(),
            "arm64".into(),
            "x86_64".into(),
        ];

        // 1. No node, no helper -> fails.
        assert_eq!(check_packaged_app::run(&args), 1);

        // 2. Node present, helper missing -> fails.
        fs::write(&node, b"fake-node").unwrap();
        fs::set_permissions(&node, fs::Permissions::from_mode(0o755)).unwrap();
        assert_eq!(check_packaged_app::run(&args), 1);

        // 3. Helper empty -> fails.
        fs::write(&helper, b"").unwrap();
        assert_eq!(check_packaged_app::run(&args), 1);

        // 4. Helper there, node not executable -> fails.
        fs::write(&helper, b"export {};\n").unwrap();
        fs::set_permissions(&node, fs::Permissions::from_mode(0o644)).unwrap();
        assert_eq!(check_packaged_app::run(&args), 1);
        fs::set_permissions(&node, fs::Permissions::from_mode(0o755)).unwrap();

        // 5. Node thin (arm64 only) -> fails.
        make_fake_tool(&fake_bin, "lipo", "#!/bin/sh\necho \"arm64\"\n");
        assert_eq!(check_packaged_app::run(&args), 1);
        make_fake_tool(&fake_bin, "lipo", "#!/bin/sh\necho \"arm64 x86_64\"\n");

        // 6. Only one of the two entitlements -> fails.
        make_fake_tool(
            &fake_bin,
            "codesign",
            "#!/bin/sh\nif [ \"$1\" = \"-d\" ]; then echo '<plist><dict><key>com.apple.security.cs.allow-jit</key><true/></dict></plist>'; fi\nexit 0\n",
        );
        assert_eq!(check_packaged_app::run(&args), 1);

        // 7. Signature that does not verify -> fails.
        make_fake_tool(&fake_bin, "codesign", "#!/bin/sh\nexit 1\n");
        assert_eq!(check_packaged_app::run(&args), 1);
        make_fake_tool(&fake_bin, "codesign", full_codesign);

        // 8. Everything in place -> passes.
        assert_eq!(check_packaged_app::run(&args), 0);

        // The architectures asked for are the ones checked: a universal ask of a
        // node with two slices passes, an arm64 ask of the same node fails.
        let arm_only: Vec<String> = vec![
            "check-packaged-app".into(),
            "--tool-folder".into(),
            folder.to_str().unwrap().into(),
            "arm64".into(),
        ];
        assert_eq!(check_packaged_app::run(&arm_only), 1);

        // No folder named is a usage error, not a pass.
        assert_eq!(
            check_packaged_app::run(&["check-packaged-app".into(), "--tool-folder".into()]),
            2
        );

        std::env::set_var("PATH", &orig_path);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn check_packaged_app_tool_folder_checks_bin_tool_archs() {
        let dir = std::env::temp_dir().join("check_pkg_tool_folder_archs_test");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let fake_bin = dir.join("fake_bin");
        let archs_dir = fake_bin.join("archs");
        fs::create_dir_all(&archs_dir).unwrap();
        make_fake_tool(&fake_bin, "lipo", FAKE_LIPO);
        let full_codesign = "#!/bin/sh\nif [ \"$1\" = \"-d\" ]; then\n  cat <<'PLIST'\n<plist version=\"1.0\"><dict><key>com.apple.security.cs.allow-jit</key><true/><key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/></dict></plist>\nPLIST\nfi\nexit 0\n";
        make_fake_tool(&fake_bin, "codesign", full_codesign);

        let folder = dir.join("vitruvian-code");
        fs::create_dir_all(folder.join("bin/claude-helper")).unwrap();
        fs::write(folder.join("vitruvian-tool.json"), b"{}").unwrap();
        fs::write(folder.join("bin/mermaid.min.js"), b"m").unwrap();
        for exe in ["bin/tool", "bin/node"] {
            fs::write(folder.join(exe), b"fake").unwrap();
            fs::set_permissions(folder.join(exe), fs::Permissions::from_mode(0o755)).unwrap();
        }
        fs::write(
            folder.join("bin/claude-helper/claude-helper.mjs"),
            b"export {};\n",
        )
        .unwrap();

        let _path_guard = PATH_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let orig_path = std::env::var("PATH").unwrap_or_default();
        std::env::set_var("PATH", format!("{}:{}", fake_bin.display(), orig_path));

        let both_args: Vec<String> = vec![
            "check-packaged-app".into(),
            "--tool-folder".into(),
            folder.to_str().unwrap().into(),
            "arm64".into(),
            "x86_64".into(),
        ];
        let arm_args: Vec<String> = vec![
            "check-packaged-app".into(),
            "--tool-folder".into(),
            folder.to_str().unwrap().into(),
            "arm64".into(),
        ];

        // 1. node = arm64 x86_64, tool = arm64, expected arm64 x86_64 -> rejected.
        fs::write(archs_dir.join("node"), "arm64 x86_64\n").unwrap();
        fs::write(archs_dir.join("tool"), "arm64\n").unwrap();
        assert_eq!(check_packaged_app::run(&both_args), 1);

        // 2. node = arm64, tool = arm64 x86_64, expected arm64 -> rejected.
        fs::write(archs_dir.join("node"), "arm64\n").unwrap();
        fs::write(archs_dir.join("tool"), "arm64 x86_64\n").unwrap();
        assert_eq!(check_packaged_app::run(&arm_args), 1);

        // 3. node = arm64, tool = x86_64, expected arm64 -> rejected.
        fs::write(archs_dir.join("node"), "arm64\n").unwrap();
        fs::write(archs_dir.join("tool"), "x86_64\n").unwrap();
        assert_eq!(check_packaged_app::run(&arm_args), 1);

        // 4. node = arm64, tool = arm64, expected arm64 -> accepted.
        fs::write(archs_dir.join("node"), "arm64\n").unwrap();
        fs::write(archs_dir.join("tool"), "arm64\n").unwrap();
        assert_eq!(check_packaged_app::run(&arm_args), 0);

        std::env::set_var("PATH", &orig_path);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn bazel_app_holds_node_rejects_missing_node_wrong_arch_and_bad_helper_hash() {
        let fx = app_fixture("bazel_app_holds_node_unit_test", true);
        let nvmrc = fx.dir.join(".nvmrc");
        fs::write(&nvmrc, "22.21.1\n").unwrap();
        let expected_helper = fx.dir.join("expected.mjs");
        fs::write(&expected_helper, b"expected-bundle-bytes").unwrap();
        let verify = |fx: &AppFixture| {
            let _path_guard = PATH_LOCK.lock().unwrap_or_else(|e| e.into_inner());
            let orig_path = std::env::var("PATH").unwrap_or_default();
            std::env::set_var("PATH", format!("{}:{}", fx.fake_bin.display(), orig_path));
            let r = bazel_app_holds_node::verify_unpacked_app(
                &fx.app,
                &nvmrc,
                &expected_helper,
                &fx.dir,
            );
            std::env::set_var("PATH", &orig_path);
            r
        };

        // 1. A thin Node missing.
        fx.remove("Contents/Helpers/node-x86_64");
        let missing = verify(&fx).unwrap_err();
        assert!(
            missing.contains("Contents/Helpers/node-x86_64"),
            "{missing}"
        );

        // 2. The copy for an architecture holds the other one.
        fx.add_executable("Contents/Helpers/node-x86_64", Some("arm64"));
        let wrong = verify(&fx).unwrap_err();
        assert!(
            wrong.contains("node-x86_64 is built for 'arm64', expected 'x86_64'"),
            "{wrong}"
        );

        // 3. A single fat `node` in place of the two thin ones.
        fx.add_executable("Contents/Helpers/node-x86_64", Some("x86_64"));
        fx.add_executable("Contents/Helpers/node", Some("arm64 x86_64"));
        let fat = verify(&fx).unwrap_err();
        assert!(
            fat.contains("Contents/Helpers/node is in the universal app"),
            "{fat}"
        );
        fx.remove("Contents/Helpers/node");

        // 4. The Claude helper's bytes differ from the checked-in bundle: the
        //    Node files pass, then this fails before anything is run.
        let bad_hash = verify(&fx).unwrap_err();
        assert!(
            bad_hash.contains("does not match checked-in bundle"),
            "{bad_hash}"
        );

        let _ = fs::remove_dir_all(&fx.dir);
    }
}
