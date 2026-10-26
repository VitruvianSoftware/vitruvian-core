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

use std::process;

fn usage() -> ! {
    eprintln!(
        "Usage: track_upstream_rs [--root DIR] [--changes PATH] [--upstream-url URL] \
         [--cache DIR] [--no-fetch] <command> [options]\n\
         \n\
         Commands:\n\
         \x20 check-changes       validate local-changes.tsv (offline)\n\
         \x20 check               exit 1 unless this copy is the base plus the listed changes\n\
         \x20 status [--check] [--markdown] [--previous-body FILE]\n\
         \x20 sync [--to REV] [--dry-run] [--report FILE] [--allow-dirty]"
    );
    process::exit(2);
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let refs: Vec<&str> = args.iter().map(|s| s.as_str()).collect();

    let mut root_arg = None;
    let mut changes_arg = None;
    let mut upstream_url = upstream_rs::UPSTREAM_URL;
    let mut cache_arg = None;
    let mut no_fetch = false;
    let mut i = 0;

    while i < refs.len() {
        match refs[i] {
            "--root" => {
                if i + 1 >= refs.len() { usage(); }
                root_arg = Some(refs[i + 1]);
                i += 2;
            }
            "--changes" => {
                if i + 1 >= refs.len() { usage(); }
                changes_arg = Some(refs[i + 1]);
                i += 2;
            }
            "--upstream-url" => {
                if i + 1 >= refs.len() { usage(); }
                upstream_url = refs[i + 1];
                i += 2;
            }
            "--cache" => {
                if i + 1 >= refs.len() { usage(); }
                cache_arg = Some(refs[i + 1]);
                i += 2;
            }
            "--no-fetch" => {
                no_fetch = true;
                i += 1;
            }
            "--help" | "-h" => usage(),
            _ => break,
        }
    }

    if i >= refs.len() {
        usage();
    }

    let root = match upstream_rs::repo_root(root_arg) {
        Ok(r) => r,
        Err(e) => {
            eprintln!("upstream: {}", e);
            process::exit(2);
        }
    };
    let cp = upstream_rs::changes_path(changes_arg, &root);
    let cache = upstream_rs::cache_dir(cache_arg);

    let cmd = refs[i];
    let rest = &refs[i + 1..];

    let code = match cmd {
        "check-changes" => {
            match upstream_rs::cmd_check_changes(&cp) {
                Ok(c) => c,
                Err(e) => { eprintln!("upstream: {}", e); 2 }
            }
        }
        "check" => {
            match upstream_rs::cmd_check(&root, &cp, upstream_url, &cache, no_fetch) {
                Ok(c) => c,
                Err(e) => { eprintln!("upstream: {}", e); 2 }
            }
        }
        "status" => {
            let mut check = false;
            let mut markdown = false;
            let mut previous_body = None;
            let mut j = 0;
            while j < rest.len() {
                match rest[j] {
                    "--check" => { check = true; j += 1; }
                    "--markdown" => { markdown = true; j += 1; }
                    "--previous-body" => {
                        if j + 1 >= rest.len() { usage(); }
                        previous_body = Some(rest[j + 1]);
                        j += 2;
                    }
                    _ => { j += 1; }
                }
            }
            match upstream_rs::cmd_status(&root, &cp, upstream_url, &cache, no_fetch, check, markdown, previous_body) {
                Ok(c) => c,
                Err(e) => { eprintln!("upstream: {}", e); 2 }
            }
        }
        "sync" => {
            let mut to = None;
            let mut dry_run = false;
            let mut report_path = None;
            let mut allow_dirty = false;
            let mut j = 0;
            while j < rest.len() {
                match rest[j] {
                    "--to" => {
                        if j + 1 >= rest.len() { usage(); }
                        to = Some(rest[j + 1]);
                        j += 2;
                    }
                    "--dry-run" => { dry_run = true; j += 1; }
                    "--report" => {
                        if j + 1 >= rest.len() { usage(); }
                        report_path = Some(rest[j + 1]);
                        j += 2;
                    }
                    "--allow-dirty" => { allow_dirty = true; j += 1; }
                    _ => { j += 1; }
                }
            }
            match upstream_rs::cmd_sync(&root, &cp, upstream_url, &cache, no_fetch, to, dry_run, report_path, allow_dirty) {
                Ok(c) => c,
                Err(e) => { eprintln!("upstream: {}", e); 2 }
            }
        }
        _ => {
            eprintln!("unknown command: {}", cmd);
            usage();
        }
    };

    process::exit(code);
}
