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

//! The catalog's command-line tools (//catalog:sign, :check-downloads,
//! :rehearse and :bump), ported from their Python scripts, which stay the
//! reference: each binary prints, writes and exits as its script does.

pub mod argparse;
pub mod base64;
pub mod bump;
pub mod catalogue;
pub mod check_downloads;
pub mod crypto;
pub mod here;
pub mod http;
pub mod json;
pub mod macho;
pub mod plist;
pub mod py;
pub mod pyerr;
pub mod pypath;
pub mod pyre;
pub mod pystr;
pub mod pytext;
pub mod rehearse;
pub mod rules;
pub mod schema;
pub mod sign;
pub mod signing;
pub mod timefmt;
pub mod zip;

#[cfg(test)]
mod catalog_test;
#[cfg(test)]
mod release_trigger_test;
