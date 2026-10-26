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

#![no_main]

use std::ffi::{CStr, OsString};
use std::os::raw::{c_char, c_int};
#[cfg(unix)]
use std::os::unix::ffi::OsStringExt;

#[no_mangle]
pub extern "C" fn main(argc: c_int, argv: *const *const c_char) -> c_int {
    ci_preflight_lib::init_locale();
    let mut args = Vec::with_capacity(argc.max(0) as usize);
    if !argv.is_null() {
        for i in 0..(argc.max(0) as usize) {
            let ptr = unsafe { *argv.add(i) };
            if ptr.is_null() {
                break;
            }
            let bytes = unsafe { CStr::from_ptr(ptr).to_bytes().to_vec() };
            #[cfg(unix)]
            args.push(OsString::from_vec(bytes));
            #[cfg(not(unix))]
            args.push(OsString::from(String::from_utf8_lossy(&bytes).into_owned()));
        }
    }
    std::process::exit(ci_preflight_lib::run_os(&args))
}
