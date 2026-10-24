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

//! agent-guard in Rust: the same decisions as agent_guard.py, compiled.
//!
//! A PreToolUse hook for Claude Code and Antigravity. It reads the tool call
//! on stdin, works out every program the command would run, and refuses the
//! ones that, inside vitruvian-core, must go through a Bazel target. The
//! refusal names the replacement. It is a guardrail against habits, not a
//! security boundary.
//!
//! agent_guard.py stays the source of truth (hook.sh runs it); this crate is a
//! port that must decide exactly as it does, which
//! `//tools/agent-guard:agent_guard_rs_parity_test` checks by running
//! agent_guard_test.py's own table and hook tests against this binary.

mod unicode_tables;

pub mod batch;
pub mod classify;
pub mod gitstate;
pub mod guard;
pub mod hook;
pub mod invocations;
pub mod paths;
pub mod pyutil;
pub mod pyval;
pub mod redact;
pub mod scope;
pub mod shell;
pub mod tamper;

pub use guard::{evaluate, evaluate_tool, Decision, VERSION};
