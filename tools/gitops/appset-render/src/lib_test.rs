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

//! main_test.go, ported, plus exact error text for the hazards it names.

use super::*;

fn check(name: &str, src: &str) -> Option<String> {
    check_source(name.as_bytes(), src.as_bytes(), &funcs()).map(|e| String::from_utf8(e).unwrap())
}

#[test]
fn stray_backtick_is_caught() {
    let src = "spec:\n  template:\n    values: |\n      {{`\n      annotations:\n        summary: pod `oops` restarting\n      `}}\n";
    let err = check("prometheus", src).expect("#414 must fail to parse");
    assert_eq!(
        err,
        "template: prometheus:6: bad character U+0060 '`' in action started at prometheus:4"
    );
    assert!(classify(err.as_bytes()).contains("#414"));
}

#[test]
fn valid_raw_string_passthrough_passes() {
    let src = "spec:\n  template:\n    values: |\n      {{`\n      annotations:\n        summary: {{ $labels.namespace }} restarting\n      `}}\n";
    assert_eq!(check("prometheus", src), None);
}

#[test]
fn unwrapped_literal_braces_are_caught() {
    let src = "spec:\n  template:\n    values: |\n      summary: {{ $labels.namespace }}\n";
    assert_eq!(
        check("prometheus", src).unwrap(),
        "template: prometheus:4: undefined variable \"$labels\""
    );
}

#[test]
fn generator_params_parse() {
    let src = "spec:\n  template:\n    spec:\n      destination:\n        server: '{{.server}}'\n        name: '{{.name}}'\n";
    assert_eq!(check("clusters", src), None);
}

#[test]
fn sprig_functions_resolve() {
    for f in [
        "{{ .values | nindent 12 }}",
        "{{ .name | quote }}",
        "{{ .cfg | toYaml | indent 4 }}",
        "{{ default \"x\" .missing }}",
    ] {
        assert_eq!(
            check("sprig", &format!("spec:\n  template:\n    v: {f}\n")),
            None,
            "{f}"
        );
    }
    assert_eq!(
        check("sprig", "{{ nosuchfunc .x }}").unwrap(),
        "template: sprig:1: function \"nosuchfunc\" not defined"
    );
}

#[test]
fn unclosed_action_is_caught() {
    assert_eq!(
        check("broken", "spec:\n  template:\n    v: {{ .server \n").unwrap(),
        "template: broken:4: unclosed action started at broken:3"
    );
}

#[test]
fn classify_distinguishes_hazards() {
    let backtick = check("b", "v: |\n  {{`\n  a `x`\n  `}}\n").unwrap();
    assert!(classify(backtick.as_bytes()).contains("#414"));
    let braces = check("c", "v: {{ $labels.ns }}\n").unwrap();
    assert!(classify(braces.as_bytes()).contains("raw-string passthrough"));
    assert!(classify(b"something else").starts_with("goTemplate parse failure"));
}

#[test]
fn more_error_shapes() {
    for (src, want) in [
        ("{{end}}", "template: t:1: unexpected {{end}}"),
        (
            "{{if .x}}a{{else}}b{{else}}c{{end}}",
            "template: t:1: expected end; found {{else}}",
        ),
        ("{{break}}", "template: t:1: {{break}} outside {{range}}"),
        ("{{range .x}}{{break}}{{end}}", ""),
        ("{{ 1e }}", "template: t:1: illegal number syntax: \"1e\""),
        (
            "{{ 99999999999999999999 }}",
            "template: t:1: integer overflow: \"99999999999999999999\"",
        ),
        (
            "{{ 1+i }}",
            "template: t:1: syntax error scanning complex number",
        ),
        (
            "{{ 'ab' }}",
            "template: t:1: malformed character constant: 'ab'",
        ),
        ("{{ \"\\q\" }}", "template: t:1: invalid syntax"),
        (
            "{{ true.x }}",
            "template: t:1: unexpected . after term \"true\"",
        ),
        (
            "{{ .x | 3 }}",
            "template: t:1: non executable command in pipeline stage 2",
        ),
        ("{{ }}", "template: t:1: missing value for command"),
        ("{{ ( }}", "template: t:1: unclosed left paren"),
        ("{{ ) }}", "template: t:1: unexpected right paren"),
        (
            "{{ € }}",
            "template: t:1: unrecognized character in action: U+20AC '€'",
        ),
        (
            "{{define \"a\"}}x{{end}}{{define \"a\"}}y{{end}}",
            "template: t:1: template: multiple definition of template \"a\"",
        ),
        ("{{/* c */}}", ""),
        (
            "{{/* c */ }}",
            "template: t:1: comment ends before closing delimiter",
        ),
        (
            "{{ $x, $y := .a }}",
            "template: t:1: too many declarations in command",
        ),
        ("{{ .x \"abcdefghijklm\" | }}", ""),
        (
            "{{ .x | }}{{ | }}",
            "template: t:1: unexpected \"|\" in command",
        ),
        ("{{ .x ! }}", "template: t:1: unexpected \"!\" in operand"),
        (
            "{{ .x \"abcdefghijklmnop\"= }}",
            "template: t:1: unexpected \"=\" in operand",
        ),
        ("{{ if }}", "template: t:1: missing value for if"),
    ] {
        let got = check("t", src).unwrap_or_default();
        assert_eq!(got, want, "{src}");
    }
}

#[test]
fn file_name_percent_is_a_verb() {
    // Go builds the error format with the name inside it.
    assert_eq!(
        check("a%sb", "{{end}}").unwrap(),
        "template: a{{end}}b:1: unexpected %!s(MISSING)"
    );
    assert_eq!(
        check("a%%b", "{{end}}").unwrap(),
        "template: a%b:1: unexpected {{end}}"
    );
}

#[test]
fn flags() {
    let mut e = Vec::new();
    assert_eq!(parse_flags(b"p", &[b"-h".to_vec()], &mut e).err(), Some(0));
    assert!(String::from_utf8(e)
        .unwrap()
        .starts_with("Usage of p:\n  -include-disabled\n"));
    let mut e = Vec::new();
    assert_eq!(
        parse_flags(b"p", &[b"-root".to_vec()], &mut e).err(),
        Some(2)
    );
    assert!(String::from_utf8(e)
        .unwrap()
        .starts_with("flag needs an argument: -root\nUsage of p:"));
    let mut e = Vec::new();
    let o = parse_flags(
        b"p",
        &[
            b"--root=x".to_vec(),
            b"-include-disabled=F".to_vec(),
            b"rest".to_vec(),
        ],
        &mut e,
    )
    .ok()
    .unwrap();
    assert_eq!(
        (o.root.as_slice(), o.include_disabled),
        (b"x".as_slice(), false)
    );
    let mut e = Vec::new();
    assert_eq!(
        parse_flags(b"p", &[b"-include-disabled=maybe".to_vec()], &mut e).err(),
        Some(2)
    );
    assert!(String::from_utf8(e)
        .unwrap()
        .starts_with("invalid boolean value \"maybe\" for -include-disabled: parse error\n"));
}

#[test]
fn paths() {
    assert_eq!(base(b"a/b/applicationset.yaml"), b"applicationset.yaml");
    assert_eq!(base(b"a/b/"), b"b");
    assert_eq!(base(b""), b".");
    assert_eq!(clean(b"./a//b/../c/"), b"a/c");
}
