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

//! What would end sync.py: an uncaught exception, whose traceback's last
//! line is `Type: message`, or `raise SystemExit(message)`.

use crate::pystr::PyStr;

#[derive(Clone, Debug, PartialEq)]
pub enum PyErr {
    /// An uncaught exception: its type as a traceback names it, and its
    /// message.
    Exception { kind: String, message: PyStr },
    /// `raise SystemExit(message)`: the message alone on stderr, status 1.
    Exit(PyStr),
}

impl PyErr {
    pub fn exc(kind: &str, message: &str) -> PyErr {
        PyErr::Exception {
            kind: kind.to_string(),
            message: PyStr::from(message),
        }
    }

    pub fn exc_s(kind: &str, message: PyStr) -> PyErr {
        PyErr::Exception {
            kind: kind.to_string(),
            message,
        }
    }

    pub fn exit(message: PyStr) -> PyErr {
        PyErr::Exit(message)
    }

    /// `KeyError: 'key'`.
    pub fn key_error(key: &PyStr) -> PyErr {
        PyErr::exc_s("KeyError", key.repr())
    }

    pub fn type_error(message: &str) -> PyErr {
        PyErr::exc("TypeError", message)
    }

    /// The last line of the traceback, or the SystemExit message.
    pub fn last_line(&self) -> String {
        match self {
            PyErr::Exception { kind, message } => {
                format!("{}: {}", kind, message.to_string_lossy())
            }
            PyErr::Exit(message) => message.to_string_lossy(),
        }
    }

    /// What Python writes to stderr for it. A traceback's frames name
    /// Python's own files and lines, which the port does not have: it
    /// writes one frame, and the last line, which is Python's.
    pub fn stderr_bytes(&self) -> Vec<u8> {
        let mut text = PyStr::new();
        match self {
            PyErr::Exception { kind, message } => {
                text.push_str("Traceback (most recent call last):\n");
                text.push_str("  File \"sync.py\", in main\n");
                text.push_str(kind);
                text.push_str(": ");
                text.push(message);
                text.push_str("\n");
            }
            PyErr::Exit(message) => {
                text.push(message);
                text.push_str("\n");
            }
        }
        text.to_utf8_backslashreplace()
    }
}
