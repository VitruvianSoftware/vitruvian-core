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

//! Path glob matching and `allow.txt` parsing.

#[derive(Debug, Clone, Default)]
pub struct AllowList {
    patterns: Vec<String>,
}

impl AllowList {
    pub fn from_patterns(patterns: Vec<String>) -> Self {
        Self { patterns }
    }

    pub fn parse(text: &str) -> Vec<String> {
        text.lines()
            .map(str::trim)
            .filter(|line| !line.is_empty() && !line.starts_with('#'))
            .map(ToString::to_string)
            .collect()
    }

    pub fn extend(&mut self, extra: impl IntoIterator<Item = String>) {
        for pat in extra {
            let trimmed = pat.trim();
            if !trimmed.is_empty() {
                self.patterns.push(trimmed.to_string());
            }
        }
    }

    pub fn is_allowed(&self, path: &str) -> bool {
        self.patterns.iter().any(|pat| glob_match(pat, path))
    }

    pub fn patterns(&self) -> &[String] {
        &self.patterns
    }
}

pub fn glob_match(pattern: &str, path: &str) -> bool {
    let pat_segs: Vec<&str> = if pattern.is_empty() {
        Vec::new()
    } else {
        pattern.split('/').collect()
    };
    let path_segs: Vec<&str> = if path.is_empty() {
        Vec::new()
    } else {
        path.split('/').collect()
    };

    let m = pat_segs.len();
    let n = path_segs.len();
    let mut dp = vec![vec![false; n + 1]; m + 1];
    dp[m][n] = true;

    for i in (0..m).rev() {
        if pat_segs[i] == "**" {
            for j in (0..=n).rev() {
                dp[i][j] = dp[i + 1][j] || (j < n && dp[i][j + 1]);
            }
        } else {
            for j in 0..n {
                if segment_match(pat_segs[i], path_segs[j]) {
                    dp[i][j] = dp[i + 1][j + 1];
                }
            }
        }
    }

    dp[0][0]
}

fn segment_match(pattern: &str, text: &str) -> bool {
    let p: Vec<char> = pattern.chars().collect();
    let t: Vec<char> = text.chars().collect();
    let mut pi = 0;
    let mut ti = 0;
    let mut star_pi: Option<usize> = None;
    let mut match_ti = 0;

    while ti < t.len() {
        if pi < p.len() && (p[pi] == '?' || p[pi] == t[ti]) {
            pi += 1;
            ti += 1;
        } else if pi < p.len() && p[pi] == '*' {
            star_pi = Some(pi);
            match_ti = ti;
            pi += 1;
        } else if let Some(sp) = star_pi {
            pi = sp + 1;
            match_ti += 1;
            ti = match_ti;
        } else {
            return false;
        }
    }

    while pi < p.len() && p[pi] == '*' {
        pi += 1;
    }

    pi == p.len()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_allow_file_ignores_comments_and_blanks() {
        let raw = "\
# comment
   
  apps/antigravity/plugins/*/hooks/src/json.rs  
# another comment
packages/pulumi/examples/**
";
        assert_eq!(
            AllowList::parse(raw),
            vec![
                "apps/antigravity/plugins/*/hooks/src/json.rs",
                "packages/pulumi/examples/**",
            ]
        );
    }

    #[test]
    fn glob_matches_single_and_double_wildcards() {
        assert!(glob_match(
            "apps/antigravity/plugins/*/hooks/src/json.rs",
            "apps/antigravity/plugins/hookify/hooks/src/json.rs"
        ));
        assert!(!glob_match(
            "apps/antigravity/plugins/*/hooks/src/json.rs",
            "apps/antigravity/plugins/a/b/hooks/src/json.rs"
        ));

        let core = "apps/*/plugins/vitruvian-orchestrator/**/orchestrator-core.mjs";
        assert!(glob_match(
            core,
            "apps/opencode/plugins/vitruvian-orchestrator/lib/orchestrator-core.mjs"
        ));
        assert!(glob_match(
            core,
            "apps/antigravity/plugins/vitruvian-orchestrator/sidecars/panel/lib/orchestrator-core.mjs"
        ));
        assert!(glob_match(
            core,
            "apps/x/plugins/vitruvian-orchestrator/orchestrator-core.mjs"
        ));
        assert!(!glob_match(
            core,
            "apps/x/plugins/vitruvian-orchestrator/lib/prices.mjs"
        ));

        assert!(glob_match(
            "packages/pulumi/examples/**",
            "packages/pulumi/examples/go-foundation/main.go"
        ));
        assert!(!glob_match(
            "packages/pulumi/examples/**",
            "packages/pulumi/examples-extra/main.go"
        ));
        assert!(glob_match(
            "apps/web/oauth-user-inspector/frontend/design-system/**",
            "apps/web/oauth-user-inspector/frontend/design-system/a/b/c.ts"
        ));
        assert!(glob_match(
            "infrastructure/pulumi/foundation/**",
            "infrastructure/pulumi/foundation/0-bootstrap/main.go"
        ));
    }

    #[test]
    fn allow_list_matches_combined_patterns() {
        let mut list = AllowList::from_patterns(AllowList::parse(
            "apps/*/plugins/vitruvian-orchestrator/**/prices.mjs\n",
        ));
        list.extend(["apps/demo/skip_*.rs".to_string()]);
        assert!(
            list.is_allowed("apps/claude-code/plugins/vitruvian-orchestrator/hooks/lib/prices.mjs")
        );
        assert!(list.is_allowed("apps/demo/skip_me.rs"));
        assert!(!list.is_allowed("apps/demo/keep_me.rs"));
    }
}
