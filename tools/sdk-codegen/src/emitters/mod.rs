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

//! One module per language, as emitters/*.py has one, each taking the model
//! and giving back its files by their path in the package. They run in the
//! order sdk_codegen.py finds them: by name.

pub mod go;
pub mod plain;
pub mod python;
pub mod rust;
pub mod typescript;

use crate::model::Model;
use crate::pyerr::PyResult;

/// An emitter: its NAME and its `emit`.
pub struct Emitter {
    pub name: &'static str,
    pub emit: fn(&Model) -> PyResult<Vec<(String, String)>>,
}

/// Every emitter, by name.
pub fn all() -> Vec<Emitter> {
    vec![
        Emitter {
            name: "go",
            emit: go::emit,
        },
        Emitter {
            name: "python",
            emit: python::emit,
        },
        Emitter {
            name: "rust",
            emit: rust::emit,
        },
        Emitter {
            name: "typescript",
            emit: typescript::emit,
        },
    ]
}
