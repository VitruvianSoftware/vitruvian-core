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

use std::path::{Path, PathBuf};

pub fn resolve_dist_dir(explicit: Option<&str>) -> Result<PathBuf, String> {
    if let Some(dir) = explicit {
        let p = PathBuf::from(dir);
        if p.join("cesium").is_dir() {
            return Ok(p);
        }
    }

    let candidates: Vec<Option<String>> = vec![
        std::env::var("RUNFILES_DIR")
            .ok()
            .filter(|s| !s.is_empty())
            .map(|r| format!("{}/_main/apps/web/gods-eye-view/dist", r)),
        std::env::var("TEST_SRCDIR")
            .ok()
            .filter(|s| !s.is_empty())
            .map(|r| format!("{}/_main/apps/web/gods-eye-view/dist", r)),
        Some("apps/web/gods-eye-view/dist".to_string()),
        Some("dist".to_string()),
    ];

    for candidate in &candidates {
        if let Some(path_str) = candidate {
            let p = PathBuf::from(path_str);
            if p.join("cesium").is_dir() {
                return Ok(p);
            }
        }
    }

    Err("dist/cesium directory not found in runfiles or cwd.".into())
}

pub fn verify(dist_dir: &Path) -> Result<String, String> {
    let cesium = dist_dir.join("cesium");

    let cesium_js = cesium.join("Cesium.js");
    if !cesium_js.is_file() {
        return Err("MISSING: Cesium.js".into());
    }
    if std::fs::metadata(&cesium_js)
        .map(|m| m.len() == 0)
        .unwrap_or(true)
    {
        return Err("MISSING: Cesium.js (empty)".into());
    }

    let widgets_css = cesium.join("Widgets/widgets.css");
    if !widgets_css.is_file() {
        return Err("MISSING: Widgets/widgets.css".into());
    }
    if std::fs::metadata(&widgets_css)
        .map(|m| m.len() == 0)
        .unwrap_or(true)
    {
        return Err("MISSING: Widgets/widgets.css (empty)".into());
    }

    if !cesium.join("Workers").is_dir() {
        return Err("MISSING: Workers/".into());
    }
    if !cesium.join("ThirdParty").is_dir() {
        return Err("MISSING: ThirdParty/".into());
    }

    let assets_dir = cesium.join("Assets");
    if !assets_dir.is_dir() {
        return Err("MISSING: Assets directory".into());
    }
    let asset_count = std::fs::read_dir(&assets_dir)
        .map_err(|e| format!("Cannot read Assets directory: {}", e))?
        .count();
    if asset_count == 0 {
        return Err("MISSING: Assets directory is empty".into());
    }

    Ok(format!(
        "All Cesium runtime assets verified successfully in {}/cesium ({} assets in Assets/).",
        dist_dir.display(),
        asset_count
    ))
}

pub fn run(args: &[String]) -> Result<(), String> {
    let explicit = args.first().map(String::as_str);
    let dist_dir = resolve_dist_dir(explicit)?;
    eprintln!(
        "Verifying Cesium runtime assets in {}/cesium ...",
        dist_dir.display()
    );
    let msg = verify(&dist_dir)?;
    println!("{}", msg);
    Ok(())
}
