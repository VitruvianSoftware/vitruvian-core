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

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

use crate::check_import_directions::{
    analyze_module, cached_canonicalize, is_code_file, is_node_builtin, resolve_app_root,
    seed_non_symlink_files,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BoundaryReport {
    pub name: String,
    pub exports: usize,
    pub modules: usize,
}

fn is_external_allowed(id: &str, group_external: &[String]) -> bool {
    group_external
        .iter()
        .any(|ext| id == ext || id.starts_with(&format!("{}/", ext)))
}

/// Build each browser or Node export group and reject imports outside its declared ownership.
/// Port of `checkPackageBoundaries(root)` in `scripts/check-package-boundaries.mjs`.
pub fn check_package_boundaries(root_in: &Path) -> Result<Vec<BoundaryReport>, String> {
    let root = std::fs::canonicalize(root_in)
        .map_err(|e| format!("Failed to resolve root {}: {}", root_in.display(), e))?;

    let pkg_raw = std::fs::read_to_string(root.join("package.json"))
        .map_err(|e| format!("Failed to read package.json: {}", e))?;
    let pkg: serde_json::Value =
        serde_json::from_str(&pkg_raw).map_err(|e| format!("Invalid package.json: {}", e))?;

    let groups_raw = std::fs::read_to_string(root.join("scripts/package-boundaries.json"))
        .map_err(|e| format!("Failed to read scripts/package-boundaries.json: {}", e))?;
    let groups_val: serde_json::Value = serde_json::from_str(&groups_raw)
        .map_err(|e| format!("Invalid scripts/package-boundaries.json: {}", e))?;
    let groups_obj = groups_val
        .as_object()
        .ok_or_else(|| "scripts/package-boundaries.json must be a JSON object".to_string())?;

    let exports_obj = pkg.get("exports").and_then(|v| v.as_object());
    let mut declared_exports: Vec<String> = exports_obj
        .map(|m| m.keys().cloned().collect())
        .unwrap_or_default();
    declared_exports.sort();

    let mut classified_exports: Vec<String> = Vec::new();
    for group in groups_obj.values() {
        if let Some(arr) = group.get("exports").and_then(|v| v.as_array()) {
            for item in arr {
                if let Some(s) = item.as_str() {
                    classified_exports.push(s.to_string());
                }
            }
        }
    }
    classified_exports.sort();

    if declared_exports.is_empty() || declared_exports != classified_exports {
        return Err("Every package export must belong to exactly one boundary group".to_string());
    }

    let deps = pkg.get("dependencies").and_then(|v| v.as_object());
    let peer_deps = pkg.get("peerDependencies").and_then(|v| v.as_object());
    let dev_deps = pkg.get("devDependencies").and_then(|v| v.as_object());

    let mut parsed_cache: HashMap<PathBuf, Vec<String>> = HashMap::new();
    let mut canon_cache: HashMap<PathBuf, Option<PathBuf>> = HashMap::new();
    seed_non_symlink_files(&root, &["src", "server", "build"], &mut canon_cache);
    let mut reports = Vec::new();

    for (name, group) in groups_obj {
        let runtime_opt = group.get("runtime").and_then(|v| v.as_str());
        if let Some(rt) = runtime_opt {
            if rt != "browser" && rt != "node" {
                return Err(format!("Invalid boundary runtime: {}", name));
            }
        }
        let is_node = runtime_opt == Some("node");

        let modules_arr = match group.get("modules").and_then(|v| v.as_array()) {
            Some(arr) if !arr.is_empty() => arr,
            _ => return Err(format!("Invalid package boundary: {}", name)),
        };
        let external_arr = match group.get("external").and_then(|v| v.as_array()) {
            Some(arr) => arr,
            None => return Err(format!("Invalid package boundary: {}", name)),
        };

        let mut group_external = Vec::new();
        for ext_val in external_arr {
            let ext = ext_val
                .as_str()
                .ok_or_else(|| format!("Invalid package boundary: {}", name))?;
            let in_deps = deps.map(|m| m.contains_key(ext)).unwrap_or(false);
            let in_peer = peer_deps.map(|m| m.contains_key(ext)).unwrap_or(false);
            let in_dev = is_node && dev_deps.map(|m| m.contains_key(ext)).unwrap_or(false);
            if !in_deps && !in_peer && !in_dev {
                return Err(format!(
                    "Boundary external must be a declared dependency for its runtime: {}",
                    ext
                ));
            }
            group_external.push(ext.to_string());
        }

        let mut allowed: HashSet<PathBuf> = HashSet::new();
        for mod_val in modules_arr {
            let module = match mod_val.as_str() {
                Some(s) if !s.is_empty() => s,
                _ => return Err(format!("Boundary modules must be repository paths: {}", name)),
            };
            if Path::new(module).is_absolute()
                || module.contains('\\')
                || module.split('/').any(|seg| seg == "..")
            {
                return Err(format!("Boundary modules must be repository paths: {}", name));
            }
            let resolved = cached_canonicalize(&root.join(module), &mut canon_cache)
                .ok_or_else(|| format!("Boundary module does not exist: {} ({})", module, name))?;
            let rel = match resolved.strip_prefix(&root) {
                Ok(r) => r,
                Err(_) => return Err(format!("Boundary module escapes repository: {}", name)),
            };
            if rel.as_os_str().is_empty() || rel.is_absolute() {
                return Err(format!("Boundary module escapes repository: {}", name));
            }
            allowed.insert(resolved);
        }

        let group_exports = group
            .get("exports")
            .and_then(|v| v.as_array())
            .ok_or_else(|| format!("Invalid package boundary: {}", name))?;

        let mut input: Vec<PathBuf> = Vec::with_capacity(group_exports.len());
        let exports_map = exports_obj.unwrap();

        for key_val in group_exports {
            let key = key_val
                .as_str()
                .ok_or_else(|| format!("Invalid export key in {}", name))?;
            let declaration = exports_map
                .get(key)
                .ok_or_else(|| format!("Missing export declaration: {}", key))?;

            let target = if is_node {
                let obj = match declaration.as_object() {
                    Some(o) if o.len() == 1 && o.contains_key("node") => o,
                    _ => return Err(format!("Node export must have only a node condition: {}", key)),
                };
                obj.get("node").and_then(|v| v.as_str())
            } else {
                declaration.as_str()
            };

            let target_str = match target {
                Some(s) if s.starts_with("./") => s,
                _ => return Err(format!("Export must point to an owned module: {}", key)),
            };
            let resolved_target = match cached_canonicalize(&root.join(target_str), &mut canon_cache) {
                Some(p) => p,
                None => return Err(format!("Export must point to an owned module: {}", key)),
            };
            if !allowed.contains(&resolved_target) {
                return Err(format!("Export must point to an owned module: {}", key));
            }
            input.push(resolved_target);
        }

        // Walk the transitive module dependency graph starting from `input`
        let mut seen: HashSet<PathBuf> = HashSet::new();
        let mut queue: Vec<PathBuf> = input.clone();

        while let Some(mod_path) = queue.pop() {
            if !allowed.contains(&mod_path) {
                let rel = mod_path
                    .strip_prefix(&root)
                    .unwrap_or(&mod_path)
                    .to_string_lossy()
                    .replace('\\', "/");
                return Err(format!(
                    "Package boundary {} imports an unowned module: {}",
                    name, rel
                ));
            }
            if !seen.insert(mod_path.clone()) {
                continue;
            }

            let file_name = mod_path
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or("");
            if !is_code_file(file_name) {
                continue;
            }

            let imports = if let Some(cached) = parsed_cache.get(&mod_path) {
                cached.clone()
            } else {
                let src = std::fs::read_to_string(&mod_path)
                    .map_err(|e| format!("Cannot read {}: {}", mod_path.display(), e))?;
                let analysis = analyze_module(&src)?;
                parsed_cache.insert(mod_path.clone(), analysis.imports.clone());
                analysis.imports
            };

            for specifier in imports {
                let clean = specifier.split('?').next().unwrap_or(&specifier);
                if is_external_allowed(clean, &group_external) {
                    continue;
                }
                if is_node_builtin(clean) {
                    if is_node {
                        continue;
                    } else {
                        return Err(format!(
                            "Package boundary {} imports an unowned module: {} (Node builtin in browser export)",
                            name, specifier
                        ));
                    }
                }
                if clean.starts_with('.') {
                    let candidate = mod_path.parent().unwrap_or(&root).join(clean);
                    let resolved_dep =
                        cached_canonicalize(&candidate, &mut canon_cache).ok_or_else(|| {
                            format!(
                                "Package boundary {} imports an unowned module: {}",
                                name, clean
                            )
                        })?;
                    if !allowed.contains(&resolved_dep) {
                        let rel = resolved_dep
                            .strip_prefix(&root)
                            .unwrap_or(&resolved_dep)
                            .to_string_lossy()
                            .replace('\\', "/");
                        return Err(format!(
                            "Package boundary {} imports an unowned module: {}",
                            name, rel
                        ));
                    }
                    if !seen.contains(&resolved_dep) {
                        queue.push(resolved_dep);
                    }
                } else {
                    return Err(format!(
                        "Package boundary {} imports an unowned module: {}",
                        name, specifier
                    ));
                }
            }
        }

        reports.push(BoundaryReport {
            name: name.clone(),
            exports: input.len(),
            modules: seen.len(),
        });
    }

    Ok(reports)
}

pub fn run(args: &[String]) -> Result<String, String> {
    let root = resolve_app_root(args.first().map(String::as_str))?;
    let reports = check_package_boundaries(&root)?;
    let lines: Vec<String> = reports
        .iter()
        .map(|r| {
            format!(
                "Checked {}: {} exports, {} owned modules.",
                r.name, r.exports, r.modules
            )
        })
        .collect();
    Ok(lines.join("\n"))
}
