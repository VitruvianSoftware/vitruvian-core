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

//! profiles.tsv: one row per profile, whitespace-separated
//! `profile tools sa_account sa_project secrets purpose...`. Comment rows
//! (first field starts with `#`) and blank rows are skipped; the trailing
//! purpose may contain spaces and is rejoined with single spaces, exactly as
//! the awk the shell version used.

use std::fs;
use std::path::Path;

#[derive(Clone, Debug, Default)]
pub struct Profile {
    pub tools: String,
    pub sa_account: String,
    pub sa_project: String,
    pub secrets: String,
    pub purpose: String,
}

/// awk's default field splitting: runs of blanks (space, tab) separate fields.
fn fields(line: &str) -> Vec<&str> {
    line.split(|c| c == ' ' || c == '\t' || c == '\n')
        .filter(|f| !f.is_empty())
        .collect()
}

/// The manifest's data rows, as field lists.
fn rows(file: &Path) -> Vec<Vec<String>> {
    let text = fs::read(file).unwrap_or_default();
    let text = String::from_utf8_lossy(&text);
    let mut out = Vec::new();
    for line in text.split('\n') {
        let f = fields(line);
        if f.is_empty() || f[0].starts_with('#') {
            continue;
        }
        out.push(f.into_iter().map(str::to_string).collect());
    }
    out
}

fn purpose_of(f: &[String]) -> String {
    if f.len() > 5 {
        f[5..].join(" ")
    } else {
        String::new()
    }
}

/// load_profile: the row named `name`, or None when there is none or it
/// names no tools. A profile with an identity always gets gcloud, which
/// reading its secrets needs, matched as a whole comma-delimited field.
pub fn load(file: &Path, name: &str) -> Option<Profile> {
    let row = rows(file).into_iter().find(|f| f[0] == name)?;
    let get = |i: usize| row.get(i).cloned().unwrap_or_default();
    let mut p = Profile {
        tools: get(1),
        sa_account: get(2),
        sa_project: get(3),
        secrets: get(4),
        purpose: purpose_of(&row),
    };
    if p.tools.is_empty() {
        return None;
    }
    if p.sa_account != "-" && !p.tools.split(',').any(|t| t == "gcloud") {
        p.tools.push_str(",gcloud");
    }
    Some(p)
}

/// list_profiles: `  <name, padded to 10> <purpose>` per row.
pub fn list(file: &Path) -> String {
    let mut out = String::new();
    for f in rows(file) {
        out.push_str(&format!("  {:<10} {}\n", f[0], purpose_of(&f)));
    }
    out
}

/// known_credential_vars: every env var named in ANY row's secrets column,
/// sorted and unique. The manifest defines what counts as a credential.
pub fn known_credential_vars(file: &Path) -> Vec<String> {
    let mut vars: Vec<String> = Vec::new();
    for f in rows(file) {
        let Some(secrets) = f.get(4) else { continue };
        for pair in secrets.split(',') {
            let var = pair.split('=').next().unwrap_or("");
            if !var.is_empty() && var != "-" {
                vars.push(var.to_string());
            }
        }
    }
    vars.sort();
    vars.dedup();
    vars
}

/// `for x in $(printf '%s' "$list" | tr ',' ' ')`: split on commas and blanks.
pub fn words(list: &str) -> Vec<String> {
    list.split(|c| c == ',' || c == ' ' || c == '\t' || c == '\n')
        .filter(|w| !w.is_empty())
        .map(str::to_string)
        .collect()
}

/// `${pair%%=*}` and `${pair#*=}`: a pair with no `=` is both its own var and
/// its own secret name.
pub fn split_pair(pair: &str) -> (String, String) {
    match pair.find('=') {
        Some(i) => (pair[..i].to_string(), pair[i + 1..].to_string()),
        None => (pair.to_string(), pair.to_string()),
    }
}
