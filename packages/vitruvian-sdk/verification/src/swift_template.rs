// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT
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

//! Native Rust port of `packages/vitruvian-sdk/samples/swift_template_test.py`
//! and `packages/vitruvian-sdk/samples/swift_template_cleanup_test.py`.

use std::collections::{BTreeSet, HashMap};
use std::env;
use std::fs;
use std::io::Read;
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use conformance_rs_lib::json::Value;

use crate::{copy_dir_all, find_package_dir, is_executable, lexical_abspath, resolve_runfile};

pub const PACKAGE_PARTS: &[&str] = &["Package.swift", "Sources", "Tests", "samples"];
pub const BUILD_LIMIT: u64 = 600;
pub const COMMAND_LIMIT: u64 = 30;
pub const REMOVE_LIMIT: u64 = 15;

pub const TABLE: &str = "\
/dev/disk3s1s1 on / (apfs, sealed, local, read-only, journaled)
/dev/disk5s1 on /work/t/home/Library/Developer/DVTDownloads/MetalToolchain/mounts/389a (apfs, local, nodev, nosuid, read-only, noowners, mounted by runner)
/dev/disk6s1 on /work/t/home/Library/Developer/DVTDownloads/MetalToolchain/mounts/389a/inner disk (apfs, local, nodev, nosuid, mounted by runner)
/dev/disk7s1 on /work/t-other/x (apfs, local, nodev, nosuid, mounted by runner)
";

extern "C" {
    fn kill(pid: i32, sig: i32) -> i32;
    fn geteuid() -> u32;
    fn getuid() -> u32;
    #[cfg(target_os = "macos")]
    fn confstr(name: i32, buf: *mut u8, len: usize) -> usize;
}

const SIGKILL: i32 = 9;

/// Runs a program to its end, or kills its process group when `limit_secs` passes.
pub fn started(
    words: &[String],
    limit_secs: u64,
    env_map: Option<&HashMap<String, String>>,
    cwd: Option<&Path>,
) -> (Option<i32>, String) {
    let Some((prog, args)) = words.split_first() else {
        return (Some(1), String::new());
    };
    let mut cmd = Command::new(prog);
    cmd.args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .process_group(0);
    if let Some(map) = env_map {
        cmd.env_clear().envs(map);
    }
    if let Some(dir) = cwd {
        cmd.current_dir(dir);
    }
    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => return (Some(1), e.to_string()),
    };
    let mut stdout_pipe = child.stdout.take().expect("stdout");
    let mut stderr_pipe = child.stderr.take().expect("stderr");

    let out_handle = thread::spawn(move || {
        let mut buf = Vec::new();
        let _ = stdout_pipe.read_to_end(&mut buf);
        buf
    });
    let err_handle = thread::spawn(move || {
        let mut buf = Vec::new();
        let _ = stderr_pipe.read_to_end(&mut buf);
        buf
    });

    let deadline = Instant::now() + Duration::from_secs(limit_secs);
    let mut timed_out = false;
    let mut exit_code = None;

    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                exit_code = Some(status.code().unwrap_or(1));
                break;
            }
            Ok(None) => {
                if Instant::now() >= deadline {
                    timed_out = true;
                    unsafe {
                        let _ = kill(-(child.id() as i32), SIGKILL);
                    }
                    let _ = child.wait();
                    break;
                }
                thread::sleep(Duration::from_millis(10));
            }
            Err(_) => break,
        }
    }

    let out_bytes = out_handle.join().unwrap_or_default();
    let err_bytes = err_handle.join().unwrap_or_default();
    let mut printed = format!(
        "{}{}",
        String::from_utf8_lossy(&out_bytes),
        String::from_utf8_lossy(&err_bytes)
    );
    if timed_out {
        printed.push_str(&format!("\nkilled after {limit_secs} seconds"));
        (None, printed)
    } else {
        (exit_code, printed)
    }
}

pub fn swift_environment(root: &Path) -> HashMap<String, String> {
    let home = root.join("home");
    let temporary = root.join("tmp");
    let modules = root.join("modules");
    for folder in [&home, &temporary, &modules] {
        fs::create_dir_all(folder).unwrap();
    }
    let mut environment = HashMap::new();
    environment.insert(
        "PATH".into(),
        env::var("PATH").unwrap_or_else(|_| "/usr/bin:/bin".into()),
    );
    environment.insert(
        "CFFIXED_USER_HOME".into(),
        home.to_string_lossy().into_owned(),
    );
    environment.insert("HOME".into(), home.to_string_lossy().into_owned());
    environment.insert("TMPDIR".into(), temporary.to_string_lossy().into_owned());
    environment.insert(
        "CLANG_MODULE_CACHE_PATH".into(),
        modules.to_string_lossy().into_owned(),
    );
    for name in ["DEVELOPER_DIR", "SDKROOT", "TOOLCHAINS"] {
        if let Ok(val) = env::var(name) {
            environment.insert(name.into(), val);
        }
    }
    environment
}

fn parse_mount_line(line: &str) -> Option<&str> {
    let trimmed = line.trim();
    if !trimmed.ends_with(')') {
        return None;
    }
    let open_paren = trimmed.rfind(" (")?;
    let opts = &trimmed[open_paren + 2..trimmed.len() - 1];
    if opts.contains('(') || opts.contains(')') {
        return None;
    }
    let before_paren = &trimmed[..open_paren];
    let on_pos = before_paren.find(" on /")?;
    if on_pos == 0 {
        return None;
    }
    Some(&before_paren[on_pos + 4..])
}

/// The folders in `mount`'s table that are inside `folder`, the deepest first.
pub fn mounts_under(folder: &Path, table: &str) -> Vec<String> {
    let mut roots = BTreeSet::new();
    roots.insert(lexical_abspath(folder).to_string_lossy().into_owned());
    if let Ok(canon) = fs::canonicalize(folder) {
        roots.insert(canon.to_string_lossy().into_owned());
    }

    let mut inside_set = BTreeSet::new();
    for line in table.lines() {
        let Some(mounted) = parse_mount_line(line) else {
            continue;
        };
        if roots
            .iter()
            .any(|root| mounted.starts_with(&format!("{root}/")))
        {
            inside_set.insert(mounted.to_string());
        }
    }
    let mut inside: Vec<String> = inside_set.into_iter().collect();
    inside.sort_by(|a, b| {
        let depth_a = a.matches('/').count();
        let depth_b = b.matches('/').count();
        depth_b.cmp(&depth_a).then_with(|| a.cmp(b))
    });
    inside
}

pub fn detached(folder: &Path) -> Vec<String> {
    let (status, table) = started(&["/sbin/mount".into()], COMMAND_LIMIT, None, None);
    if status != Some(0) {
        return vec![format!("mount could not list what is mounted:\n{table}")];
    }
    let mut problems = Vec::new();
    for mounted in mounts_under(folder, &table) {
        let (mut status, mut printed) = started(
            &["/usr/bin/hdiutil".into(), "detach".into(), mounted.clone()],
            COMMAND_LIMIT,
            None,
            None,
        );
        if status != Some(0) {
            (status, printed) = started(
                &[
                    "/usr/bin/hdiutil".into(),
                    "detach".into(),
                    "-force".into(),
                    mounted.clone(),
                ],
                COMMAND_LIMIT,
                None,
                None,
            );
        }
        if status != Some(0) {
            problems.push(format!("{mounted} could not be detached:\n{printed}"));
        }
    }
    problems
}

fn rmtree_ignore_errors(path: &Path) {
    let Ok(meta) = fs::symlink_metadata(path) else {
        return;
    };
    if meta.is_dir() && !meta.file_type().is_symlink() {
        if let Ok(entries) = fs::read_dir(path) {
            for entry in entries.flatten() {
                rmtree_ignore_errors(&entry.path());
            }
        }
        let _ = fs::remove_dir(path);
    } else {
        let _ = fs::remove_file(path);
    }
}

fn collect_remaining_relative(root: &Path, cur: &Path, out: &mut Vec<String>) {
    let Ok(entries) = fs::read_dir(cur) else {
        return;
    };
    let mut subdirs = Vec::new();
    for entry in entries.flatten() {
        let p = entry.path();
        if let Ok(rel) = p.strip_prefix(root) {
            out.push(rel.to_string_lossy().into_owned());
        }
        if p.symlink_metadata()
            .is_ok_and(|m| m.is_dir() && !m.file_type().is_symlink())
        {
            subdirs.push(p);
        }
    }
    for sub in subdirs {
        collect_remaining_relative(root, &sub, out);
    }
}

pub fn removed(folder: &Path, limit_secs: u64) -> Vec<String> {
    let deadline = Instant::now() + Duration::from_secs(limit_secs);
    loop {
        rmtree_ignore_errors(folder);
        if fs::symlink_metadata(folder).is_err() {
            return Vec::new();
        }
        if Instant::now() >= deadline {
            let mut left = Vec::new();
            collect_remaining_relative(folder, folder, &mut left);
            left.sort();
            left.truncate(40);
            if left.is_empty() {
                return vec!["(the folder itself)".to_string()];
            }
            return left;
        }
        thread::sleep(Duration::from_millis(500));
    }
}

pub fn system_temp() -> Option<PathBuf> {
    #[cfg(target_os = "macos")]
    {
        // _CS_DARWIN_USER_TEMP_DIR = 65537
        let mut buf = vec![0u8; 4096];
        let len = unsafe { confstr(65537, buf.as_mut_ptr(), buf.len()) };
        if len > 0 && len <= buf.len() {
            let nul_pos = buf.iter().position(|&b| b == 0).unwrap_or(len - 1);
            if let Ok(s) = std::str::from_utf8(&buf[..nul_pos]) {
                return fs::canonicalize(s).ok();
            }
        }
        None
    }
    #[cfg(not(target_os = "macos"))]
    {
        None
    }
}

pub fn swift_leftovers(folder: Option<&Path>) -> BTreeSet<String> {
    let Some(dir) = folder else {
        return BTreeSet::new();
    };
    let Ok(entries) = fs::read_dir(dir) else {
        return BTreeSet::new();
    };
    entries
        .flatten()
        .filter_map(|e| e.file_name().into_string().ok())
        .filter(|name| name.starts_with("TemporaryDirectory."))
        .collect()
}

pub fn sweep(folder: Option<&Path>, before: &BTreeSet<String>, began: i64) {
    let Some(dir) = folder else {
        return;
    };
    let current = swift_leftovers(Some(dir));
    let now_secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    let my_uid = unsafe { getuid() };

    for name in current.difference(before) {
        let path = dir.join(name);
        let Ok(about) = fs::symlink_metadata(&path) else {
            continue;
        };
        let marker = path.join(".keep-directory");
        let mine = about.uid() == my_uid && !about.file_type().is_symlink();
        let young = now_secs - about.mtime() < 2;
        #[cfg(target_os = "macos")]
        let created_before = {
            use std::os::macos::fs::MetadataExt as MacMetadataExt;
            about.st_birthtime() < began
        };
        #[cfg(not(target_os = "macos"))]
        let created_before = false;

        if !mine || young || created_before {
            continue;
        }
        let Ok(entries) = fs::read_dir(&path) else {
            continue;
        };
        let names: Vec<String> = entries
            .flatten()
            .filter_map(|e| e.file_name().into_string().ok())
            .collect();
        if names != vec![".keep-directory".to_string()] {
            continue;
        }
        let Ok(marker_meta) = fs::symlink_metadata(&marker) else {
            continue;
        };
        if marker_meta.len() != 0 {
            continue;
        }
        let _ = fs::remove_file(&marker);
        let _ = fs::remove_dir(&path);
    }
}

fn collect_files_relative(root: &Path, cur: &Path, out: &mut Vec<String>) {
    let Ok(entries) = fs::read_dir(cur) else {
        return;
    };
    for entry in entries.flatten() {
        let p = entry.path();
        if p.is_dir() {
            collect_files_relative(root, &p, out);
        } else if let Ok(rel) = p.strip_prefix(root) {
            out.push(rel.to_string_lossy().into_owned());
        }
    }
}

fn tail_chars(s: &str, max_chars: usize) -> &str {
    let count = s.chars().count();
    if count <= max_chars {
        return s;
    }
    let skip = count - max_chars;
    match s.char_indices().nth(skip) {
        Some((idx, _)) => &s[idx..],
        None => s,
    }
}

pub fn check_swift_template(
    root: &Path,
    command: &Path,
    package_dir: &Path,
    problems: &mut Vec<String>,
) {
    let sdk = root.join("vitruvian-sdk");
    fs::create_dir_all(&sdk).unwrap();
    for &part in PACKAGE_PARTS {
        let source = package_dir.join(part);
        let dst = sdk.join(part);
        if source.is_dir() {
            copy_dir_all(&source, &dst).unwrap();
        } else {
            fs::copy(&source, &dst).unwrap();
        }
    }

    let environment = swift_environment(root);
    let folder = root.join("fresh");
    let cmd_str = command.to_string_lossy().into_owned();
    let (status, printed) = started(
        &[
            cmd_str.clone(),
            "init".into(),
            folder.to_string_lossy().into_owned(),
            "--id".into(),
            "com.example.fresh".into(),
            "--name".into(),
            "Fresh".into(),
            "--publisher".into(),
            "Example".into(),
            "--template".into(),
            "swift".into(),
            "--sdk".into(),
            sdk.to_string_lossy().into_owned(),
        ],
        COMMAND_LIMIT,
        Some(&environment),
        None,
    );
    let script = folder.join("build.sh");
    if status != Some(0) || !is_executable(&script) {
        problems.push(format!("init did not write the Swift template:\n{printed}"));
        return;
    }

    let began = Instant::now();
    let (status, printed) = started(
        &[script.to_string_lossy().into_owned()],
        BUILD_LIMIT,
        Some(&environment),
        Some(root),
    );
    println!("build.sh: {:.0} seconds", began.elapsed().as_secs_f64());

    let tool = folder.join("tool");
    let program = tool.join("bin").join("tool");
    if status != Some(0) || !is_executable(&program) {
        let status_disp = status
            .map(|c| c.to_string())
            .unwrap_or_else(|| "None".to_string());
        problems.push(format!(
            "build.sh did not build the tool (status {status_disp}):\n{}",
            tail_chars(&printed, 6000)
        ));
        return;
    }

    let real_tool = fs::canonicalize(&tool).unwrap_or_else(|_| tool.clone());
    let expected_msg = format!("The folder to add to Vitruvian is {}", real_tool.display());
    if !printed.contains(&expected_msg) {
        problems.push(format!(
            "build.sh does not name the folder to add:\n{}",
            tail_chars(&printed, 2000)
        ));
    }

    let mut inside = Vec::new();
    collect_files_relative(&tool, &tool, &mut inside);
    inside.sort();
    if inside != vec!["bin/tool".to_string(), "vitruvian-tool.json".to_string()] {
        let inside_repr = Value::Arr(inside.into_iter().map(Value::Str).collect()).py_repr();
        problems.push(format!(
            "the built tool's folder holds more than a tool: {inside_repr}"
        ));
    }

    let tool_str = tool.to_string_lossy().into_owned();
    let (status, printed) = started(
        &[cmd_str.clone(), "validate".into(), tool_str.clone()],
        COMMAND_LIMIT,
        Some(&environment),
        None,
    );
    if status != Some(0) || !printed.contains("ok       manifest: com.example.fresh 0.1.0") {
        problems.push(format!(
            "validate does not pass the built Swift tool:\n{printed}"
        ));
    }

    let (status, printed) = started(
        &[
            cmd_str,
            "run".into(),
            tool_str,
            "--command".into(),
            "hello".into(),
        ],
        COMMAND_LIMIT,
        Some(&environment),
        None,
    );
    if status != Some(0) || !printed.contains("ran      hello") || !printed.contains("run: OK") {
        problems.push(format!("the built Swift tool does not run:\n{printed}"));
    }
}

static TEMP_SEQ: AtomicU64 = AtomicU64::new(0);

fn make_unmanaged_temp_dir(prefix: &str) -> PathBuf {
    let base = env::var("TEST_TMPDIR")
        .ok()
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(env::temp_dir);
    let seq = TEMP_SEQ.fetch_add(1, Ordering::Relaxed);
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let path = base.join(format!("{prefix}{}_{}_{}", std::process::id(), nanos, seq));
    fs::create_dir_all(&path).unwrap();
    path
}

pub fn main_swift_template(arguments: &[String]) -> i32 {
    let Some(arg0) = arguments.first() else {
        eprintln!("usage: swift_template_test <vitruvian-tool>");
        return 1;
    };
    let command = resolve_runfile(arg0);
    let package_dir = match find_package_dir() {
        Ok(d) => d,
        Err(e) => {
            eprintln!("{e}");
            return 1;
        }
    };

    let mut problems = Vec::new();
    let began = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64 - 1)
        .unwrap_or(0);
    let system = system_temp();
    let before = swift_leftovers(system.as_deref());
    let root = make_unmanaged_temp_dir("vitruvian-swift-template-");

    check_swift_template(&root, &command, &package_dir, &mut problems);

    problems.extend(detached(&root));
    let left = removed(&root, REMOVE_LIMIT);
    if !left.is_empty() {
        let left_repr = Value::Arr(left.into_iter().map(Value::Str).collect()).py_repr();
        problems.push(format!(
            "the test's folder was not deleted: {}\nstill in it: {left_repr}",
            root.display()
        ));
    }
    thread::sleep(Duration::from_millis(2100));
    sweep(system.as_deref(), &before, began);

    for problem in &problems {
        eprintln!("{problem}");
    }
    println!(
        "swift template: {}",
        if problems.is_empty() { "OK" } else { "FAILED" }
    );
    if problems.is_empty() {
        0
    } else {
        1
    }
}

fn mounted_disk(base: &Path) -> Vec<String> {
    let image = base.join("disk.dmg");
    let folder = base.join("with-disk");
    let point = folder.join("home").join("mounts").join("disk");
    fs::create_dir_all(&point).unwrap();

    let img_str = image.to_string_lossy().into_owned();
    let pt_str = point.to_string_lossy().into_owned();
    for words in [
        vec![
            "hdiutil", "create", "-quiet", "-size", "1m", "-fs", "HFS+", &img_str,
        ],
        vec![
            "hdiutil",
            "attach",
            "-quiet",
            "-nobrowse",
            "-mountpoint",
            &pt_str,
            &img_str,
        ],
    ] {
        let made = Command::new(words[0])
            .args(&words[1..])
            .output()
            .expect("hdiutil");
        if !made.status.success() {
            return vec![format!(
                "could not make a disk to test with: {}",
                String::from_utf8_lossy(&made.stderr)
            )];
        }
    }

    let mut problems = detached(&folder);
    let left = removed(&folder, 5);
    if !left.is_empty() || fs::symlink_metadata(&folder).is_ok() {
        let _ = Command::new("hdiutil")
            .args(["detach", "-force", &pt_str])
            .output();
        let left_repr = Value::Arr(left.into_iter().map(Value::Str).collect()).py_repr();
        problems.push(format!(
            "a folder with a disk mounted in it was not deleted: {left_repr}"
        ));
    }
    problems
}

pub fn main_swift_template_cleanup() -> i32 {
    let mut problems = Vec::new();
    let base = make_unmanaged_temp_dir("vitruvian-swift-cleanup-");

    // 1. Only what is inside the folder, the deepest first; names may hold spaces.
    let found = mounts_under(Path::new("/work/t"), TABLE);
    let mounts = "/work/t/home/Library/Developer/DVTDownloads/MetalToolchain/mounts/389a";
    let expected = vec![format!("{mounts}/inner disk"), mounts.to_string()];
    if found != expected {
        let found_repr = Value::Arr(found.into_iter().map(Value::Str).collect()).py_repr();
        problems.push(format!(
            "the mounts inside the folder were not found: {found_repr}"
        ));
    }

    // 2. A real disk image mounted inside a folder (macOS).
    if cfg!(target_os = "macos") {
        problems.extend(mounted_disk(&base));
    }

    // 3. Something still writing for two seconds: the folder goes all the same.
    let busy = base.join("busy");
    fs::create_dir_all(busy.join("deep").join("deeper")).unwrap();
    let busy_clone = busy.clone();
    let writer_handle = thread::spawn(move || {
        let end = Instant::now() + Duration::from_secs(2);
        let mut count = 0u64;
        while Instant::now() < end {
            let _ = fs::write(busy_clone.join(format!("late-{count}")), "x");
            count += 1;
        }
    });
    thread::sleep(Duration::from_millis(200));
    let left = removed(&busy, 10);
    let _ = writer_handle.join();
    if !left.is_empty() || fs::symlink_metadata(&busy).is_ok() {
        let left_repr = Value::Arr(left.into_iter().map(Value::Str).collect()).py_repr();
        problems.push(format!(
            "a folder being written into was not deleted: {left_repr}"
        ));
    }

    // 4. A folder that cannot go: what is left is named, and nothing waits long.
    if unsafe { geteuid() } != 0 {
        let stuck = base.join("stuck");
        let locked = stuck.join("locked");
        fs::create_dir_all(&locked).unwrap();
        fs::write(locked.join("kept"), "x").unwrap();
        fs::set_permissions(&locked, fs::Permissions::from_mode(0o500)).unwrap();
        let began = Instant::now();
        let left = removed(&stuck, 1);
        let took = began.elapsed().as_secs_f64();
        let _ = fs::set_permissions(&locked, fs::Permissions::from_mode(0o700));
        if left != vec!["locked".to_string(), "locked/kept".to_string()] {
            let left_repr = Value::Arr(left.into_iter().map(Value::Str).collect()).py_repr();
            problems.push(format!(
                "what could not be deleted was not named: {left_repr}"
            ));
        }
        if took > 5.0 {
            problems.push(format!("giving up took {took:.0} seconds, not about one"));
        }
    }

    if !removed(&base, 5).is_empty() {
        problems.push("the test's own folder was not deleted".to_string());
    }

    for problem in &problems {
        eprintln!("{problem}");
    }
    println!(
        "swift template cleanup: {}",
        if problems.is_empty() { "OK" } else { "FAILED" }
    );
    if problems.is_empty() {
        0
    } else {
        1
    }
}
