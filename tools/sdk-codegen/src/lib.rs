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

//! tools/sdk-codegen in Rust: the same files, output and exit status as
//! sdk_codegen.py, from the same three protocol files. Each module is the
//! Python module, or the piece of Python's standard library or of
//! jsonschema, whose behaviour it carries; the parity test holds the two
//! programs to each other.

pub mod argparse;
pub mod cli;
pub mod difflib;
pub mod emitters;
pub mod fsio;
pub mod json;
pub mod metaschema;
pub mod model;
pub mod pprint;
pub mod pyerr;
pub mod pyre;
pub mod pystr;
pub mod schema;
pub mod textwrap;
pub mod unicode_tables;
