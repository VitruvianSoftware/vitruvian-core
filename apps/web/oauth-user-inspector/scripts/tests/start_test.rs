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

//! The container entrypoint end to end, in the shape of the runtime image.
//!
//! Regression for #4041: after the Rust cutover (#4039) `dist-server/start`
//! exec'd `node dist-server/server.js`, which the image does not ship, so every
//! Cloud Run revision exited before listening on PORT. The unit tests check the
//! choice of server; this checks the outcome Cloud Run checks: lay out `/app`
//! the way the Dockerfile does (dist/, dist-server/start,
//! dist-server/oauth-user-inspector-server, and no server.js), run `start`
//! with PORT set and with no `node` or `npm` on PATH, and require an HTTP 200
//! on that port.

use std::fs;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

const INDEX_HTML: &str =
    "<!doctype html><title>oauth-user-inspector</title><div id=\"root\"></div>";

/// Kills the server when the test ends, pass or fail.
struct Running(Child);

impl Drop for Running {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

fn runfile(var: &str) -> PathBuf {
    let p = PathBuf::from(std::env::var(var).unwrap_or_else(|_| panic!("{var} unset")));
    fs::canonicalize(&p).unwrap_or_else(|e| panic!("{var}={}: {e}", p.display()))
}

/// `/app` as the runtime stage of the Dockerfile leaves it.
fn image_layout() -> PathBuf {
    let base = std::env::var_os("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir);
    let app = base.join(format!("start-app-{}", std::process::id()));
    let _ = fs::remove_dir_all(&app);
    fs::create_dir_all(app.join("dist/assets")).unwrap();
    fs::create_dir_all(app.join("dist-server")).unwrap();
    fs::write(app.join("dist/index.html"), INDEX_HTML).unwrap();
    // fs::copy keeps the executable bit, as the image's `chmod +x` does.
    fs::copy(runfile("START_BIN"), app.join("dist-server/start")).unwrap();
    fs::copy(
        runfile("SERVER_BIN"),
        app.join("dist-server/oauth-user-inspector-server"),
    )
    .unwrap();
    assert!(!app.join("dist-server/server.js").exists());
    app
}

fn free_port() -> u16 {
    TcpListener::bind("127.0.0.1:0")
        .unwrap()
        .local_addr()
        .unwrap()
        .port()
}

fn get_root(port: u16) -> Option<String> {
    let mut s = TcpStream::connect(("127.0.0.1", port)).ok()?;
    s.set_read_timeout(Some(Duration::from_secs(2))).ok()?;
    s.write_all(b"GET / HTTP/1.0\r\nHost: localhost\r\n\r\n")
        .ok()?;
    let mut buf = String::new();
    let _ = s.read_to_string(&mut buf);
    Some(buf)
}

fn read_log(p: &Path) -> String {
    fs::read_to_string(p).unwrap_or_default()
}

#[test]
fn start_serves_on_port_from_the_image_layout() {
    let app = image_layout();
    let port = free_port();
    // An empty directory as PATH: no `node`, no `npm` (the native server needs
    // neither), and `ls` missing only drops the directory listings.
    let empty_path = app.join("empty-path");
    fs::create_dir_all(&empty_path).unwrap();
    let out = app.join("start.out");
    let err = app.join("start.err");
    let mut child = Running(
        Command::new(app.join("dist-server/start"))
            .current_dir(&app)
            .env_clear()
            .env("PATH", &empty_path)
            .env("PORT", port.to_string())
            .env("NODE_ENV", "production")
            .stdin(Stdio::null())
            .stdout(fs::File::create(&out).unwrap())
            .stderr(fs::File::create(&err).unwrap())
            .spawn()
            .expect("spawn dist-server/start"),
    );

    // Cloud Run's startup probe allows far longer; the native server binds in
    // milliseconds.
    let deadline = Instant::now() + Duration::from_secs(20);
    let response = loop {
        if let Some(status) = child.0.try_wait().unwrap() {
            panic!(
                "dist-server/start exited ({status}) without listening on PORT={port}\n\
                 --- stdout ---\n{}\n--- stderr ---\n{}",
                read_log(&out),
                read_log(&err)
            );
        }
        if let Some(r) = get_root(port) {
            break r;
        }
        assert!(
            Instant::now() < deadline,
            "nothing listening on PORT={port} after 20s\n--- stdout ---\n{}\n--- stderr ---\n{}",
            read_log(&out),
            read_log(&err)
        );
        std::thread::sleep(Duration::from_millis(100));
    };

    let status_line = response.lines().next().unwrap_or_default();
    assert!(
        status_line.contains(" 200"),
        "GET / on PORT={port}: {status_line}\n{response}"
    );
    assert!(response.contains("oauth-user-inspector"), "{response}");
    let log = read_log(&out);
    // The server logs the address its socket is bound to. Cloud Run reaches
    // it on the container's own address, so loopback would serve nothing
    // there, while every request this test makes (over loopback) succeeds.
    assert!(log.contains(r#""address":"0.0.0.0""#), "{log}");
    // The native path never looks for Node (the image ships none, #4176).
    assert!(!log.contains("Node version"), "{log}");
    assert!(!log.contains("NPM version"), "{log}");
    assert!(log.contains(&format!("Port: {port}")), "{log}");
    drop(child);
    let _ = fs::remove_dir_all(&app);
}
