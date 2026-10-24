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

//! Redaction for the log. Each of agent_guard.py's `_REDACTIONS` regexes is a
//! matcher here with the same leftmost, backtracking result, applied in the
//! same order with `re.sub`'s left-to-right, non-overlapping replacement.

use crate::pyutil::{
    ci_alpha, ci_starts_at, is_decimal, is_space, is_word, starts_at, word_boundary,
};

pub const LOG_COMMAND_MAX: usize = 1000;
/// Every value quantifier's upper bound (`_V`).
const V: usize = 1400;

/// A match at a position: (end, replacement text).
type Matcher = fn(&[char], usize) -> Option<(usize, String)>;

fn sub(t: &[char], m: Matcher) -> Vec<char> {
    let mut out = Vec::with_capacity(t.len());
    let mut i = 0;
    while i < t.len() {
        if let Some((end, repl)) = m(t, i) {
            out.extend(repl.chars());
            i = end;
        } else {
            out.push(t[i]);
            i += 1;
        }
    }
    out
}

fn s(t: &[char], a: usize, b: usize) -> String {
    t[a..b].iter().collect()
}

/// Greedy run of chars satisfying f from i, at most max; returns the end.
fn run(t: &[char], i: usize, max: usize, f: impl Fn(char) -> bool) -> usize {
    let mut j = i;
    while j < t.len() && j - i < max && f(t[j]) {
        j += 1;
    }
    j
}

/// `(?<!\S)` at i.
fn no_nonspace_before(t: &[char], i: usize) -> bool {
    i == 0 || is_space(t[i - 1])
}

fn ws(c: char) -> bool {
    is_space(c)
}

/// `(?i)(authorization\s{0,8}:\s{0,8})([^'\"\n]{0,1400})` -> `\1[REDACTED]`.
fn m_authorization(t: &[char], i: usize) -> Option<(usize, String)> {
    if !ci_starts_at(t, i, "authorization") {
        return None;
    }
    let a = i + 13;
    let w = run(t, a, usize::MAX, ws);
    if w - a > 8 || t.get(w) != Some(&':') {
        return None;
    }
    let g1_end = run(t, w + 1, 8, ws);
    let end = run(t, g1_end, V, |c| c != '\'' && c != '"' && c != '\n');
    Some((end, format!("{}[REDACTED]", s(t, i, g1_end))))
}

fn ci_header_class(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '-' || ci_alpha(c)
}

/// Does a keyword start at k and end at or before q? Returns its end.
fn keyword_at(t: &[char], k: usize, q: usize, words: &[&str]) -> Vec<usize> {
    let mut ends = Vec::new();
    for w in words {
        if ci_starts_at(t, k, w) {
            let e = k + w.chars().count();
            if e <= q {
                ends.push(e);
            }
        }
    }
    ends
}

/// `(?i)(\b[A-Za-z0-9-]{0,64}(?:-key|token|secret|cookie|api-?key)[A-Za-z0-9-]{0,64}\s{0,8}:\s{0,8})([^'\"\n]{1,1400})`.
fn m_header(t: &[char], i: usize) -> Option<(usize, String)> {
    if !word_boundary(t, i) {
        return None;
    }
    let q = run(t, i, usize::MAX, ci_header_class);
    let split_ok = (0..=64.min(q.saturating_sub(i))).any(|a| {
        keyword_at(
            t,
            i + a,
            q,
            &["-key", "token", "secret", "cookie", "api-key", "apikey"],
        )
        .iter()
        .any(|&e| q - e <= 64)
    });
    if !split_ok {
        return None;
    }
    let w = run(t, q, usize::MAX, ws);
    if w - q > 8 || t.get(w) != Some(&':') {
        return None;
    }
    let colon = w;
    let wsmax = run(t, colon + 1, 8, ws);
    let value = |c: char| c != '\'' && c != '"' && c != '\n';
    for g1_end in (colon + 1..=wsmax).rev() {
        let end = run(t, g1_end, V, value);
        if end > g1_end {
            return Some((end, format!("{}[REDACTED]", s(t, i, g1_end))));
        }
    }
    None
}

/// `(?i)\b(bearer|basic)\s{1,8}([A-Za-z0-9._~+/=-]{8,1400})` -> `\1 [REDACTED]`.
fn m_bearer(t: &[char], i: usize) -> Option<(usize, String)> {
    if !word_boundary(t, i) {
        return None;
    }
    let word_end = if ci_starts_at(t, i, "bearer") {
        i + 6
    } else if ci_starts_at(t, i, "basic") {
        i + 5
    } else {
        return None;
    };
    let w = run(t, word_end, usize::MAX, ws);
    if w == word_end || w - word_end > 8 {
        return None;
    }
    let class = |c: char| c.is_ascii_alphanumeric() || ci_alpha(c) || "._~+/=-".contains(c);
    let end = run(t, w, V, class);
    if end - w < 8 {
        return None;
    }
    Some((end, format!("{} [REDACTED]", s(t, i, word_end))))
}

/// `(?<!\S)(--password|...)(=|\s{1,8})(\S{1,1400})` -> `\1\2[REDACTED]`.
fn m_flag_value(t: &[char], i: usize) -> Option<(usize, String)> {
    if !no_nonspace_before(t, i) {
        return None;
    }
    let flag = [
        "--password",
        "--passwd",
        "--token",
        "--secret",
        "--api-key",
        "--apikey",
        "--auth-token",
        "--access-token",
        "--client-secret",
    ]
    .iter()
    .find(|f| starts_at(t, i, f))?;
    let fe = i + flag.len();
    let g2_end = if t.get(fe) == Some(&'=') {
        fe + 1
    } else {
        let w = run(t, fe, usize::MAX, ws);
        if w == fe || w - fe > 8 {
            return None;
        }
        w
    };
    let end = run(t, g2_end, V, |c| !is_space(c));
    if end == g2_end {
        return None;
    }
    Some((end, format!("{}[REDACTED]", s(t, i, g2_end))))
}

/// `\w{0,8}\b` right after "rint" at k (inside a lookahead).
fn rint_tail(t: &[char], k: usize) -> bool {
    let e = run(t, k, usize::MAX, is_word);
    e - k <= 8
}

/// `(?<!\S)-p(?!(?:rint\w{0,8}|rune|erm|ath|ipe|lain|retty|aginate|ush|ull)\b)(?!\d{1,2}\b)([^\s-]\S{0,1400})`.
fn m_dash_p(t: &[char], i: usize) -> Option<(usize, String)> {
    if !no_nonspace_before(t, i) || !starts_at(t, i, "-p") {
        return None;
    }
    let k = i + 2;
    if starts_at(t, k, "rint") && rint_tail(t, k + 4) {
        return None;
    }
    for w in [
        "rune", "erm", "ath", "ipe", "lain", "retty", "aginate", "ush", "ull",
    ] {
        if starts_at(t, k, w) && word_boundary(t, k + w.len()) {
            return None;
        }
    }
    let d = run(t, k, 2, is_decimal);
    if d > k && (word_boundary(t, d) || (d - k == 2 && word_boundary(t, k + 1))) {
        // \d{1,2}\b: two digits then a boundary, or (backtracking) one.
        return None;
    }
    let c = *t.get(k)?;
    if is_space(c) || c == '-' {
        return None;
    }
    let end = run(t, k + 1, V, |c| !is_space(c));
    Some((end, "-p[REDACTED]".to_string()))
}

/// `(?<!\S)(-u|--user)(=|\s{0,8})([^\s:]{1,128}):(\S{1,1400})` -> `\1\2\3:[REDACTED]`.
fn m_user(t: &[char], i: usize) -> Option<(usize, String)> {
    if !no_nonspace_before(t, i) {
        return None;
    }
    let fe = if starts_at(t, i, "-u") {
        i + 2
    } else if starts_at(t, i, "--user") {
        i + 6
    } else {
        return None;
    };
    let rest = |g2_end: usize| -> Option<(usize, String)> {
        let g3_end = run(t, g2_end, usize::MAX, |c| !is_space(c) && c != ':');
        if g3_end == g2_end || g3_end - g2_end > 128 || t.get(g3_end) != Some(&':') {
            return None;
        }
        let end = run(t, g3_end + 1, V, |c| !is_space(c));
        if end == g3_end + 1 {
            return None;
        }
        Some((end, format!("{}:[REDACTED]", s(t, i, g3_end))))
    };
    if t.get(fe) == Some(&'=') {
        if let Some(r) = rest(fe + 1) {
            return Some(r);
        }
    }
    let w = run(t, fe, usize::MAX, ws);
    if w - fe > 8 {
        return None;
    }
    rest(w)
}

/// `(\bsecret\s{1,8}set\b[^\n]{0,256}?(?<!\S)(?:-b|--body)(?:=|\s{1,8}))("[^"]{0,1400}"|'[^']{0,1400}'|\S{1,1400})`.
fn m_secret_body(t: &[char], i: usize) -> Option<(usize, String)> {
    if !word_boundary(t, i) || !starts_at(t, i, "secret") {
        return None;
    }
    let w = run(t, i + 6, usize::MAX, ws);
    if w == i + 6 || w - (i + 6) > 8 || !starts_at(t, w, "set") || !word_boundary(t, w + 3) {
        return None;
    }
    let base = w + 3;
    let value = |g: usize| -> Option<usize> {
        for q in ['"', '\''] {
            if t.get(g) == Some(&q) {
                let close = run(t, g + 1, V, |c| c != q);
                if t.get(close) == Some(&q) {
                    return Some(close + 1);
                }
            }
        }
        let end = run(t, g, V, |c| !is_space(c));
        if end > g {
            Some(end)
        } else {
            None
        }
    };
    for k in 0..=256 {
        let x = base + k;
        if k > 0 && t.get(x - 1).map_or(true, |&c| c == '\n') {
            break; // [^\n] cannot cross a newline (or the end)
        }
        if !no_nonspace_before(t, x) {
            continue;
        }
        let fe = if starts_at(t, x, "-b") {
            x + 2
        } else if starts_at(t, x, "--body") {
            x + 6
        } else {
            continue;
        };
        if t.get(fe) == Some(&'=') {
            if let Some(end) = value(fe + 1) {
                return Some((end, format!("{}[REDACTED]", s(t, i, fe + 1))));
            }
        }
        let ww = run(t, fe, usize::MAX, ws);
        if ww > fe && ww - fe <= 8 {
            if let Some(end) = value(ww) {
                return Some((end, format!("{}[REDACTED]", s(t, i, ww))));
            }
        }
    }
    None
}

fn ci_assign_class(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_' || c == '.' || c == '-' || ci_alpha(c)
}

/// `(?i)([A-Za-z0-9_.-]{0,64}(?:token|...|credential)[A-Za-z0-9_.-]{0,64})=(\S{1,1400})` -> `\1=[REDACTED]`.
fn m_assignment(t: &[char], i: usize) -> Option<(usize, String)> {
    let q = run(t, i, usize::MAX, ci_assign_class);
    if q == i || t.get(q) != Some(&'=') {
        return None;
    }
    let words = [
        "token",
        "secret",
        "password",
        "passwd",
        "apikey",
        "api_key",
        "api-key",
        "accesskey",
        "access_key",
        "access-key",
        "credential",
    ];
    let split_ok =
        (0..=64.min(q - i)).any(|a| keyword_at(t, i + a, q, &words).iter().any(|&e| q - e <= 64));
    if !split_ok {
        return None;
    }
    let end = run(t, q + 1, V, |c| !is_space(c));
    if end == q + 1 {
        return None;
    }
    Some((end, format!("{}=[REDACTED]", s(t, i, q))))
}

/// `(?i)\b([a-z][a-z0-9+.-]{0,31}://)[^/\s:@]{1,256}:[^/\s@]{1,1400}@` -> `\1[REDACTED]@`.
fn m_url_userinfo(t: &[char], i: usize) -> Option<(usize, String)> {
    if !word_boundary(t, i) || !t.get(i).map_or(false, |&c| ci_alpha(c)) {
        return None;
    }
    let se = run(t, i + 1, usize::MAX, |c| {
        c.is_ascii_alphanumeric() || ci_alpha(c) || "+.-".contains(c)
    });
    if se - (i + 1) > 31 || !starts_at(t, se, "://") {
        return None;
    }
    let g1_end = se + 3;
    let ue = run(t, g1_end, usize::MAX, |c| {
        c != '/' && !is_space(c) && c != ':' && c != '@'
    });
    if ue == g1_end || ue - g1_end > 256 || t.get(ue) != Some(&':') {
        return None;
    }
    let pe = run(t, ue + 1, usize::MAX, |c| {
        c != '/' && !is_space(c) && c != '@'
    });
    if pe == ue + 1 || pe - (ue + 1) > V || t.get(pe) != Some(&'@') {
        return None;
    }
    Some((pe + 1, format!("{}[REDACTED]@", s(t, i, g1_end))))
}

/// The well-known token shapes.
fn m_token(t: &[char], i: usize) -> Option<(usize, String)> {
    if !word_boundary(t, i) {
        return None;
    }
    let alnum = |c: char| c.is_ascii_alphanumeric();
    let alnum_u = |c: char| c.is_ascii_alphanumeric() || c == '_';
    let alnum_d = |c: char| c.is_ascii_alphanumeric() || c == '-';
    let alnum_ud = |c: char| c.is_ascii_alphanumeric() || c == '_' || c == '-';
    let body = |start: usize, min: usize, max: usize, f: &dyn Fn(char) -> bool| -> Option<usize> {
        let e = run(t, start, max, f);
        if e - start >= min {
            Some(e)
        } else {
            None
        }
    };
    let hit = |end: usize| Some((end, "[REDACTED]".to_string()));
    if starts_at(t, i, "gh")
        && t.get(i + 2).map_or(false, |c| "pousr".contains(*c))
        && t.get(i + 3) == Some(&'_')
    {
        if let Some(e) = body(i + 4, 20, 255, &alnum) {
            return hit(e);
        }
    }
    if starts_at(t, i, "github_pat_") {
        if let Some(e) = body(i + 11, 20, 255, &alnum_u) {
            return hit(e);
        }
    }
    if starts_at(t, i, "xox")
        && t.get(i + 3).map_or(false, |c| "abprs".contains(*c))
        && t.get(i + 4) == Some(&'-')
    {
        if let Some(e) = body(i + 5, 10, 255, &alnum_d) {
            return hit(e);
        }
    }
    if starts_at(t, i, "sk-") {
        if let Some(e) = body(i + 3, 20, 255, &alnum_ud) {
            return hit(e);
        }
    }
    if starts_at(t, i, "AKIA") {
        if let Some(e) = body(i + 4, 16, 16, &|c: char| {
            c.is_ascii_digit() || c.is_ascii_uppercase()
        }) {
            return hit(e);
        }
    }
    if starts_at(t, i, "AIza") {
        if let Some(e) = body(i + 4, 35, 35, &alnum_ud) {
            return hit(e);
        }
    }
    if starts_at(t, i, "glpat-") {
        if let Some(e) = body(i + 6, 20, 255, &alnum_ud) {
            return hit(e);
        }
    }
    None
}

const REDACTIONS: [Matcher; 10] = [
    m_authorization,
    m_header,
    m_bearer,
    m_flag_value,
    m_dash_p,
    m_user,
    m_secret_body,
    m_assignment,
    m_url_userinfo,
    m_token,
];

pub fn redact(text: &str) -> String {
    let mut t: Vec<char> = text.chars().collect();
    for m in REDACTIONS {
        t = sub(&t, m);
    }
    t.into_iter().collect()
}

fn truncate(text: &str, original_len: usize) -> String {
    let n = text.chars().count();
    if n <= LOG_COMMAND_MAX && original_len <= LOG_COMMAND_MAX + 200 {
        return text.to_string();
    }
    let head: String = text.chars().take(LOG_COMMAND_MAX).collect();
    format!("{}...[truncated, {} characters]", head, original_len)
}

/// Redact, then cut to LOG_COMMAND_MAX. Only the head is ever scanned.
pub fn redact_for_log(text: &str) -> String {
    let head: String = text.chars().take(LOG_COMMAND_MAX + 200).collect();
    truncate(&redact(&head), text.chars().count())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redacts() {
        for (text, secret) in [
            ("mysql -phunter2 db", "hunter2"), // gitleaks:allow
            ("psql postgres://app:s3cr3t@db:5432/x", "s3cr3t"), // gitleaks:allow
            ("curl -u admin:adm1npass https://x", "adm1npass"), // gitleaks:allow
            ("gh secret set FOO -b 'two words'", "two words"),
            (
                "gh secret set FOO --body=\"quoted value\" -R x/y",
                "quoted value",
            ),
            ("curl -H 'X-Api-Key: k3yvalue' https://x", "k3yvalue"), // gitleaks:allow
            (
                "curl -H 'Authorization: Bearer sekrit-value-123' https://x", // gitleaks:allow
                "sekrit-value-123",                                           // gitleaks:allow
            ),
            (
                "GH_TOKEN=ghs_abcdefghijklmnopqrstuvwxyz0123 gh pr list", // gitleaks:allow
                "ghs_abcdefghijklmnopqrstuvwxyz0123",                     // gitleaks:allow
            ),
            ("vault login --token s.abcdef", "s.abcdef"),
        ] {
            let out = redact(text);
            assert!(!out.contains(secret), "{} -> {}", text, out);
            assert!(out.contains("[REDACTED]"), "{}", text);
        }
    }

    #[test]
    fn leaves_ordinary_commands_alone() {
        for text in [
            "git log -p 5",
            "git log -p -5",
            "patch -p1 < x.diff",
            "find . -print",
            "find . -path ./x -prune",
            "sudo -u james ls",
            "mkdir -p a/b",
            "gh secret list",
            "ssh -p 2222 host",
        ] {
            assert_eq!(redact(text), text);
        }
    }
}
