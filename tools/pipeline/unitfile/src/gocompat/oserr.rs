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

//! Go's wording for operating-system errors: `syscall.Errno.Error()` is the
//! C library's message starting lower-case ("no such file or directory"),
//! and an `*os.PathError` is "<op> <path>: <errno>".

use std::io;

/// The text Go prints for the errno behind `e`.
pub fn errno_text(e: &io::Error) -> String {
    if let Some(code) = e.raw_os_error() {
        // Rust's Display is "<strerror> (os error N)".
        let full = io::Error::from_raw_os_error(code).to_string();
        let msg = match full.rfind(" (os error ") {
            Some(i) => &full[..i],
            None => full.as_str(),
        };
        return lower_first(msg);
    }
    lower_first(&e.to_string())
}

fn lower_first(s: &str) -> String {
    let mut c = s.chars();
    match c.next() {
        Some(f) => {
            // "Is a directory" -> "is a directory", but keep acronyms whole.
            let second_upper = c.clone().next().map(|x| x.is_uppercase()).unwrap_or(false);
            if second_upper {
                s.to_string()
            } else {
                f.to_lowercase().collect::<String>() + c.as_str()
            }
        }
        None => String::new(),
    }
}

/// `&os.PathError{Op: op, Path: path, Err: e}.Error()`.
pub fn path_err(op: &str, path: &str, e: &io::Error) -> String {
    format!("{op} {path}: {}", errno_text(e))
}

/// Whether Go's `os.IsNotExist` holds.
pub fn is_not_exist(e: &io::Error) -> bool {
    e.kind() == io::ErrorKind::NotFound
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn errno_reads_like_go() {
        assert_eq!(
            errno_text(&io::Error::from_raw_os_error(2)),
            "no such file or directory"
        );
        assert_eq!(
            errno_text(&io::Error::from_raw_os_error(13)),
            "permission denied"
        );
        assert_eq!(
            errno_text(&io::Error::from_raw_os_error(21)),
            "is a directory"
        );
        assert_eq!(
            path_err("open", "/x", &io::Error::from_raw_os_error(2)),
            "open /x: no such file or directory"
        );
    }
}
