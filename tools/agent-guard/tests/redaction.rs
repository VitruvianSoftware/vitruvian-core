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

//! RedactionTest: secrets are taken out of what the log keeps, and
//! ordinary commands are left alone.

use agent_guard::redact::redact;

use crate::common::*;

#[test]
fn redacts() {
    let _l = shared();
    let cases: [(&str, &str); 27] = [
        ("mysql -phunter2 db", "hunter2"),
        ("psql postgres://app:s3cr3t@db:5432/x", "s3cr3t"),
        (
            "redis-cli -u redis://default:r3dispass@host:6379",
            "r3dispass",
        ),
        ("curl -u admin:adm1npass https://x", "adm1npass"), // gitleaks:allow
        ("curl --user admin:adm1npass https://x", "adm1npass"), // gitleaks:allow
        ("gh secret set FOO --body s3cretvalue", "s3cretvalue"),
        ("gh secret set FOO -b 'two words'", "two words"),
        (
            "gh secret set FOO --body=\"quoted value\" -R x/y",
            "quoted value",
        ),
        ("curl -H 'X-Api-Key: k3yvalue' https://x", "k3yvalue"), // gitleaks:allow
        (
            "curl -H 'X-Auth-Token: t0kenvalue' https://x", // gitleaks:allow
            "t0kenvalue",
        ),
        (
            "curl -H 'PRIVATE-TOKEN: glvalue123' https://x", // gitleaks:allow
            "glvalue123",
        ),
        (
            "curl 'https://x?key=AIzaSyA1234567890abcdefghijklmnopqrstuv'", // gitleaks:allow
            "AIzaSyA1234567890abcdefghijklmnopqrstuv",                      // gitleaks:allow
        ),
        (
            "echo ghs_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123",
            "ghs_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123",
        ),
        (
            "echo github_pat_11ABCDEFG0123456789_abcdefghijklmnop",
            "github_pat_11ABCDEFG0123456789_abcdefghijklmnop",
        ),
        (
            "echo xoxb-1234567890-abcdefghij",
            "xoxb-1234567890-abcdefghij",
        ),
        (
            "echo xoxp-1234567890-abcdefghij",
            "xoxp-1234567890-abcdefghij",
        ),
        (
            "echo sk-ant-api03-abcdefghijklmnopqrstuvwxyz",
            "sk-ant-api03-abcdefghijklmnopqrstuvwxyz",
        ),
        ("tool --password=hunter2", "hunter2"),
        ("tool --password hunter2", "hunter2"),
        ("curl 'https://x/?token=abc123def'", "abc123def"),
        (
            "GH_TOKEN=ghs_abcdefghijklmnopqrstuvwxyz0123 gh pr list",
            "ghs_abcdefghijklmnopqrstuvwxyz0123",
        ),
        (
            "curl -H 'Authorization: Bearer sekrit-value-123' https://x", // gitleaks:allow
            "sekrit-value-123",
        ),
        (
            "curl -H \"Authorization: token abcdefgh12345\" x", // gitleaks:allow
            "abcdefgh12345",
        ),
        ("git clone https://user:pa55word@github.com/x/y", "pa55word"),
        (
            "echo ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
            "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
        ),
        ("API_KEY=xyz789 ./run", "xyz789"),
        ("vault login --token s.abcdef", "s.abcdef"),
    ];
    for (t, secret) in cases {
        let out = redact(t);
        assert!(!out.contains(secret), "{}: {}", t, out);
        assert!(out.contains("[REDACTED]"), "{}: {}", t, out);
    }
}

#[test]
fn leaves_ordinary_commands_alone() {
    let _l = shared();
    for t in [
        "git log --oneline",
        "go test ./...",
        "gh pr view 12",
        "git log -p 5",
        "git log -p -5",
        "patch -p1 < x.diff",
        "git apply -p2 x.patch",
        "find . -print",
        "find . -path ./x -prune",
        "sudo -u james ls",
        "mkdir -p a/b",
        "gh secret list",
        "ssh -p 2222 host",
    ] {
        assert_eq!(redact(t), t);
    }
}
