// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT
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

//! Native Rust port of `apps/desktop/nexus-agent/src/annotations.test.js`.

use nexus_agent_src_lib::annotations::archived_conversation_ids;
use std::env;
use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

fn make_temp_dir(prefix: &str) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir = env::temp_dir().join(format!("{}-{}-{}", prefix, std::process::id(), nanos));
    fs::create_dir_all(&dir).unwrap();
    dir
}

#[test]
fn archived_ids_are_collected_across_data_directories() {
    let home = make_temp_dir("nexus-annotations");
    let app = home.join("antigravity");
    let cli = home.join("antigravity-cli");
    for dir in [&app, &cli] {
        fs::create_dir_all(dir.join("annotations")).unwrap();
    }
    fs::write(app.join("annotations/a.pbtxt"), "archived:true").unwrap();
    fs::write(app.join("annotations/b.pbtxt"), "pinned:true").unwrap();
    fs::write(cli.join("annotations/c.pbtxt"), "archived: true").unwrap();
    fs::write(cli.join("annotations/notes.txt"), "archived:true").unwrap();

    let collected: Vec<String> = archived_conversation_ids(&[&app, &cli])
        .into_iter()
        .collect();
    assert_eq!(collected, vec!["a".to_string(), "c".to_string()]);

    let missing: Vec<String> = archived_conversation_ids(&[home.join("missing")])
        .into_iter()
        .collect();
    assert!(missing.is_empty());

    let _ = fs::remove_dir_all(&home);
}
