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

//! The Dockerfile against what the tests prove (#4176).
//!
//! `start_test` lays out `/app` itself from Bazel's binaries, so on its own it
//! says nothing about the image: drop the runtime stage's server COPY, or build
//! the server with a different Rust, and every other test still passes; only
//! the development deploy would notice. This reads the Dockerfile and checks
//! the parts that decide whether the image starts:
//!
//! - the server is compiled with the Rust release Bazel uses (MODULE.bazel), so
//!   the image runs the code the tests ran;
//! - the build stage produces `dist-server/start` and
//!   `dist-server/oauth-user-inspector-server`, the runtime stage copies them
//!   and the frontend into `/app`, and the command is `/app/dist-server/start`;
//! - the `/app` those COPY lines produce is one `start` accepts and in which it
//!   picks the native server (checked with `start`'s own functions);
//! - the runtime stage ships no Node, which nothing at run time uses;
//! - nothing the Dockerfile copies from the build context (server/, scripts/,
//!   frontend/, ...) is excluded by `.dockerignore`.
//!
//! It does not build the image (the delivery workflow's build job does that on
//! every deployable push); it catches the edits that build fine and then fail
//! to serve.

use oauth_scripts_lib::start::{select_server_command, validate_build_dirs, ServerCommand};
use std::fs;
use std::path::PathBuf;

fn runfile(var: &str) -> PathBuf {
    PathBuf::from(std::env::var(var).unwrap_or_else(|_| panic!("{var} unset")))
}

fn read(var: &str) -> String {
    let p = runfile(var);
    fs::read_to_string(&p).unwrap_or_else(|e| panic!("{var}={}: {e}", p.display()))
}

/// One instruction per entry, with `\` continuations joined.
fn instructions(dockerfile: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut cur = String::new();
    for raw in dockerfile.lines() {
        let line = raw.trim();
        if cur.is_empty() && (line.is_empty() || line.starts_with('#')) {
            continue;
        }
        if let Some(body) = line.strip_suffix('\\') {
            cur.push_str(body.trim_end());
            cur.push(' ');
        } else {
            cur.push_str(line);
            out.push(std::mem::take(&mut cur));
        }
    }
    if !cur.is_empty() {
        out.push(cur);
    }
    out
}

struct Stage {
    from: String,
    name: String,
    body: Vec<String>,
}

fn stages(dockerfile: &str) -> (Vec<String>, Vec<Stage>) {
    let mut global = Vec::new();
    let mut stages: Vec<Stage> = Vec::new();
    for ins in instructions(dockerfile) {
        if let Some(rest) = ins.strip_prefix("FROM ") {
            let words: Vec<&str> = rest.split_whitespace().collect();
            let name = match words.as_slice() {
                [_, as_kw, name, ..] if as_kw.eq_ignore_ascii_case("AS") => name.to_string(),
                _ => String::new(),
            };
            stages.push(Stage {
                from: words.first().copied().unwrap_or_default().to_string(),
                name,
                body: Vec::new(),
            });
        } else if let Some(s) = stages.last_mut() {
            s.body.push(ins);
        } else {
            global.push(ins);
        }
    }
    (global, stages)
}

fn stage<'a>(all: &'a [Stage], name: &str) -> &'a Stage {
    all.iter()
        .find(|s| s.name == name)
        .unwrap_or_else(|| panic!("no `FROM ... AS {name}` stage in the Dockerfile"))
}

fn arg_default(global: &[String], name: &str) -> Option<String> {
    global.iter().find_map(|ins| {
        ins.strip_prefix("ARG ")?
            .trim()
            .strip_prefix(&format!("{name}="))
            .map(|v| v.trim().to_string())
    })
}

/// `rust.toolchain(... versions = ["X"] ...)` in MODULE.bazel.
fn bazel_rust_version(module: &str) -> String {
    let start = module
        .find("rust.toolchain(")
        .expect("MODULE.bazel has no rust.toolchain(...)");
    let call = &module[start..];
    let call = &call[..call.find(')').expect("unterminated rust.toolchain(")];
    let versions = &call[call
        .find("versions")
        .expect("rust.toolchain has no versions")..];
    let q1 = versions.find('"').expect("no quoted version") + 1;
    let q2 = q1 + versions[q1..].find('"').expect("unterminated version");
    versions[q1..q2].to_string()
}

#[test]
fn server_is_built_with_bazels_rust() {
    let (global, all) = stages(&read("DOCKERFILE"));
    let bazel = bazel_rust_version(&read("MODULE_BAZEL"));
    let server = stage(&all, "server-build");
    assert_eq!(
        server.from, "rust:${RUST_VERSION}-slim-bookworm",
        "the server-build stage must take its Rust from ARG RUST_VERSION, not a hardcoded tag"
    );
    assert_eq!(
        arg_default(&global, "RUST_VERSION").as_deref(),
        Some(bazel.as_str()),
        "Dockerfile ARG RUST_VERSION must equal MODULE.bazel's rust.toolchain version ({bazel}): \
         the image would run code compiled by a Rust no test used"
    );
}

#[test]
fn runtime_stage_ships_the_server_and_starts_it() {
    let (_, all) = stages(&read("DOCKERFILE"));
    let server = stage(&all, "server-build");
    let built = server.body.join("\n");
    for out in [
        "/app/dist-server/oauth-user-inspector-server",
        "-o /app/dist-server/start",
    ] {
        assert!(
            built.contains(out),
            "server-build stage no longer produces {out}:\n{built}"
        );
    }

    let runtime = all.last().expect("Dockerfile has no stages");
    assert_eq!(
        runtime.name, "runtime",
        "the last stage is the image; expected it to be `runtime`"
    );
    let body = &runtime.body;
    assert!(
        body.iter().any(|i| i == "WORKDIR /app"),
        "runtime WORKDIR must be /app (start resolves dist/ and dist-server/ from its cwd)"
    );
    for copy in [
        "COPY --from=server-build /app/dist-server ./dist-server",
        "COPY --from=build /app/dist ./dist",
    ] {
        assert!(
            body.iter().any(|i| i == copy),
            "runtime stage is missing `{copy}`; without it the image cannot serve"
        );
    }
    let cmd: Vec<&String> = body
        .iter()
        .filter(|i| i.starts_with("CMD ") || i.starts_with("ENTRYPOINT "))
        .collect();
    assert_eq!(
        cmd,
        vec![&r#"CMD ["/app/dist-server/start"]"#.to_string()],
        "the image must start through dist-server/start"
    );

    // The /app those COPY lines leave, judged by start's own checks.
    let app = std::env::var_os("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir)
        .join(format!("dockerfile-app-{}", std::process::id()));
    let _ = fs::remove_dir_all(&app);
    fs::create_dir_all(app.join("dist")).unwrap();
    fs::create_dir_all(app.join("dist-server")).unwrap();
    for out in ["oauth-user-inspector-server", "start"] {
        if built.contains(&format!("/app/dist-server/{out}")) {
            fs::write(app.join("dist-server").join(out), "").unwrap();
        }
    }
    assert_eq!(validate_build_dirs(&app), Ok(()));
    assert_eq!(
        select_server_command(&app),
        ServerCommand::Native("dist-server/oauth-user-inspector-server")
    );
    let _ = fs::remove_dir_all(&app);
}

#[test]
fn runtime_stage_ships_no_node() {
    let (_, all) = stages(&read("DOCKERFILE"));
    let runtime = all.last().unwrap();
    assert!(
        !runtime.from.starts_with("node:"),
        "runtime stage is FROM {}; the native server needs no Node",
        runtime.from
    );
    for ins in &runtime.body {
        let lower = ins.to_lowercase();
        for word in ["pnpm ", "npm ", "corepack", "nodejs", "node_modules"] {
            assert!(
                !lower.contains(word),
                "runtime stage still sets up Node ({word:?}): {ins}"
            );
        }
    }
    // The server shells out to curl for its outbound HTTPS calls.
    assert!(
        runtime.body.iter().any(|i| i.contains("apt-get install")
            && i.contains(" curl")
            && i.contains("ca-certificates")),
        "runtime stage must install curl and ca-certificates: the server's outbound calls use them"
    );
}

#[test]
fn copied_context_paths_are_not_dockerignored() {
    let ignore = read("DOCKERIGNORE");
    let ignored: Vec<&str> = ignore
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .collect();
    let (_, all) = stages(&read("DOCKERFILE"));
    let mut sources = Vec::new();
    for s in &all {
        for ins in &s.body {
            let Some(rest) = ins.strip_prefix("COPY ") else {
                continue;
            };
            if rest.starts_with("--from=") {
                continue;
            }
            let words: Vec<&str> = rest.split_whitespace().collect();
            sources.extend(words[..words.len() - 1].iter().map(|w| w.to_string()));
        }
    }
    assert!(
        sources.iter().any(|s| s == "server/"),
        "no COPY of server/: {sources:?}"
    );
    for src in &sources {
        let rel = src.trim_end_matches('/');
        let top = rel.split('/').next().unwrap();
        assert!(
            !ignored.contains(&top) && !ignored.contains(&rel),
            ".dockerignore excludes {src}, which the Dockerfile copies"
        );
    }
}
