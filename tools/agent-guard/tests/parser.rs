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

//! ParserTest: the shell parser the decisions rest on.

use agent_guard::shell::{
    body_substitutions, fallback_split, parse_script, strip_heredoc_bodies, SimpleCommand,
    MAX_COMMANDS,
};

use crate::common::*;

fn parse(t: &str) -> Vec<SimpleCommand> {
    let mut budget = MAX_COMMANDS;
    parse_script(t, &mut budget).unwrap_or_else(|e| panic!("{:?} parsing {:?}", e, t))
}

fn words(t: &str) -> Vec<Vec<String>> {
    parse(t).into_iter().map(|c| c.words).collect()
}

fn w(items: &[&[&str]]) -> Vec<Vec<String>> {
    items
        .iter()
        .map(|c| c.iter().map(|x| x.to_string()).collect())
        .collect()
}

fn v(items: &[&str]) -> Vec<String> {
    items.iter().map(|x| x.to_string()).collect()
}

#[test]
fn quotes_and_operators() {
    let _l = shared();
    assert_eq!(
        words("a 'b c' \"d $e\" && f|g; h"),
        w(&[&["a", "b c", "d $e"], &["f"], &["g"], &["h"]])
    );
}

#[test]
fn redirections_are_not_arguments() {
    let _l = shared();
    let cmds = parse("git log > out.txt 2>&1 < /dev/null");
    assert_eq!(cmds[0].words, v(&["git", "log"]));
    assert!(
        cmds[0]
            .redirects
            .contains(&(">".to_string(), "out.txt".to_string())),
        "{:?}",
        cmds[0].redirects
    );
}

#[test]
fn heredoc_body_is_data() {
    let _l = shared();
    let cmds = parse("cat <<'EOF' > f\ngit push\nEOF\necho done");
    let got: Vec<Vec<String>> = cmds.iter().map(|c| c.words.clone()).collect();
    assert_eq!(got, w(&[&["cat"], &["echo", "done"]]));
    assert_eq!(cmds[0].heredocs, v(&["git push"]));
}

#[test]
fn nested_substitution() {
    let _l = shared();
    assert!(words("echo \"$(echo $(git push))\"").contains(&v(&["git", "push"])));
}

#[test]
fn heredoc_inside_substitution_is_skipped() {
    let _l = shared();
    let t = "echo \"$(cat <<'EOF'\nit's `git push`\nEOF\n)\" && ls";
    assert_eq!(
        words(t),
        w(&[
            &["echo", "$(cat <<'EOF'\nit's `git push`\nEOF\n)"],
            &["ls"],
            &["cat"]
        ])
    );
}

#[test]
fn fallback_drops_heredoc_bodies() {
    let _l = shared();
    let t = "cat <<'EOF'\ndon't git push\nEOF\necho \"unterminated";
    assert!(!strip_heredoc_bodies(t).contains("push"));
    let all: Vec<String> = fallback_split(t, None)
        .expect("fallback splits")
        .into_iter()
        .flat_map(|c| c.words)
        .collect();
    assert!(!all.contains(&"push".to_string()), "{:?}", all);
}

#[test]
fn unquoted_heredoc_runs_its_substitutions() {
    let _l = shared();
    let body: Vec<char> = "a $(git push) `go test` \\$(no) \\`no\\` $((1+2))"
        .chars()
        .collect();
    let subs: Vec<String> = body_substitutions(&body)
        .into_iter()
        .map(|s| s.into_iter().collect())
        .collect();
    assert_eq!(subs, v(&["git push", "go test"]));
    assert!(words("cat <<EOF\n$(git push)\nEOF").contains(&v(&["git", "push"])));
    assert!(!words("cat <<'EOF'\n$(git push)\nEOF").contains(&v(&["git", "push"])));
}

#[test]
fn comments() {
    let _l = shared();
    assert_eq!(words("ls # git push"), w(&[&["ls"]]));
}
