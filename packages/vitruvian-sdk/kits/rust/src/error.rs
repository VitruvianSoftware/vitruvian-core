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

use std::fmt;
use std::time::Duration;

use crate::generated::Error;

/// The codes a failure carries. The first five are JSON-RPC's own; the
/// rest are the protocol's refusals, which [`RefusalCode`] names too.
pub mod codes {
    pub const PARSE_ERROR: i64 = -32700;
    pub const INVALID_REQUEST: i64 = -32600;
    pub const METHOD_NOT_FOUND: i64 = -32601;
    pub const INVALID_PARAMS: i64 = -32602;
    pub const INTERNAL_ERROR: i64 = -32603;
    pub const NOT_IN_USES: i64 = -32001;
    pub const NOT_INSTALLED: i64 = -32002;
    pub const PERMISSION_MISSING: i64 = -32003;
    pub const UNAVAILABLE: i64 = -32004;
    pub const COMMAND_REFUSED: i64 = -32010;
}

/// Why a request was refused, by the code of its failure.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RefusalCode {
    /// The app: the service is not listed in the tool's `uses`.
    NotInUses,
    /// The app: the tool is not installed, or is switched off.
    NotInstalled,
    /// The app: Vitruvian lacks a macOS permission the service needs.
    PermissionMissing,
    /// The app: not available right now.
    Unavailable,
    /// The tool: it would not run the command.
    CommandRefused,
}

impl RefusalCode {
    /// The refusal a failure carries; None for any other failure.
    pub fn of(error: &Error) -> Option<RefusalCode> {
        match error.code {
            codes::NOT_IN_USES => Some(RefusalCode::NotInUses),
            codes::NOT_INSTALLED => Some(RefusalCode::NotInstalled),
            codes::PERMISSION_MISSING => Some(RefusalCode::PermissionMissing),
            codes::UNAVAILABLE => Some(RefusalCode::Unavailable),
            codes::COMMAND_REFUSED => Some(RefusalCode::CommandRefused),
            _ => None,
        }
    }
}

/// What can go wrong in a handler, and what a handler returns to refuse
/// its command.
#[derive(Clone, Debug, PartialEq)]
pub enum ToolError {
    /// The handler will not run its command, and a few English words for
    /// the log saying why. Make one with [`ToolError::refused`].
    Refused(String),
    /// The app refused a request: the failure it answered with.
    App(Error),
    /// The app said goodbye or closed the link, or has not said hello yet.
    LinkClosed,
    /// No answer came within the tool's answer timeout.
    NoAnswer(Duration),
    /// Anything else, as words for the log.
    Other(String),
}

impl ToolError {
    /// What a handler returns to refuse its command.
    pub fn refused(reason: impl Into<String>) -> ToolError {
        ToolError::Refused(reason.into())
    }
}

impl fmt::Display for ToolError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ToolError::Refused(reason) => f.write_str(reason),
            ToolError::App(error) => error.fmt(f),
            ToolError::LinkClosed => f.write_str("vitruvian: the link to the app is closed"),
            ToolError::NoAnswer(after) => {
                write!(f, "vitruvian: no answer from the app within {after:?}")
            }
            ToolError::Other(words) => f.write_str(words),
        }
    }
}

impl std::error::Error for ToolError {}

impl From<std::io::Error> for ToolError {
    fn from(error: std::io::Error) -> Self {
        ToolError::Other(error.to_string())
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "vitruvian: {} ({})", self.message, self.code)
    }
}

impl std::error::Error for Error {}
