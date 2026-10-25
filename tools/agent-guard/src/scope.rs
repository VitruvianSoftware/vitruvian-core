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

//! Scope: is a directory inside a vitruvian-core checkout or worktree?

use std::cell::RefCell;
use std::collections::HashMap;

use crate::paths::{abspath, dirname, isdir, isfile, join, read_text_head};
use crate::pyutil::{chars, is_space, starts_at};

thread_local! {
    static SCOPE_CACHE: RefCell<HashMap<String, Option<String>>> = RefCell::new(HashMap::new());
    static ROOT_CACHE: RefCell<HashMap<String, Option<String>>> = RefCell::new(HashMap::new());
}

pub fn clear_caches() {
    SCOPE_CACHE.with(|c| c.borrow_mut().clear());
    ROOT_CACHE.with(|c| c.borrow_mut().clear());
}

/// `MODULE_NAME_RE.search(head)`: `module\(\s*name\s*=\s*"vitruvian_core"`.
pub fn names_vitruvian_core(head: &str) -> bool {
    let t = chars(head);
    let mut from = 0;
    while let Some(at) = crate::pyutil::find_str(&t, "module(", from) {
        from = at + 1;
        let mut i = at + 7;
        let skip = |mut i: usize| {
            while i < t.len() && is_space(t[i]) {
                i += 1;
            }
            i
        };
        i = skip(i);
        if !starts_at(&t, i, "name") {
            continue;
        }
        i = skip(i + 4);
        if !starts_at(&t, i, "=") {
            continue;
        }
        i = skip(i + 1);
        if starts_at(&t, i, "\"vitruvian_core\"") {
            return true;
        }
    }
    false
}

/// The vitruvian-core root containing path (the path need not exist).
pub fn repo_root_of(path: &str) -> Option<String> {
    if let Some(hit) = ROOT_CACHE.with(|c| c.borrow().get(path).cloned()) {
        return hit;
    }
    let root = find_root(path);
    ROOT_CACHE.with(|c| c.borrow_mut().insert(path.to_string(), root.clone()));
    root
}

fn find_root(path: &str) -> Option<String> {
    let mut p = abspath(path);
    while !isdir(&p) {
        let parent = dirname(&p);
        if parent == p {
            return None;
        }
        p = parent;
    }
    let mut probe = p;
    let mut seen: Vec<String> = Vec::new();
    let remember = |seen: &[String], res: &Option<String>| {
        SCOPE_CACHE.with(|c| {
            let mut c = c.borrow_mut();
            for s in seen {
                c.insert(s.clone(), res.clone());
            }
        })
    };
    loop {
        if let Some(res) = SCOPE_CACHE.with(|c| c.borrow().get(&probe).cloned()) {
            remember(&seen, &res);
            return res;
        }
        seen.push(probe.clone());
        let module = join(&probe, "MODULE.bazel");
        if isfile(&module) {
            let head = read_text_head(&module, 8192).unwrap_or_default();
            if names_vitruvian_core(&head) {
                let res = Some(probe.clone());
                remember(&seen, &res);
                return res;
            }
        }
        let parent = dirname(&probe);
        if parent == probe {
            remember(&seen, &None);
            return None;
        }
        probe = parent;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn module_name() {
        assert!(names_vitruvian_core(
            "module(\n    name = \"vitruvian_core\",\n)"
        ));
        assert!(!names_vitruvian_core("module(name = \"abrialcode\")"));
    }
}
