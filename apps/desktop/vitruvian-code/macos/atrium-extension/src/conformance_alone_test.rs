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

//! tool_conformance_test runs alone.
//!
//! The conformance script holds the tool to the app's time limits, two
//! seconds to answer and two to exit after shutdown. Run beside the Swift
//! test suites and compiles on a 3-vCPU CI runner, the tool got a sixth of
//! the CPU it gets alone and missed the exit limit (Presubmit run
//! 45486587457). The `exclusive` tag makes Bazel run it with nothing else.

use std::fs;

/// The rule named `name` in `build`, from its `name = ` line to the `)` that
/// closes it at the start of a line.
fn rule<'a>(build: &'a str, name: &str) -> Option<&'a str> {
    let marker = format!("name = \"{}\",", name);
    let at = build.find(&marker)?;
    let start = build[..at].rfind("\n")? + 1;
    let end = build[at..].find("\n)").map(|n| at + n)?;
    Some(&build[start..end])
}

#[test]
fn the_conformance_test_runs_alone() {
    let path = std::env::var("BUILD_FILE").expect("BUILD_FILE not set");
    let build = fs::read_to_string(&path).expect("cannot read BUILD");
    let conformance =
        rule(&build, "tool_conformance_test").expect("no tool_conformance_test in BUILD");
    let tags = conformance
        .split("tags = [")
        .nth(1)
        .and_then(|rest| rest.split(']').next())
        .expect("tool_conformance_test has no tags");
    assert!(
        tags.contains("\"exclusive\""),
        "tool_conformance_test must be tagged exclusive: its time limits are the app's, \
         not a runner's shared with the Swift suites. Tags: [{}]",
        tags.trim()
    );
}
