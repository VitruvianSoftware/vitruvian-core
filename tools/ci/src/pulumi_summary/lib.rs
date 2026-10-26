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

//! pulumi-summary.sh — render a markdown digest of a `pulumi up`/`pulumi preview`
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

fn strip_ansi_and_color(raw: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(raw.len());
    let mut i = 0;
    while i < raw.len() {
        if raw[i] == 0x1b && i + 1 < raw.len() && raw[i + 1] == b'[' {
            i += 2;
            while i < raw.len() {
                let c = raw[i];
                i += 1;
                if c.is_ascii_alphabetic() {
                    break;
                }
            }
            continue;
        }
        if raw[i] == b'<' && i + 2 < raw.len() && raw[i + 1] == b'{' && raw[i + 2] == b'%' {
            if let Some(end) = find_seq(&raw[i..], b"%}>") {
                i += end + 3;
                continue;
            }
        }
        if raw[i] == b'\r' {
            i += 1;
            continue;
        }
        out.push(raw[i]);
        i += 1;
    }
    out
}

fn trim_ascii_end_slice(s: &[u8]) -> &[u8] {
    let mut end = s.len();
    while end > 0 && s[end - 1].is_ascii_whitespace() {
        end -= 1;
    }
    &s[..end]
}

fn trim_ascii_slice(s: &[u8]) -> &[u8] {
    let s = trim_ascii_end_slice(s);
    let mut start = 0;
    while start < s.len() && s[start].is_ascii_whitespace() {
        start += 1;
    }
    &s[start..]
}

fn find_seq(hay: &[u8], needle: &[u8]) -> Option<usize> {
    hay.windows(needle.len()).position(|w| w == needle)
}

fn extract_num(line: &[u8], keywords: &[&[u8]]) -> Option<i64> {
    for kw in keywords {
        if let Some(pos) = find_seq(line, kw) {
            let before = &line[..pos];
            let before = trim_ascii_end_slice(before);
            let start = before
                .iter()
                .rposition(|&c| !c.is_ascii_digit())
                .map(|p| p + 1)
                .unwrap_or(0);
            let num_bytes = &before[start..];
            if !num_bytes.is_empty() {
                return Some(parse_num(num_bytes));
            }
        }
    }
    None
}

fn trim_leading_markers(s: &[u8]) -> Vec<u8> {
    let mut i = 0;
    while i < s.len() {
        match s[i] {
            b' ' | b'\t' | b'-' | b'+' | b'~' => i += 1,
            _ => break,
        }
    }
    s[i..].to_vec()
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
            let trimmed = trim_ascii_slice(line);
            if trimmed.is_empty() || line.starts_with(b"Duration:") {
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
        let trimmed = trim_ascii_end_slice(line);
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

        let before_suffix_len = trim_ascii_end_slice(line)
            .len()
            .saturating_sub(action.len() + 4);
        let type_part = &trim_ascii_end_slice(line)[..before_suffix_len];
        let rtype = trim_leading_markers(type_part);

        let mut name = Vec::new();
        for j in (i + 1)..std::cmp::min(i + 9, n) {
            let jline = &clean_lines[j];
            if find_seq(jline, b"[urn=").is_some() {
                let urn_start = find_seq(jline, b"[urn=").unwrap();
                let urn_data = &jline[urn_start + 5..];
                let urn_end = urn_data
                    .iter()
                    .position(|&c| c == b']')
                    .unwrap_or(urn_data.len());
                let urn = &urn_data[..urn_end];
                if let Some(last_sep) = urn.iter().rposition(|&c| c == b':') {
                    name = urn[last_sep + 1..].to_vec();
                }
                break;
            }
            let jt = trim_ascii_end_slice(jline);
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
            errors.push(line.clone());
        }
    }

    (counts, rows, errors, op, stack)
}

fn paren(line: &[u8]) -> Vec<u8> {
    if let Some(open) = line.iter().position(|&c| c == b'(') {
        if let Some(close) = line[open..].iter().position(|&c| c == b')') {
            return line[open + 1..open + close].to_vec();
        }
    }
    Vec::new()
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    if _args.len() < 3 {
        err(b"usage: pulumi-summary <phase-label> <pulumi-output-file> <exit-code>\n");
        return 2;
    }
    let label = &_args[0];
    let out_file = &_args[1];
    let exit_code_s = &_args[2];

    let exit_code: i64 = std::str::from_utf8(exit_code_s)
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(1);

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
        clean.split(|&c| c == b'\n').map(|l| l.to_vec()).collect()
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

    let head = render_head(
        label, op_display, &stack, exit_code, &counts, &rows, &errors, row_max,
    );
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
    exit_code: i64,
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
    if exit_code == 0 {
        buf.extend_from_slice(b" \xc2\xb7 \xe2\x9c\x85 Succeeded");
    } else {
        buf.extend_from_slice(b" \xc2\xb7 \xe2\x9d\x8c Failed");
    }
    buf.extend_from_slice(b"\n\n");

    // Error block on failure
    if exit_code != 0 {
        if counts.errored > 0 {
            buf.extend_from_slice(b"> \xe2\x9d\x8c **");
            buf.extend_from_slice(op_display);
            buf.extend_from_slice(b" failed** (exit ");
            buf.extend_from_slice(itoa(exit_code).as_bytes());
            buf.extend_from_slice(b") \xc2\xb7 \xf0\x9f\x92\xa5 ");
            buf.extend_from_slice(itoa(counts.errored).as_bytes());
            buf.extend_from_slice(b" errored\n\n");
        } else {
            buf.extend_from_slice(b"> \xe2\x9d\x8c **");
            buf.extend_from_slice(op_display);
            buf.extend_from_slice(b" failed** (exit ");
            buf.extend_from_slice(itoa(exit_code).as_bytes());
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
