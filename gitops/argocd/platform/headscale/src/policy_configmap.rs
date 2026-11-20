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

//! Regenerates `configmap-policy.yaml` from `policy.hujson`.

use std::path::Path;
use std::process;

use headscale_values::{
    parse_policy, render_policy_configmap, PKG_DIR, POLICY_CONFIGMAP_FILENAME, POLICY_FILENAME,
};

fn main() {
    let ws = match std::env::var("BUILD_WORKSPACE_DIRECTORY") {
        Ok(d) if !d.is_empty() => d,
        _ => {
            eprintln!(
                "policy-configmap must be invoked via: bazel run //{PKG_DIR}:policy-configmap"
            );
            process::exit(1);
        }
    };
    let pkg_dir = Path::new(&ws).join(PKG_DIR);
    let policy_path = pkg_dir.join(POLICY_FILENAME);
    let raw = match std::fs::read_to_string(&policy_path) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("failed to read {}: {e}", policy_path.display());
            process::exit(1);
        }
    };
    if let Err(e) = parse_policy(&raw) {
        eprintln!("refusing to generate {POLICY_CONFIGMAP_FILENAME}: {e}");
        process::exit(1);
    }
    let out_path = pkg_dir.join(POLICY_CONFIGMAP_FILENAME);
    let rendered = render_policy_configmap(&raw);
    if let Err(e) = std::fs::write(&out_path, rendered) {
        eprintln!("failed to write {}: {e}", out_path.display());
        process::exit(1);
    }
    println!("wrote {}", out_path.display());
}
