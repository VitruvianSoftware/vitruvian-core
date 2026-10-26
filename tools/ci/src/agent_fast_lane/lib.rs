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

//! agent-fast-lane.sh — decide whether a PR may skip the heavy test jobs.

use shell_compat::{cat, env, env_or_empty, err, out};

const LABEL: &[u8] = b"agent-fast-lane";

fn emit(line: &[u8]) {
    out(line);
    out(b"\n");
    if let Some(gh_output) = env("GITHUB_OUTPUT") {
        if !gh_output.is_empty() {
            let _ = std::fs::OpenOptions::new()
                .append(true)
                .create(true)
                .open(shell_compat::path(&gh_output))
                .and_then(|mut f| {
                    use std::io::Write;
                    f.write_all(line)?;
                    f.write_all(b"\n")
                });
        }
    }
}

fn finish(verdict: &[u8], reason: &[u8]) -> i32 {
    emit(&cat(&[b"verdict=", verdict]));
    emit(&cat(&[b"reason=", reason]));
    err(&cat(&[b"agent-fast-lane: ", verdict, b": ", reason, b"\n"]));
    0
}

fn parse_json_string_array(input: &[u8]) -> Option<Vec<Vec<u8>>> {
    let s = std::str::from_utf8(input).ok()?;
    let s = s.trim();
    if !s.starts_with('[') || !s.ends_with(']') {
        return None;
    }
    let inner = s[1..s.len() - 1].trim();
    if inner.is_empty() {
        return Some(Vec::new());
    }
    let mut result = Vec::new();
    for item in inner.split(',') {
        let trimmed = item.trim();
        if trimmed.is_empty() {
            continue;
        }
        if !trimmed.starts_with('"') || !trimmed.ends_with('"') || trimmed.len() < 2 {
            return None;
        }
        result.push(trimmed[1..trimmed.len() - 1].as_bytes().to_vec());
    }
    Some(result)
}

fn lookup_agent(roster_path: &[u8], id: &[u8]) -> Result<Option<Vec<u8>>, ()> {
    let content = match std::fs::read(shell_compat::path(roster_path)) {
        Ok(c) => c,
        Err(_) => return Err(()),
    };
    for line in shell_compat::lines(&content) {
        if line.starts_with(b"#") || line.is_empty() {
            continue;
        }
        let fields: Vec<&[u8]> = line.splitn(5, |&c| c == b'\t').collect();
        if fields.len() >= 4 && fields[3] == id {
            return Ok(Some(fields[0].to_vec()));
        }
    }
    Ok(None)
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let event_name = env_or_empty("EVENT_NAME");
    if event_name != b"pull_request" {
        return finish(b"full", b"not a pull request");
    }

    let repo = match env("GITHUB_REPOSITORY") {
        Some(v) if !v.is_empty() => v,
        _ => return finish(b"full", b"GITHUB_REPOSITORY is not set"),
    };

    let head_repo = env_or_empty("PR_HEAD_REPO");
    if head_repo != repo {
        return finish(
            b"full",
            &cat(&[b"the branch is not in ", &repo, b" (a fork?)"]),
        );
    }

    let labels_raw = env_or_empty("PR_LABELS");
    let labels = match parse_json_string_array(&labels_raw) {
        Some(l) => l,
        None => return finish(b"full", b"could not read the label list"),
    };
    if !labels.iter().any(|l| l == LABEL) {
        return finish(b"full", b"no agent-fast-lane label");
    }

    let author_type = env_or_empty("PR_AUTHOR_TYPE");
    if author_type != b"Bot" {
        return finish(b"full", b"opened by a person, not an agent app");
    }

    let id = env_or_empty("PR_AUTHOR_ID");
    if id.is_empty() || !id.iter().all(|&c| c.is_ascii_digit()) {
        return finish(b"full", b"no author id");
    }

    let roster = env_or_empty("AGENTS_TSV");
    if !shell_compat::is_file(&roster) {
        return finish(b"full", b"agent roster not found");
    }

    let agent = match lookup_agent(&roster, &id) {
        Err(()) => return finish(b"full", b"could not read the agent roster"),
        Ok(None) => {
            return finish(
                b"full",
                &cat(&[b"author ", &id, b" is not one of the agent apps"]),
            )
        }
        Ok(Some(name)) => name,
    };

    finish(
        b"fast",
        &cat(&[
            b"opened by the ",
            &agent,
            b" agent app from a branch in ",
            &repo,
            b", with the ",
            LABEL,
            b" label",
        ]),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_json_empty_array() {
        let r = parse_json_string_array(b"[]").unwrap();
        assert!(r.is_empty());
    }

    #[test]
    fn parse_json_single_element() {
        let r = parse_json_string_array(b"[\"hello\"]").unwrap();
        assert_eq!(r, vec![b"hello".to_vec()]);
    }

    #[test]
    fn parse_json_multiple_elements() {
        let r = parse_json_string_array(b"[\"ci\",\"agent-fast-lane\"]").unwrap();
        assert_eq!(r, vec![b"ci".to_vec(), b"agent-fast-lane".to_vec()]);
    }

    #[test]
    fn parse_json_with_spaces() {
        let r = parse_json_string_array(b"[ \"a\" , \"b\" ]").unwrap();
        assert_eq!(r, vec![b"a".to_vec(), b"b".to_vec()]);
    }

    #[test]
    fn parse_json_not_array() {
        assert!(parse_json_string_array(b"\"agent-fast-lane\"").is_none());
    }

    #[test]
    fn parse_json_not_json() {
        assert!(parse_json_string_array(b"not json").is_none());
    }

    #[test]
    fn parse_json_empty_string() {
        assert!(parse_json_string_array(b"").is_none());
    }

    #[test]
    fn parse_json_number_element() {
        assert!(parse_json_string_array(b"[42]").is_none());
    }

    #[test]
    fn lookup_agent_finds_match() {
        let dir = shell_compat::mktemp_dir().unwrap();
        let tsv_path = shell_compat::cat(&[&dir, b"/agents.tsv"]);
        let content = b"# agent\tapp_id\tinstallation_id\tbot_user_id\nwren\t100\t200\t300\natlas\t101\t201\t301\n";
        shell_compat::write_file(&tsv_path, content, 0o644).unwrap();
        let r = lookup_agent(&tsv_path, b"301").unwrap();
        assert_eq!(r, Some(b"atlas".to_vec()));
        let _ = std::fs::remove_dir_all(shell_compat::path(&dir));
    }

    #[test]
    fn lookup_agent_no_match() {
        let dir = shell_compat::mktemp_dir().unwrap();
        let tsv_path = shell_compat::cat(&[&dir, b"/agents.tsv"]);
        let content = b"wren\t100\t200\t300\n";
        shell_compat::write_file(&tsv_path, content, 0o644).unwrap();
        let r = lookup_agent(&tsv_path, b"999").unwrap();
        assert_eq!(r, None);
        let _ = std::fs::remove_dir_all(shell_compat::path(&dir));
    }

    #[test]
    fn lookup_agent_skips_comments() {
        let dir = shell_compat::mktemp_dir().unwrap();
        let tsv_path = shell_compat::cat(&[&dir, b"/agents.tsv"]);
        let content = b"# agent\tapp_id\tinstallation_id\tbot_user_id\n#wren\t100\t200\t300\n";
        shell_compat::write_file(&tsv_path, content, 0o644).unwrap();
        let r = lookup_agent(&tsv_path, b"300").unwrap();
        assert_eq!(r, None);
        let _ = std::fs::remove_dir_all(shell_compat::path(&dir));
    }

    #[test]
    fn lookup_agent_missing_file() {
        let r = lookup_agent(b"/no/such/file", b"300");
        assert!(r.is_err());
    }
}
