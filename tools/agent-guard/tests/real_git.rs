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

//! RealGitStateTest: probe_git_state against a real repository with a real
//! merge conflict.

use agent_guard::gitstate::probe_git_state;

use crate::common::*;

#[test]
fn conflict_is_seen() {
    let _l = shared();
    if !have_git() {
        eprintln!("skipped: git is not on PATH");
        return;
    }
    let tmp = TempDir(mkdtemp("agent-guard-git-"));
    let dir = tmp.0.clone();
    let g = |args: &[&str]| git(&dir, args, true);
    g(&["init", "-q", "-b", "main"]);
    let path = join(&dir, "f.txt");
    write(&path, "base\n");
    g(&["add", "f.txt"]);
    g(&["commit", "-qm", "base"]);
    g(&["checkout", "-qb", "side"]);
    write(&path, "side\n");
    g(&["commit", "-qam", "side"]);
    g(&["checkout", "-q", "main"]);
    write(&path, "main\n");
    g(&["commit", "-qam", "main"]);
    let st = probe_git_state(&dir);
    assert!(!st.in_progress(), "{:?}", st);
    assert!(st.primary, "{:?}", st);
    git(&dir, &["merge", "side"], false);
    let st = probe_git_state(&dir);
    assert!(st.merge, "{:?}", st);
    assert_eq!(st.unmerged, vec![realpath(&path)]);
    eprintln!(
        "real git: merge in progress detected, conflicted file {}",
        st.unmerged[0]
    );
}
