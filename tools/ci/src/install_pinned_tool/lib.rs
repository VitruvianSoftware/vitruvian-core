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

//! //tools/ci:install_pinned_tool — download a pinned CI-tool release asset, verify
//! its checksum, and install it to ~/.local/bin for the rest of the job.

use shell_compat::{cat, env, env_or_empty, err, mktemp_dir, os, out, path, status};
use std::process::Command;

pub fn run(args: &[Vec<u8>]) -> i32 {
    if args.len() < 6 || args.len() > 7 {
        err(b"usage: install-pinned-tool <base-url> <asset> <checksum-file> <checksum-pattern> <bin-name> --tar|--raw [member-path]\n");
        return 2;
    }

    let base_url = &args[0];
    let asset = &args[1];
    let checksum_file = &args[2];
    let checksum_pattern = &args[3];
    let bin_name = &args[4];
    let mode = &args[5];

    // `${7:-${BIN_NAME}}`: an empty member path means the bin name too.
    let member_path = match args.get(6) {
        Some(m) if !m.is_empty() => m.clone(),
        _ => bin_name.clone(),
    };

    match mode.as_slice() {
        b"--tar" | b"--raw" => {}
        _ => {
            err(&cat(&[
                b"install-pinned-tool: mode must be --tar or --raw, got '",
                mode,
                b"'\n",
            ]));
            return 2;
        }
    }

    let github_path = match env("GITHUB_PATH") {
        Some(v) if !v.is_empty() => v,
        _ => {
            // As bash's `${GITHUB_PATH:?...}` did in the script: exit 1.
            err(b"install-pinned-tool: GITHUB_PATH: GITHUB_PATH must be set \xe2\x80\x94 this script is meant to run as a GitHub Actions step\n");
            return 1;
        }
    };

    let work = match mktemp_dir() {
        Ok(d) => d,
        Err(e) => {
            err(&cat(&[
                b"install-pinned-tool: mktemp failed: ",
                e.to_string().as_bytes(),
                b"\n",
            ]));
            return 1;
        }
    };

    let result = run_inner(
        &work,
        base_url,
        asset,
        checksum_file,
        checksum_pattern,
        bin_name,
        mode,
        &member_path,
        &github_path,
    );

    let _ = std::fs::remove_dir_all(path(&work));
    result
}

fn run_inner(
    work: &[u8],
    base_url: &[u8],
    asset: &[u8],
    checksum_file: &[u8],
    checksum_pattern: &[u8],
    bin_name: &[u8],
    mode: &[u8],
    member_path: &[u8],
    github_path: &[u8],
) -> i32 {
    let asset_url = cat(&[base_url, b"/", asset]);
    let asset_path = cat(&[work, b"/", asset]);
    let checksums_url = cat(&[base_url, b"/", checksum_file]);

    let rc = status(
        118,
        Command::new("curl")
            .current_dir(os(work))
            .arg("-fsSL")
            .arg("--retry")
            .arg("6")
            .arg("--retry-all-errors")
            .arg("--retry-max-time")
            .arg("180")
            .arg("--max-time")
            .arg("120")
            .arg("-O")
            .arg(os(&asset_url)),
        false,
    );
    if rc != 0 {
        return rc;
    }

    let rc = status(
        119,
        Command::new("curl")
            .current_dir(os(work))
            .arg("-fsSL")
            .arg("--retry")
            .arg("6")
            .arg("--retry-all-errors")
            .arg("--retry-max-time")
            .arg("180")
            .arg("--max-time")
            .arg("120")
            .arg("-O")
            .arg(os(&checksums_url)),
        false,
    );
    if rc != 0 {
        return rc;
    }

    // grep PATTERN CHECKSUM_FILE | sha256sum -c -
    let grep = Command::new("grep")
        .current_dir(os(work))
        .arg(os(checksum_pattern))
        .arg(os(checksum_file))
        .stdout(std::process::Stdio::piped())
        .spawn();
    let mut grep_child = match grep {
        Ok(c) => c,
        Err(e) => {
            err(&cat(&[
                b"install-pinned-tool: grep failed: ",
                e.to_string().as_bytes(),
                b"\n",
            ]));
            return 1;
        }
    };
    let rc = status(
        128,
        Command::new("sha256sum")
            .arg("-c")
            .arg("-")
            .current_dir(os(work))
            .stdin(std::process::Stdio::from(grep_child.stdout.take().unwrap())),
        false,
    );
    let grep_ok = grep_child.wait().map(|s| s.success()).unwrap_or(false);
    if rc != 0 || !grep_ok {
        return if rc != 0 { rc } else { 1 };
    }

    let home = env_or_empty("HOME");
    let local_bin = cat(&[&home, b"/.local/bin"]);
    // `mkdir -p` under `set -e`: a failure stops here, before anything installs.
    if let Err(e) = shell_compat::mkdir_p(&local_bin) {
        err(&cat(&[
            b"install-pinned-tool: mkdir -p ",
            &local_bin,
            b": ",
            e.to_string().as_bytes(),
            b"\n",
        ]));
        return 1;
    }

    match mode {
        b"--tar" => {
            let depth = member_path.iter().filter(|&&c| c == b'/').count();
            let rc = status(
                136,
                Command::new("tar")
                    .arg("-xzf")
                    .arg(os(&asset_path))
                    .arg("-C")
                    .arg(os(&local_bin))
                    .arg(&format!("--strip-components={}", depth))
                    .arg(os(member_path)),
                false,
            );
            if rc != 0 {
                return rc;
            }
        }
        b"--raw" => {
            let dest = cat(&[&local_bin, b"/", bin_name]);
            let rc = status(
                140,
                Command::new("install")
                    .arg("-m")
                    .arg("0755")
                    .arg(os(&asset_path))
                    .arg(os(&dest)),
                false,
            );
            if rc != 0 {
                return rc;
            }
        }
        _ => unreachable!(),
    }

    // `echo ... >> "${GITHUB_PATH}"` under `set -e`: a step that cannot put
    // the tool on PATH fails, rather than reporting an install later steps
    // cannot use.
    let appended = std::fs::OpenOptions::new()
        .append(true)
        .create(true)
        .open(path(github_path))
        .and_then(|mut f| {
            use std::io::Write;
            f.write_all(&cat(&[&local_bin, b"\n"]))
        });
    if let Err(e) = appended {
        err(&cat(&[
            b"install-pinned-tool: ",
            github_path,
            b": ",
            e.to_string().as_bytes(),
            b"\n",
        ]));
        return 1;
    }

    out(&cat(&[
        b"install-pinned-tool: installed ",
        bin_name,
        b" from ",
        base_url,
        b"/",
        asset,
        b"\n",
    ]));
    0
}
