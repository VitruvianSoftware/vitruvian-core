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

//! pulumi-summary — render a markdown digest of a `pulumi up`/`pulumi preview`
//! run so foundation CI surfaces the deploy signal on the Actions run page
//! ($GITHUB_STEP_SUMMARY) and, for previews, in the sticky PR comment.

use shell_compat::{cat, env, env_or, err, out};

struct Counts {
    created: i64,
    updated: i64,
    replaced: i64,
    deleted: i64,
    unchanged: i64,
    errored: i64,
}

struct ResRow {
    rank: i32,
    action: Vec<u8>,
    rtype: Vec<u8>,
    name: Vec<u8>,
}

fn parse_num(s: &[u8]) -> i64 {
    std::str::from_utf8(s)
        .ok()
        .and_then(|v| v.trim().parse().ok())
        .unwrap_or(0)
}

/// The script's `sed -E -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' -e 's/<\{%[^%]*%\}>//g'
/// -e 's/\r$//'`: applied line by line, each expression in turn. So an escape
/// only goes when it is ESC `[` digits/semicolons and a letter (`ESC[?25l`
/// stays), a colour directive has no `%` inside, and only a line's LAST `\r`
/// goes. Nothing spans a newline.
fn strip_ansi_and_color(raw: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(raw.len());
    let mut lines = raw.split(|&c| c == b'\n').peekable();
    while let Some(line) = lines.next() {
        let a = strip_csi(line);
        let b = strip_directives(&a);
        let c = match b.last() {
            Some(b'\r') => &b[..b.len() - 1],
            _ => &b[..],
        };
        out.extend_from_slice(c);
        if lines.peek().is_some() {
            out.push(b'\n');
        }
    }
    out
}

/// `s/\x1b\[[0-9;]*[a-zA-Z]//g` on one line.
fn strip_csi(line: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(line.len());
    let mut i = 0;
    while i < line.len() {
        if line[i] == 0x1b && line.get(i + 1) == Some(&b'[') {
            let mut j = i + 2;
            while j < line.len() && (line[j].is_ascii_digit() || line[j] == b';') {
                j += 1;
            }
            if j < line.len() && line[j].is_ascii_alphabetic() {
                i = j + 1;
                continue;
            }
        }
        out.push(line[i]);
        i += 1;
    }
    out
}

/// `s/<\{%[^%]*%\}>//g` on one line.
fn strip_directives(line: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(line.len());
    let mut i = 0;
    while i < line.len() {
        if line[i..].starts_with(b"<{%") {
            let mut j = i + 3;
            while j < line.len() && line[j] != b'%' {
                j += 1;
            }
            if line[j..].starts_with(b"%}>") {
                i = j + 3;
                continue;
            }
        }
        out.push(line[i]);
        i += 1;
    }
    out
}

fn find_seq(hay: &[u8], needle: &[u8]) -> Option<usize> {
    hay.windows(needle.len()).position(|w| w == needle)
}

/// awk's `num()`: the leftmost `<digits> <keyword>` on the line (exactly one
/// space), its digits read as `%d`. `5  created` (two spaces) and
/// `2 recreated` do not count.
fn extract_num(line: &[u8], keywords: &[&[u8]]) -> Option<i64> {
    let mut i = 0;
    while i < line.len() {
        if !line[i].is_ascii_digit() {
            i += 1;
            continue;
        }
        let mut j = i;
        while j < line.len() && line[j].is_ascii_digit() {
            j += 1;
        }
        if line.get(j) == Some(&b' ') {
            let rest = &line[j + 1..];
            if keywords.iter().any(|kw| rest.starts_with(kw)) {
                return Some(parse_num(&line[i..j]));
            }
        }
        i += 1;
    }
    None
}

/// `sub(/^[ \t]*[-+~]*[ \t]*/, "", t)`: blanks, then markers, then blanks,
/// once (so `" + - x"` keeps `- x`).
fn trim_leading_markers(s: &[u8]) -> Vec<u8> {
    let mut i = 0;
    while i < s.len() && (s[i] == b' ' || s[i] == b'\t') {
        i += 1;
    }
    while i < s.len() && matches!(s[i], b'-' | b'+' | b'~') {
        i += 1;
    }
    while i < s.len() && (s[i] == b' ' || s[i] == b'\t') {
        i += 1;
    }
    s[i..].to_vec()
}

/// Trailing spaces and tabs only, as the awk header regex's `[ \t]*$`.
fn trim_blank_end(s: &[u8]) -> &[u8] {
    let mut end = s.len();
    while end > 0 && (s[end - 1] == b' ' || s[end - 1] == b'\t') {
        end -= 1;
    }
    &s[..end]
}

/// awk: `u = L[j]; sub(/^.*::/, "", u); sub(/\].*$/, "", u)`: after the line's
/// LAST `::`, up to the first `]`. A name holding a single `:` survives whole.
fn urn_name(line: &[u8]) -> Vec<u8> {
    let after = match line.windows(2).rposition(|w| w == b"::") {
        Some(p) => &line[p + 2..],
        None => line,
    };
    let end = after.iter().position(|&c| c == b']').unwrap_or(after.len());
    after[..end].to_vec()
}

fn cell_escape(s: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(s.len());
    for &c in s {
        if c == b'|' {
            out.extend_from_slice(b"\\|");
        } else {
            out.push(c);
        }
    }
    out
}

fn parse_clean(clean_lines: &[Vec<u8>]) -> (Counts, Vec<ResRow>, Vec<Vec<u8>>, Vec<u8>, Vec<u8>) {
    let n = clean_lines.len();
    let mut start = 0usize;
    let mut op = Vec::new();
    let mut stack = Vec::new();

    for i in 0..n {
        let line = &clean_lines[i];
        if line.starts_with(b"Updating (") {
            start = i;
            op = b"up".to_vec();
            stack = paren(line);
        } else if line.starts_with(b"Previewing update (") {
            start = i;
            op = b"preview".to_vec();
            stack = paren(line);
        }
    }

    let mut counts = Counts {
        created: 0,
        updated: 0,
        replaced: 0,
        deleted: 0,
        unchanged: 0,
        errored: 0,
    };
    let mut in_resources = false;
    for i in start..n {
        let line = &clean_lines[i];
        if line.starts_with(b"Resources:") {
            in_resources = true;
            continue;
        }
        if in_resources {
            if line.iter().all(|&c| c == b' ' || c == b'\t') || line.starts_with(b"Duration:") {
                in_resources = false;
                continue;
            }
            if let Some(v) = extract_num(line, &[b"created", b"to create"]) {
                counts.created = v;
            }
            if let Some(v) = extract_num(line, &[b"updated", b"to update"]) {
                counts.updated = v;
            }
            if let Some(v) = extract_num(line, &[b"replaced", b"to replace"]) {
                counts.replaced = v;
            }
            if let Some(v) = extract_num(line, &[b"deleted", b"to delete"]) {
                counts.deleted = v;
            }
            if let Some(v) = extract_num(line, &[b"unchanged"]) {
                counts.unchanged = v;
            }
            if let Some(v) = extract_num(line, &[b"errored"]) {
                counts.errored = v;
            }
        }
    }

    let hdr_suffixes: &[&[u8]] = &[b": (create)", b": (update)", b": (delete)", b": (replace)"];

    let mut rows = Vec::new();
    for i in start..n {
        let line = &clean_lines[i];
        let trimmed = trim_blank_end(line);
        let mut action = None;
        for &suffix in hdr_suffixes {
            if trimmed.ends_with(suffix) {
                let a = &suffix[3..suffix.len() - 1];
                action = Some(a.to_vec());
                break;
            }
        }
        let action = match action {
            Some(a) => a,
            None => continue,
        };

        let before_suffix_len = trimmed.len().saturating_sub(action.len() + 4);
        let type_part = &trimmed[..before_suffix_len];
        let rtype = trim_leading_markers(type_part);

        let mut name = Vec::new();
        for j in (i + 1)..std::cmp::min(i + 9, n) {
            let jline = &clean_lines[j];
            if find_seq(jline, b"[urn=").is_some() {
                name = urn_name(jline);
                break;
            }
            let jt = trim_blank_end(jline);
            if hdr_suffixes.iter().any(|s| jt.ends_with(s)) {
                break;
            }
        }

        let rank = match action.as_slice() {
            b"delete" => 0,
            b"replace" => 1,
            b"update" => 2,
            b"create" => 3,
            _ => 4,
        };
        rows.push(ResRow {
            rank,
            action,
            rtype,
            name,
        });
    }

    rows.sort_by_key(|r| r.rank);

    let mut errors = Vec::new();
    for i in 0..n {
        let line = &clean_lines[i];
        if (line.starts_with(b"error:") || line.starts_with(b"Error:")) && errors.len() < 20 {
            // The script carried these as `ERR\t<line>` and read back field
            // 2 with awk -F'\t', so a tab ends the line.
            let cut = line.iter().position(|&c| c == b'\t').unwrap_or(line.len());
            errors.push(line[..cut].to_vec());
        }
    }

    (counts, rows, errors, op, stack)
}

/// awk's `paren()`: after the first `(`, up to the first `)` (or the end).
fn paren(line: &[u8]) -> Vec<u8> {
    let Some(open) = line.iter().position(|&c| c == b'(') else {
        return line.to_vec();
    };
    let rest = &line[open + 1..];
    let close = rest.iter().position(|&c| c == b')').unwrap_or(rest.len());
    rest[..close].to_vec()
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    // Like the script: all three must be present AND non-empty.
    if _args.len() < 3 || _args[..3].iter().any(|a| a.is_empty()) {
        err(b"usage: pulumi-summary <phase-label> <pulumi-output-file> <exit-code>\n");
        return 2;
    }
    let label = &_args[0];
    let out_file = &_args[1];
    // `[[ "$EXIT_CODE" =~ ^[0-9]+$ ]] || EXIT_CODE=1`: anything but plain
    // digits (`-1`, `+0`, ` 0`, `abc`) is a failure, and the digits are shown
    // as given (`007` stays `007`). Success is a value equal to zero.
    let exit_code: Vec<u8> = if _args[2].iter().all(|c| c.is_ascii_digit()) {
        _args[2].clone()
    } else {
        b"1".to_vec()
    };
    let succeeded = exit_code.iter().all(|&c| c == b'0');

    let raw_max: usize = std::str::from_utf8(&env_or("PULUMI_SUMMARY_RAW_MAX", b"40000"))
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(40000);
    let row_max: usize = std::str::from_utf8(&env_or("PULUMI_SUMMARY_ROW_MAX", b"100"))
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(100);
    let comment_limit: usize =
        std::str::from_utf8(&env_or("PULUMI_SUMMARY_COMMENT_LIMIT", b"63000"))
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(63000);

    let raw_bytes = if shell_compat::is_file(out_file) {
        std::fs::read(shell_compat::path(out_file)).unwrap_or_default()
    } else {
        Vec::new()
    };
    let clean = strip_ansi_and_color(&raw_bytes);
    let clean_lines: Vec<Vec<u8>> = if clean.is_empty() {
        Vec::new()
    } else {
        // awk's records: a final newline ends the last line, it does not
        // start an empty one.
        let body = clean.strip_suffix(b"\n").unwrap_or(&clean);
        body.split(|&c| c == b'\n').map(|l| l.to_vec()).collect()
    };

    let (counts, rows, errors, op, stack) = parse_clean(&clean_lines);

    if let Some(gh_output) = env("GITHUB_OUTPUT") {
        if !gh_output.is_empty() {
            let destructive = counts.deleted + counts.replaced;
            let data = cat(&[
                b"created=",
                itoa(counts.created).as_bytes(),
                b"\nupdated=",
                itoa(counts.updated).as_bytes(),
                b"\nreplaced=",
                itoa(counts.replaced).as_bytes(),
                b"\ndeleted=",
                itoa(counts.deleted).as_bytes(),
                b"\nunchanged=",
                itoa(counts.unchanged).as_bytes(),
                b"\nerrored=",
                itoa(counts.errored).as_bytes(),
                b"\ndestructive=",
                itoa(destructive).as_bytes(),
                b"\n",
            ]);
            let _ = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(shell_compat::path(&gh_output))
                .and_then(|mut f| {
                    use std::io::Write;
                    f.write_all(&data)
                });
        }
    }

    let op_display = match op.as_slice() {
        b"up" => b"pulumi up" as &[u8],
        b"preview" => b"pulumi preview",
        _ => b"pulumi",
    };

    let mut head = render_head(
        label, op_display, &stack, &exit_code, succeeded, &counts, &rows, &errors, row_max,
    );
    // HEAD="$(render_head)" drops the trailing newlines before both the
    // print and the byte count the log budget is cut from.
    while head.last() == Some(&b'\n') {
        head.pop();
    }
    out(&head);
    out(b"\n\n");

    let head_bytes = head.len();
    let raw_allow = {
        let budget = comment_limit.saturating_sub(head_bytes).saturating_sub(200);
        if budget > raw_max {
            raw_max
        } else {
            budget
        }
    };

    out(b"<details>\n<summary>\xf0\x9f\x93\x9c Full pulumi log</summary>\n\n");
    out(b"```text\n");
    let clean_size = clean.len();
    if clean_size == 0 {
        out(b"(no pulumi output captured)\n");
    } else if raw_allow == 0 {
        out(b"(log omitted \xe2\x80\x94 digest is at the comment size limit; see the raw job output)\n");
    } else if clean_size > raw_allow {
        out(&cat(&[
            b"\xe2\x80\xa6 log truncated to last ",
            itoa(raw_allow as i64).as_bytes(),
            b" bytes (full log in the raw job output) \xe2\x80\xa6\n\n",
        ]));
        out(&clean[clean_size - raw_allow..]);
    } else {
        out(&clean);
    }
    out(b"\n```\n\n</details>\n");

    0
}

fn itoa(v: i64) -> String {
    v.to_string()
}

fn render_head(
    label: &[u8],
    op_display: &[u8],
    stack: &[u8],
    exit_code: &[u8],
    succeeded: bool,
    counts: &Counts,
    rows: &[ResRow],
    errors: &[Vec<u8>],
    row_max: usize,
) -> Vec<u8> {
    let mut buf = Vec::new();

    // Title
    buf.extend_from_slice(b"## \xf0\x9f\x8f\x97\xef\xb8\x8f ");
    buf.extend_from_slice(label);
    buf.extend_from_slice(b" \xc2\xb7 ");
    buf.extend_from_slice(op_display);
    if !stack.is_empty() {
        buf.extend_from_slice(b" \xc2\xb7 ");
        buf.extend_from_slice(stack);
    }
    if succeeded {
        buf.extend_from_slice(b" \xc2\xb7 \xe2\x9c\x85 Succeeded");
    } else {
        buf.extend_from_slice(b" \xc2\xb7 \xe2\x9d\x8c Failed");
    }
    buf.extend_from_slice(b"\n\n");

    // Error block on failure
    if !succeeded {
        if counts.errored > 0 {
            buf.extend_from_slice(b"> \xe2\x9d\x8c **");
            buf.extend_from_slice(op_display);
            buf.extend_from_slice(b" failed** (exit ");
            buf.extend_from_slice(exit_code);
            buf.extend_from_slice(b") \xc2\xb7 \xf0\x9f\x92\xa5 ");
            buf.extend_from_slice(itoa(counts.errored).as_bytes());
            buf.extend_from_slice(b" errored\n\n");
        } else {
            buf.extend_from_slice(b"> \xe2\x9d\x8c **");
            buf.extend_from_slice(op_display);
            buf.extend_from_slice(b" failed** (exit ");
            buf.extend_from_slice(exit_code);
            buf.extend_from_slice(b")\n\n");
        }
        if !errors.is_empty() {
            buf.extend_from_slice(b"```text\n");
            for e in errors {
                buf.extend_from_slice(e);
                buf.push(b'\n');
            }
            buf.extend_from_slice(b"```\n\n");
        } else {
            buf.extend_from_slice(
                b"_No `error:` line was captured \xe2\x80\x94 see the full log below._\n\n",
            );
        }
    }

    // Counts table
    buf.extend_from_slice(b"### Resource changes\n\n");
    buf.extend_from_slice(
        b"| \xe2\x9e\x95 Created | \xf0\x9f\x94\x84 Updated | \xe2\x99\xbb\xef\xb8\x8f Replaced | \xe2\x9e\x96 Deleted | \xe2\x9a\xaa Unchanged |\n",
    );
    buf.extend_from_slice(b"| --: | --: | --: | --: | --: |\n");
    buf.extend_from_slice(b"| ");
    buf.extend_from_slice(itoa(counts.created).as_bytes());
    buf.extend_from_slice(b" | ");
    buf.extend_from_slice(itoa(counts.updated).as_bytes());
    buf.extend_from_slice(b" | ");
    buf.extend_from_slice(itoa(counts.replaced).as_bytes());
    buf.extend_from_slice(b" | ");
    buf.extend_from_slice(itoa(counts.deleted).as_bytes());
    buf.extend_from_slice(b" | ");
    buf.extend_from_slice(itoa(counts.unchanged).as_bytes());
    buf.extend_from_slice(b" |\n\n");

    // Risk callout
    let destructive = counts.deleted + counts.replaced;
    if destructive > 0 {
        buf.extend_from_slice(b"> \xe2\x9a\xa0\xef\xb8\x8f **");
        buf.extend_from_slice(itoa(counts.deleted).as_bytes());
        buf.extend_from_slice(b" deleted, ");
        buf.extend_from_slice(itoa(counts.replaced).as_bytes());
        buf.extend_from_slice(
            b" replaced** \xe2\x80\x94 destructive operations are listed first below.\n\n",
        );
    } else {
        buf.extend_from_slice(b"> \xe2\x9c\x85 No replaces or deletes.\n\n");
    }

    // Per-resource table
    let row_total = rows.len();
    buf.extend_from_slice(b"### Resources\n\n");
    if row_total == 0 {
        buf.extend_from_slice(b"_No resource-level changes._\n\n");
    } else {
        buf.extend_from_slice(b"| Action | Type | Name |\n");
        buf.extend_from_slice(b"| :-- | :-- | :-- |\n");
        let mut shown = 0;
        for row in rows {
            if row.action.is_empty() {
                continue;
            }
            shown += 1;
            if shown > row_max {
                break;
            }
            let (emoji, lbl): (&[u8], &[u8]) = match row.action.as_slice() {
                b"create" => (b"\xe2\x9e\x95", &b"Created"[..]),
                b"update" => (b"\xf0\x9f\x94\x84", &b"Updated"[..]),
                b"replace" => (b"\xe2\x99\xbb\xef\xb8\x8f", &b"Replaced"[..]),
                b"delete" => (b"\xe2\x9e\x96", &b"Deleted"[..]),
                _ => (b"\xe2\x80\xa2", row.action.as_slice()),
            };
            let tcell_inner = cell_escape(&row.rtype);
            let ncell = cell_escape(&row.name);
            let is_destructive =
                row.action.as_slice() == b"delete" || row.action.as_slice() == b"replace";
            buf.extend_from_slice(b"| ");
            buf.extend_from_slice(emoji);
            buf.push(b' ');
            if is_destructive {
                buf.extend_from_slice(b"**");
                buf.extend_from_slice(lbl);
                buf.extend_from_slice(b"**");
            } else {
                buf.extend_from_slice(lbl);
            }
            buf.extend_from_slice(b" | `");
            buf.extend_from_slice(&tcell_inner);
            buf.extend_from_slice(b"` | ");
            if is_destructive {
                buf.extend_from_slice(b"**");
                buf.extend_from_slice(&ncell);
                buf.extend_from_slice(b"**");
            } else {
                buf.extend_from_slice(&ncell);
            }
            buf.extend_from_slice(b" |\n");
        }
        if row_total > row_max {
            let remaining = row_total - row_max;
            buf.extend_from_slice(b"\n_\xe2\x80\xa6 and ");
            buf.extend_from_slice(itoa(remaining as i64).as_bytes());
            buf.extend_from_slice(
                b" more (destructive ops shown first; full detail in the log below)._\n",
            );
        }
        buf.push(b'\n');
    }

    buf
}
