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

//! Tests that secret backup files and their temp directories are created with
//! mode 0600 / 0700 even under a permissive caller umask (022), using fake
//! stub binaries only (never a real vault or cluster).

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

struct TestEnv {
    root: PathBuf,
    bin_dir: PathBuf,
    tmp_dir: PathBuf,
    kubeconfig: PathBuf,
    cli_bin: PathBuf,
}

impl TestEnv {
    fn new(name: &str) -> Self {
        let base = PathBuf::from(std::env::var("TEST_TMPDIR").expect("TEST_TMPDIR"));
        let root = base.join(name);
        let _ = fs::remove_dir_all(&root);
        let bin_dir = root.join("bin");
        let tmp_dir = root.join("tmp");
        fs::create_dir_all(&bin_dir).unwrap();
        fs::create_dir_all(&tmp_dir).unwrap();

        let kubeconfig = root.join("kube.yaml");
        fs::write(&kubeconfig, "apiVersion: v1\n").unwrap();

        let cli_rel = std::env::var("GITOPS_CLI_BIN").expect("GITOPS_CLI_BIN");
        let cli_bin = fs::canonicalize(std::env::current_dir().unwrap().join(cli_rel)).unwrap();

        let env = Self {
            root,
            bin_dir,
            tmp_dir,
            kubeconfig,
            cli_bin,
        };
        env.install_stubs();
        env
    }

    fn write_exec(&self, name: &str, body: &str) {
        let p = self.bin_dir.join(name);
        fs::write(&p, body).unwrap();
        fs::set_permissions(&p, fs::Permissions::from_mode(0o755)).unwrap();
    }

    fn install_stubs(&self) {
        self.write_exec(
            "kubectl",
            r#"#!/bin/sh
if [ "$4" = "argocd" ]; then
  cat <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: argocd-secret
  namespace: argocd
  resourceVersion: "1"
data:
  server.secretkey: RkFLRS1TRUNSRVQ=
  accounts.mcp.tokens: RkFLRS1UT0tFTg==
EOF
elif [ "$4" = "sealed-secrets" ]; then
  printf '%s\n' '{"apiVersion":"v1","kind":"List","items":[{"kind":"Secret","metadata":{"name":"sealed-secrets-key-fake","resourceVersion":"1"}}]}'
else
  echo "unexpected kubectl args: $*" >&2
  exit 1
fi
"#,
        );

        self.write_exec(
            "python3",
            r#"#!/bin/sh
# Hardlink the secret file created before python3 runs so we observe its exact creation mode.
if [ -n "$CAPTURE_AT_CREATION" ] && [ -e "$2" ]; then
  ln -f "$2" "$CAPTURE_AT_CREATION"
fi
exit 0
"#,
        );

        self.write_exec(
            "bw",
            r#"#!/bin/sh
case "$1" in
  status)
    printf '%s\n' '{"status":"unlocked"}'
    ;;
  sync)
    exit 0
    ;;
  get)
    case "$2" in
      item)
        printf '%s\n' '{"id":"item-1","attachments":[{"fileName":"sealed-secrets-keys.json","id":"att-1"},{"fileName":"argocd-secret.yaml","id":"att-2"}]}'
        ;;
      attachment)
        out=""
        prev=""
        for a in "$@"; do
          if [ "$prev" = "--output" ]; then
            out="$a"
            break
          fi
          prev="$a"
        done
        if [ -z "$out" ]; then
          exit 1
        fi
        printf 'kind: Secret\ndata:\n  server.secretkey: RkFLRQ==\n  accounts.mcp.tokens: RkFLRQ==\n' > "$out"
        if [ -n "$CAPTURE_AT_DOWNLOAD" ]; then
          ln -f "$out" "$CAPTURE_AT_DOWNLOAD"
        fi
        if [ -n "$CAPTURE_DIR_MODE" ]; then
          ls -ld "$(dirname "$out")" | awk '{print substr($1,1,10)}' > "$CAPTURE_DIR_MODE"
        fi
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  delete)
    exit 0
    ;;
  create)
    if [ "$2" = "attachment" ]; then
      file=""
      prev=""
      for a in "$@"; do
        if [ "$prev" = "--file" ]; then
          file="$a"
          break
        fi
        prev="$a"
      done
      if [ -z "$file" ] || [ ! -e "$file" ]; then
        exit 1
      fi
      if [ -n "$CAPTURE_AT_UPLOAD" ]; then
        ln -f "$file" "$CAPTURE_AT_UPLOAD"
      fi
      if [ -n "$CAPTURE_DIR_MODE" ]; then
        ls -ld "$(dirname "$file")" | awk '{print substr($1,1,10)}' > "$CAPTURE_DIR_MODE"
      fi
    fi
    ;;
  *)
    exit 1
    ;;
esac
"#,
        );
    }

    fn run_tool(
        &self,
        tool: &str,
        subcmd: &str,
        captures: &[(&str, &Path)],
    ) -> std::process::Output {
        let orig_path = std::env::var("PATH").unwrap_or_default();
        let path_val = format!("{}:{orig_path}", self.bin_dir.display());
        let mut cmd = Command::new("sh");
        cmd.arg("-c")
            .arg("umask 022 && exec \"$@\"")
            .arg("--")
            .arg(&self.cli_bin)
            .arg(tool)
            .arg(subcmd)
            .env("PATH", path_val)
            .env("TMPDIR", &self.tmp_dir)
            .env("KUBECONFIG", &self.kubeconfig)
            .env("KUBE_CONTEXT", "default")
            .env("BW_SESSION", "fake-session-token");
        for (k, p) in captures {
            cmd.env(k, p);
        }
        cmd.output().expect("spawn gitops-cli")
    }
}

fn mode(p: &Path) -> u32 {
    fs::metadata(p).unwrap().permissions().mode() & 0o777
}

#[test]
fn argocd_secret_backup_creates_0600_file_in_0700_dir() {
    let env = TestEnv::new("argocd_backup");
    let at_creation = env.root.join("at_creation");
    let at_upload = env.root.join("at_upload");
    let dir_mode = env.root.join("dir_mode");

    let out = env.run_tool(
        "argocd-secret",
        "backup",
        &[
            ("CAPTURE_AT_CREATION", &at_creation),
            ("CAPTURE_AT_UPLOAD", &at_upload),
            ("CAPTURE_DIR_MODE", &dir_mode),
        ],
    );
    assert!(
        out.status.success(),
        "argocd-secret backup failed: status={:?}, stderr={}",
        out.status.code(),
        String::from_utf8_lossy(&out.stderr)
    );
    assert_eq!(
        mode(&at_creation),
        0o600,
        "creation mode was {:o}",
        mode(&at_creation)
    );
    assert_eq!(
        mode(&at_upload),
        0o600,
        "upload mode was {:o}",
        mode(&at_upload)
    );
    assert_eq!(fs::read_to_string(&dir_mode).unwrap().trim(), "drwx------");
}

#[test]
fn argocd_secret_verify_creates_0600_file_in_0700_dir() {
    let env = TestEnv::new("argocd_verify");
    let at_download = env.root.join("at_download");
    let dir_mode = env.root.join("dir_mode");

    let out = env.run_tool(
        "argocd-secret",
        "verify",
        &[
            ("CAPTURE_AT_DOWNLOAD", &at_download),
            ("CAPTURE_DIR_MODE", &dir_mode),
        ],
    );
    assert!(
        out.status.success(),
        "argocd-secret verify failed: status={:?}, stderr={}",
        out.status.code(),
        String::from_utf8_lossy(&out.stderr)
    );
    assert_eq!(
        mode(&at_download),
        0o600,
        "download mode was {:o}",
        mode(&at_download)
    );
    assert_eq!(fs::read_to_string(&dir_mode).unwrap().trim(), "drwx------");
}

#[test]
fn sealed_secrets_backup_creates_0600_file_in_0700_dir() {
    let env = TestEnv::new("sealed_secrets_backup");
    let at_upload = env.root.join("at_upload");
    let dir_mode = env.root.join("dir_mode");

    let out = env.run_tool(
        "sealed-secrets-keys",
        "backup",
        &[
            ("CAPTURE_AT_UPLOAD", &at_upload),
            ("CAPTURE_DIR_MODE", &dir_mode),
        ],
    );
    assert!(
        out.status.success(),
        "sealed-secrets-keys backup failed: status={:?}, stderr={}",
        out.status.code(),
        String::from_utf8_lossy(&out.stderr)
    );
    assert_eq!(
        mode(&at_upload),
        0o600,
        "upload mode was {:o}",
        mode(&at_upload)
    );
    assert_eq!(fs::read_to_string(&dir_mode).unwrap().trim(), "drwx------");
}
