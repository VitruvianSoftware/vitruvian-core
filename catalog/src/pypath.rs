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

//! `pathlib.PurePosixPath` as the scripts print and join paths: `Path("./a/")`
//! is `a`, `Path("")` is `.`, and joining an absolute path replaces.

/// `str(Path(text))`.
pub fn norm(text: &str) -> String {
    if text.is_empty() {
        return ".".into();
    }
    let root = if text.starts_with("//") && !text.starts_with("///") {
        "//"
    } else if text.starts_with('/') {
        "/"
    } else {
        ""
    };
    let parts: Vec<&str> = text
        .split('/')
        .filter(|p| !p.is_empty() && *p != ".")
        .collect();
    let joined = parts.join("/");
    if root.is_empty() && joined.is_empty() {
        ".".into()
    } else {
        format!("{}{}", root, joined)
    }
}

/// `str(Path(a) / b)`.
pub fn join(a: &str, b: &str) -> String {
    if b.starts_with('/') {
        return norm(b);
    }
    let a = norm(a);
    let b = norm(b);
    if a == "." {
        b
    } else if b == "." {
        a
    } else if a.ends_with('/') {
        format!("{}{}", a, b)
    } else {
        format!("{}/{}", a, b)
    }
}

/// `Path(text).name`.
pub fn name(text: &str) -> String {
    let n = norm(text);
    if n == "." || n == "/" || n == "//" {
        return String::new();
    }
    n.rsplit('/').next().unwrap_or("").to_string()
}

/// `Path(text).is_absolute()`.
pub fn is_absolute(text: &str) -> bool {
    text.starts_with('/')
}

/// `os.path.basename(text)`.
pub fn basename(text: &str) -> &str {
    match text.rfind('/') {
        Some(i) => &text[i + 1..],
        None => text,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn as_pathlib() {
        assert_eq!(norm("./a//b/"), "a/b");
        assert_eq!(norm(""), ".");
        assert_eq!(norm("//x"), "//x");
        assert_eq!(norm("///x"), "/x");
        assert_eq!(join(".", "bazel-bin/x"), "bazel-bin/x");
        assert_eq!(join("/w/", "a"), "/w/a");
        assert_eq!(join("/w", "/abs"), "/abs");
        assert_eq!(join("out", "tools.json"), "out/tools.json");
        assert_eq!(name("a/public-key.txt"), "public-key.txt");
        assert_eq!(basename("dir/x.zip"), "x.zip");
    }
}
