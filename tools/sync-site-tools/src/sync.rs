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

//! sync.py: writes the Tools section of vitruviansoftware.dev from the
//! SDK's own files.
//!
//!     sync            writes the copies
//!     sync --check    fails when a copy is not what would be written
//!
//! Each copy is its source with a front matter added, its first heading
//! taken as the page's title, its links turned into links that work on the
//! site, and the words after a code fence's language dropped. The code
//! inside every fence is the source's, byte for byte, and no page is
//! written where it is not.

use std::ffi::OsString;
use std::io::Write;
use std::os::unix::ffi::OsStrExt;

use crate::catalogue;
use crate::json::{self, Value};
use crate::pyerr::PyErr;
use crate::pyfs;
use crate::pystr::{self, PyStr};
use crate::registry;

pub const SDK: &str = "packages/vitruvian-sdk";
pub const SITE: &str = "apps/web/vitruviansoftware-dev";
pub const MIRROR: &str = "https://github.com/VitruvianSoftware/vitruvian-sdk";

/// Where a file of the SDK is on the site, for links between the copies.
pub const ON_SITE: &[(&str, &str)] = &[
    ("docs/writing-a-tool.md", "/tools/guide/"),
    ("protocol/README.md", "/tools/protocol/"),
    ("samples/hello-swift", "/tools/examples/swift/"),
    ("samples/hello-python", "/tools/examples/python/"),
    ("samples/hello-typescript", "/tools/examples/typescript/"),
    ("samples/hello-python-kit", "/tools/examples/python-kit/"),
    ("samples/hello-go", "/tools/examples/go/"),
    ("samples/hello-rust", "/tools/examples/rust/"),
];

const NL: u32 = '\n' as u32;
const TICK: u32 = '`' as u32;

fn lit(text: &str) -> PyStr {
    PyStr::from(text)
}

fn cat(parts: &[&PyStr]) -> PyStr {
    PyStr::concat(parts)
}

/// `FENCE.match(line)`, `^(\s*)(```+)(.*)$`: where the whitespace ends
/// and where the backticks end.
pub fn fence_match(line: &[u32]) -> Option<(usize, usize)> {
    let mut i = 0;
    while i < line.len() && pystr::is_space(line[i]) {
        i += 1;
    }
    let mut j = i;
    while j < line.len() && line[j] == TICK {
        j += 1;
    }
    if j - i >= 3 {
        Some((i, j))
    } else {
        None
    }
}

/// `fenced(text)`: the body of every fenced block, in order.
pub fn fenced(text: &PyStr) -> Vec<PyStr> {
    let mut bodies = Vec::new();
    let mut body: Option<Vec<PyStr>> = None;
    for line in text.split_char(NL) {
        if fence_match(line.chars()).is_some() {
            match body.take() {
                None => body = Some(Vec::new()),
                Some(lines) => bodies.push(PyStr::join("\n", &lines)),
            }
        } else if let Some(lines) = body.as_mut() {
            lines.push(line);
        }
    }
    bodies
}

/// `re.match(r"^[a-z]+:|^#|^/", target)`.
fn is_absolute_link(target: &PyStr) -> bool {
    let chars = target.chars();
    match chars.first() {
        Some(&c) if c == '#' as u32 || c == '/' as u32 => true,
        _ => {
            let letters = chars
                .iter()
                .take_while(|&&c| ('a' as u32..='z' as u32).contains(&c))
                .count();
            letters > 0 && chars.get(letters) == Some(&(':' as u32))
        }
    }
}

/// `site_link(target, folder)`: a link in an SDK file, as it must be on
/// the site. A path whose last part has no dot is a folder.
pub fn site_link(target: &PyStr, folder: &PyStr) -> Result<PyStr, PyErr> {
    if is_absolute_link(target) {
        return Ok(target.clone());
    }
    let (path, _, anchor) = target.partition_char('#' as u32);
    let path = pyfs::normpath(&pyfs::join_s(folder, &path));
    if path.starts_with("..") {
        return Err(PyErr::exit(cat(&[
            &lit("a link leaves the SDK: "),
            target,
            &lit(" in "),
            folder,
        ])));
    }
    let mut found = match ON_SITE.iter().find(|(key, _)| path == lit(key)) {
        Some((_, on_site)) => lit(on_site),
        None => {
            let kind = if pyfs::basename(&path).contains_char('.' as u32) {
                "blob"
            } else {
                "tree"
            };
            cat(&[&lit(&format!("{}/{}/main/", MIRROR, kind)), &path])
        }
    };
    if !anchor.is_empty() {
        found.push_str("#");
        found.push(&anchor);
    }
    Ok(found)
}

/// `link(text, target, folder)`: a whole link. Text that is a relative path
/// in code becomes the path from the SDK's root.
pub fn link(text: &PyStr, target: &PyStr, folder: &PyStr) -> Result<PyStr, PyErr> {
    let mut text = text.clone();
    if text.starts_with("`../") && text.ends_with("`") {
        let inner = text.slice(1, text.len() - 1);
        let shown = pyfs::normpath(&pyfs::join_s(folder, &inner));
        let slash = if inner.ends_with("/") { "/" } else { "" };
        text = cat(&[&lit("`"), &shown, &lit(slash), &lit("`")]);
    }
    Ok(cat(&[
        &lit("["),
        &text,
        &lit("]("),
        &site_link(target, folder)?,
        &lit(")"),
    ]))
}

/// `LINK.sub(...)` with `\[([^\]]*)\]\(([^)\s]+)\)`.
pub fn rewrite_links(line: &PyStr, folder: &PyStr) -> Result<PyStr, PyErr> {
    let s = line.chars();
    let n = s.len();
    let mut out = PyStr::new();
    let mut i = 0;
    while i < n {
        if s[i] == '[' as u32 {
            if let Some(off) = s[i + 1..].iter().position(|&c| c == ']' as u32) {
                let j = i + 1 + off;
                if j + 1 < n && s[j + 1] == '(' as u32 {
                    let mut k = j + 2;
                    while k < n && s[k] != ')' as u32 && !pystr::is_space(s[k]) {
                        k += 1;
                    }
                    if k > j + 2 && k < n && s[k] == ')' as u32 {
                        let text = PyStr(s[i + 1..j].to_vec());
                        let target = PyStr(s[j + 2..k].to_vec());
                        out.push(&link(&text, &target, folder)?);
                        i = k + 1;
                        continue;
                    }
                }
            }
        }
        out.push_char(s[i]);
        i += 1;
    }
    Ok(out)
}

/// `page(front, body)`: the front matter, then the body, which Liquid
/// leaves alone.
pub fn page(front: &[(&str, PyStr)], body: &PyStr) -> Result<PyStr, PyErr> {
    if body.contains("{% endraw") {
        return Err(PyErr::exit(lit(
            "a source holds `{% endraw`, which would end the raw block",
        )));
    }
    let mut lines = vec![lit("---")];
    for (key, value) in front {
        lines.push(cat(&[&lit(key), &lit(": "), value]));
    }
    lines.push(lit("---"));
    for text in [
        "{%- comment -%}",
        "  Written by tools/sync-site-tools/sync.py from packages/vitruvian-sdk.",
        "  Do not edit it: change the source, then run",
        "    bazel run //tools/sync-site-tools:sync",
        "{%- endcomment -%}",
        "{% raw %}",
    ] {
        lines.push(lit(text));
    }
    lines.push(body.rstrip_char(NL));
    lines.push(lit("{% endraw %}"));
    let mut text = PyStr::join("\n", &lines);
    text.push_str("\n");
    Ok(text)
}

/// `read(base, path)`: the file as open() reads it in text mode.
fn read(base: &PyStr, path: &str) -> Result<PyStr, PyErr> {
    pyfs::read_text(&pyfs::join(base, path))
}

fn dumps_ascii(value: &PyStr) -> PyStr {
    json::dumps(&Value::Str(value.clone()), true, None)
}

/// `from_markdown(base, source, permalink, description)`: a page made of
/// one Markdown file of the SDK, and its body.
pub fn from_markdown(
    base: &PyStr,
    source: &str,
    permalink: &str,
    description: &str,
) -> Result<(PyStr, PyStr), PyErr> {
    let text = read(&pyfs::join(base, SDK), source)?;
    let (first, _, rest) = text.partition_char(NL);
    if !first.starts_with("# ") {
        return Err(PyErr::exit(lit(&format!(
            "{} does not start with a `# ` heading",
            source
        ))));
    }
    let folder = pyfs::dirname(&lit(source));
    let mut out = Vec::new();
    let mut inside = false;
    for line in rest.lstrip_char(NL).split_char(NL) {
        let mut line = line;
        if let Some((ws, ticks)) = fence_match(line.chars()) {
            if !inside {
                let after = line.slice(ticks, line.len()).strip();
                let language = after.split_char(' ' as u32).swap_remove(0);
                line = cat(&[&line.slice(0, ws), &line.slice(ws, ticks), &language]);
            }
            inside = !inside;
        } else if !inside {
            line = rewrite_links(&line, &folder)?;
        }
        out.push(line);
    }
    let body = PyStr::join("\n", &out);
    if fenced(&body) != fenced(&rest) {
        return Err(PyErr::exit(lit(&format!(
            "the code in {} would not be copied byte for byte",
            source
        ))));
    }
    let front = [
        ("layout", lit("tools")),
        ("title", dumps_ascii(&first.slice(2, first.len()).strip())),
        ("description", dumps_ascii(&lit(description))),
        ("permalink", lit(permalink)),
        ("source", lit(&format!("{}/{}", SDK, source))),
    ];
    Ok((page(&front, &body)?, body))
}

/// `methods_table(base)`: every message of the protocol, from methods.json.
pub fn methods_table(base: &PyStr) -> Result<PyStr, PyErr> {
    let table = json::loads(&read(&pyfs::join(base, SDK), "protocol/methods.json")?)?;
    let mut rows = vec![
        lit("## Every message, from `methods.json`"),
        lit(""),
        lit("| Message | Sent by | Kind | In `uses` |"),
        lit("|---|---|---|---|"),
    ];
    for row in table.subscript("methods")?.iterate()? {
        let uses = if row.subscript("uses")?.truthy() {
            cat(&[&lit("`"), &row.subscript("uses")?.py_str(), &lit("`")])
        } else {
            lit("")
        };
        rows.push(cat(&[
            &lit("| `"),
            &row.subscript("method")?.py_str(),
            &lit("` | "),
            &row.subscript("sender")?.py_str(),
            &lit(" | "),
            &row.subscript("kind")?.py_str(),
            &lit(" | "),
            &uses,
            &lit(" |"),
        ]));
    }
    Ok(PyStr::join("\n", &rows))
}

/// An example made of a sample's files.
pub struct Example {
    pub language: &'static str,
    pub title: &'static str,
    pub folder: &'static str,
    pub files: &'static [(&'static str, &'static str)],
    pub description: &'static str,
    pub how: &'static str,
}

pub const EXAMPLES: &[Example] = &[
    Example {
        language: "swift",
        title: "An example in Swift",
        folder: "samples/hello-swift",
        files: &[("vitruvian-tool.json", "json"), ("main.swift", "swift")],
        description: "A tool written with the Swift kit: it says hello, and counts with a preference the person can change in Settings.",
        how: "`vitruvian-tool init <folder> --template swift` starts a new tool from a copy of this one, as a Swift package that depends on the published SDK. Its `build.sh` builds the program into `tool/bin/tool`, and `tool/` is the folder you add to Vitruvian.",
    },
    Example {
        language: "python",
        title: "An example in Python",
        folder: "samples/hello-python",
        files: &[("vitruvian-tool.json", "json"), ("bin/tool.py", "python")],
        description: "A tool in plain Python with nothing else: it says hello, and copies the time.",
        how: "`vitruvian-tool init <folder>` starts a new tool from a copy of this one. The folder runs as it is: add it to Vitruvian.",
    },
];

/// The kit samples' examples: each sample's README.md, copied as the guide is.
pub const KIT_EXAMPLES: &[(&str, &str, &str)] = &[
    (
        "typescript",
        "samples/hello-typescript",
        "A tool written with the TypeScript kit: plain JavaScript that Node runs as it is, which says hello and counts with a preference.",
    ),
    (
        "python-kit",
        "samples/hello-python-kit",
        "A tool written with the Python kit, installed into the tool's own folder, which says hello and counts with a preference.",
    ),
    (
        "go",
        "samples/hello-go",
        "A tool written with the Go kit: it says hello, and counts with a preference the person can change in Settings.",
    ),
    (
        "rust",
        "samples/hello-rust",
        "A tool written with the Rust kit: it says hello, and counts with a preference the person can change in Settings.",
    ),
];

/// `example(base, ...)`.
pub fn example(base: &PyStr, ex: &Example) -> Result<PyStr, PyErr> {
    let mut parts = vec![
        lit(ex.how),
        lit(""),
        lit(&format!(
            "This is [`{0}`]({1}/tree/main/{0}) of the SDK, as it is. The conformance script runs it in the SDK's tests.",
            ex.folder, MIRROR
        )),
    ];
    let mut sources = Vec::new();
    let dir = pyfs::join(&pyfs::join(base, SDK), ex.folder);
    for (name, fence) in ex.files {
        let text = read(&dir, name)?;
        if text.contains("```") || !text.ends_with("\n") {
            return Err(PyErr::exit(lit(&format!(
                "{}/{} cannot be put in a fenced block",
                ex.folder, name
            ))));
        }
        let code = text.slice(0, text.len() - 1);
        sources.push(code.clone());
        parts.push(lit(""));
        parts.push(lit(&format!("`{}`:", name)));
        parts.push(lit(""));
        parts.push(lit(&format!("```{}", fence)));
        parts.push(code);
        parts.push(lit("```"));
    }
    let body = PyStr::join("\n", &parts);
    if fenced(&body) != sources {
        return Err(PyErr::exit(lit(&format!(
            "the code in {} would not be copied byte for byte",
            ex.folder
        ))));
    }
    let front = [
        ("layout", lit("tools")),
        ("title", dumps_ascii(&lit(ex.title))),
        ("description", dumps_ascii(&lit(ex.description))),
        (
            "permalink",
            lit(&format!("/tools/examples/{}/", ex.language)),
        ),
        ("source", lit(&format!("{}/{}", SDK, ex.folder))),
    ];
    page(&front, &body)
}

/// `sources()`: every file of the SDK a copy is made from.
pub fn sources() -> Vec<String> {
    let mut found: Vec<String> = [
        "docs/writing-a-tool.md",
        "protocol/README.md",
        "protocol/methods.json",
    ]
    .iter()
    .map(|s| s.to_string())
    .collect();
    for ex in EXAMPLES {
        for (name, _) in ex.files {
            found.push(format!("{}/{}", ex.folder, name));
        }
    }
    for (_, folder, _) in KIT_EXAMPLES {
        found.push(format!("{}/README.md", folder));
    }
    found
}

/// `pages(base)`: every copy, by its path in the site, in sync.py's order.
pub fn pages(base: &PyStr) -> Result<Vec<(String, PyStr)>, PyErr> {
    let (guide, _) = from_markdown(
        base,
        "docs/writing-a-tool.md",
        "/tools/guide/",
        "From nothing to a working tool in ten minutes, then the manifest, every message, the limits, and how to find out why a tool does not work.",
    )?;
    let (protocol, body) = from_markdown(
        base,
        "protocol/README.md",
        "/tools/protocol/",
        "How Vitruvian and a tool talk: one JSON message per line over the tool's standard input and output.",
    )?;
    let trimmed = body.rstrip_char(NL);
    let old = cat(&[&trimmed, &lit("\n{% endraw %}")]);
    let new = cat(&[
        &trimmed,
        &lit("\n\n"),
        &methods_table(base)?,
        &lit("\n{% endraw %}"),
    ]);
    let protocol = protocol.replace(&old, &new);
    let mut found = vec![
        ("tools/guide.md".to_string(), guide),
        ("tools/protocol.md".to_string(), protocol),
    ];
    for ex in EXAMPLES {
        let text = example(base, ex)?;
        found.push((format!("tools/examples/{}.md", ex.language), text));
    }
    for (language, folder, description) in KIT_EXAMPLES {
        let (text, _) = from_markdown(
            base,
            &format!("{}/README.md", folder),
            &format!("/tools/examples/{}/", language),
            description,
        )?;
        found.push((format!("tools/examples/{}.md", language), text));
    }
    Ok(found)
}

fn update(files: &mut Vec<(String, Vec<u8>)>, more: Vec<(String, Vec<u8>)>) {
    for (path, data) in more {
        match files.iter_mut().find(|(p, _)| *p == path) {
            Some(slot) => slot.1 = data,
            None => files.push((path, data)),
        }
    }
}

/// `wanted(base)`: every file the section is made of, by its path from the
/// repository's root, and the bytes it must hold, in sync.py's order.
pub fn wanted(base: &PyStr) -> Result<Vec<(String, Vec<u8>)>, PyErr> {
    let mut files = Vec::new();
    let found = pages(base)?;
    for (path, text) in found {
        let data = text.encode_utf8()?;
        update(&mut files, vec![(format!("{}/{}", SITE, path), data)]);
    }
    let root = pyfs::path_str(base);
    update(&mut files, catalogue::outputs(&root)?);
    update(&mut files, registry::outputs(&root)?);
    Ok(files)
}

/// `stale(base)`: the paths whose committed bytes are not what would be
/// written.
pub fn stale(base: &PyStr) -> Result<Vec<String>, PyErr> {
    let mut behind = Vec::new();
    for (path, data) in wanted(base)? {
        if !pyfs::os_isfile(&pyfs::join(base, &path))
            || pyfs::read_bytes(&pyfs::path_str(&pyfs::join(base, &path)))? != data
        {
            behind.push(path);
        }
    }
    behind.sort();
    Ok(behind)
}

/// `root()`: where `bazel run` was started, else three folders up from the
/// program, which is also where it is among a test's runfiles.
pub fn root(workspace: Option<OsString>, program: &PyStr) -> PyStr {
    match workspace {
        Some(dir) if !dir.is_empty() => PyStr::from_surrogateescape(dir.as_bytes()),
        _ => pyfs::dirname(&pyfs::dirname(&pyfs::dirname(&pyfs::abspath(program)))),
    }
}

fn body(base: &PyStr, check: bool, out: &mut dyn Write, err: &mut dyn Write) -> Result<i32, PyErr> {
    if check {
        let behind = stale(base)?;
        for path in &behind {
            let _ = writeln!(err, "{} is not what sync.py writes", path);
        }
        let _ = writeln!(
            out,
            "site tools: {}",
            if behind.is_empty() {
                "in sync"
            } else {
                "OUT OF SYNC, run bazel run //tools/sync-site-tools:sync"
            }
        );
        return Ok(if behind.is_empty() { 0 } else { 1 });
    }
    let mut files = wanted(base)?;
    files.sort_by(|a, b| a.0.cmp(&b.0));
    for (path, data) in files {
        let target = pyfs::join(base, &path);
        pyfs::makedirs(&pyfs::dirname(&target))?;
        pyfs::write_bytes(&target, &data)?;
        let _ = writeln!(out, "wrote {}", path);
    }
    Ok(0)
}

/// `main(arguments)`, and what Python does with what it returns or raises:
/// the exit status.
pub fn run(
    arguments: &[OsString],
    workspace: Option<OsString>,
    program: &PyStr,
    out: &mut dyn Write,
    err: &mut dyn Write,
) -> i32 {
    let base = root(workspace, program);
    let check = arguments.iter().any(|a| a.as_bytes() == b"--check");
    match body(&base, check, out, err) {
        Ok(code) => code,
        Err(e) => {
            let _ = out.flush();
            let _ = err.write_all(&e.stderr_bytes());
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(text: &str) -> PyStr {
        PyStr::from(text)
    }

    fn rewrite(line: &str, folder: &str) -> String {
        match rewrite_links(&s(line), &s(folder)) {
            Ok(text) => text.to_string_lossy(),
            Err(e) => e.last_line(),
        }
    }

    #[test]
    fn links_become_links_on_the_site() {
        let cases = [
            ("see [the guide](../docs/writing-a-tool.md)", "protocol", "see [the guide](/tools/guide/)"),
            ("[x](methods.json#row)", "protocol", "[x](https://github.com/VitruvianSoftware/vitruvian-sdk/blob/main/protocol/methods.json#row)"),
            ("[x](../samples/hello-go)", "docs", "[x](/tools/examples/go/)"),
            ("[x](../kits/go)", "docs", "[x](https://github.com/VitruvianSoftware/vitruvian-sdk/tree/main/kits/go)"),
            ("[`../samples/hello-python`](../samples/hello-python)", "docs", "[`samples/hello-python`](/tools/examples/python/)"),
            ("[`../kits/`](../kits/)", "docs", "[`kits/`](https://github.com/VitruvianSoftware/vitruvian-sdk/tree/main/kits)"),
            ("[a](https://x.y) [b](#top) [c](/abs) [d](mailto:x)", "docs", "[a](https://x.y) [b](#top) [c](/abs) [d](mailto:x)"),
            ("[a [b](c.md)", "docs", "[a [b](https://github.com/VitruvianSoftware/vitruvian-sdk/blob/main/docs/c.md)"),
            ("[a](b c) [](d) [e]()", "docs", "[a](b c) [](https://github.com/VitruvianSoftware/vitruvian-sdk/tree/main/docs/d) [e]()"),
            ("[x](../../out)", "docs", "a link leaves the SDK: ../../out in docs"),
            ("[x](a.md#)", "docs", "[x](https://github.com/VitruvianSoftware/vitruvian-sdk/blob/main/docs/a.md)"),
        ];
        for (line, folder, want) in cases {
            assert_eq!(rewrite(line, folder), want, "{}", line);
        }
    }

    #[test]
    fn fences_are_found_as_the_regex_finds_them() {
        assert_eq!(fence_match(&s("```json extra").0), Some((0, 3)));
        assert_eq!(fence_match(&s("\u{2003}````").0), Some((1, 5)));
        assert_eq!(fence_match(&s("  ``").0), None);
        assert_eq!(fence_match(&s("x```").0), None);
        assert_eq!(
            fenced(&s("a\n```\nb\nc\n```\n```x\n\n```")),
            vec![s("b\nc"), s("")]
        );
    }

    #[test]
    fn a_page_refuses_an_endraw() {
        let e = page(&[], &s("x {% endraw %}")).unwrap_err();
        assert_eq!(
            e.last_line(),
            "a source holds `{% endraw`, which would end the raw block"
        );
        let ok = page(&[("layout", s("tools"))], &s("body\n\n")).unwrap();
        assert!(ok
            .to_string_lossy()
            .ends_with("{% raw %}\nbody\n{% endraw %}\n"));
    }

    #[test]
    fn sources_are_the_sdk_files_copied() {
        assert_eq!(
            sources(),
            vec![
                "docs/writing-a-tool.md",
                "protocol/README.md",
                "protocol/methods.json",
                "samples/hello-swift/vitruvian-tool.json",
                "samples/hello-swift/main.swift",
                "samples/hello-python/vitruvian-tool.json",
                "samples/hello-python/bin/tool.py",
                "samples/hello-typescript/README.md",
                "samples/hello-python-kit/README.md",
                "samples/hello-go/README.md",
                "samples/hello-rust/README.md",
            ]
        );
    }

    #[test]
    fn root_prefers_the_workspace() {
        assert_eq!(root(Some(OsString::from("/w")), &s("/a/b/c/d")), s("/w"));
        assert_eq!(
            root(Some(OsString::new()), &s("/r/tools/sync-site-tools/sync")),
            s("/r")
        );
        assert_eq!(root(None, &s("/r/tools/sync-site-tools/sync")), s("/r"));
    }
}
