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

//! Platform application launcher (`Action::LaunchApp`):
//! - macOS: `open -b <bundle_id>` or `open -a <name>`
//! - Linux: `gio launch <path.desktop>` or `gtk-launch <id>`

use crate::injector::InjectorError;
use std::process::Command;

/// Determines whether `target` looks like a macOS reverse-DNS bundle identifier
/// (e.g. `com.apple.Safari` or `dev.vitruvian.wand`) rather than an app name (`Safari` or `Safari.app`).
pub fn is_macos_bundle_id(target: &str) -> bool {
    let trimmed = target.trim();
    !trimmed.is_empty()
        && !trimmed.contains('/')
        && !trimmed.contains(' ')
        && !trimmed.ends_with(".app")
        && trimmed.contains('.')
}

/// Builds the `(program, args)` command tuple to launch `target` on `os` (`"macos"` or `"linux"`).
pub fn build_launch_command(
    os: &str,
    target: &str,
) -> Result<(String, Vec<String>), InjectorError> {
    let trimmed = target.trim();
    if trimmed.is_empty() {
        return Err(InjectorError("empty application target".to_string()));
    }

    if os == "macos" {
        if is_macos_bundle_id(trimmed) {
            Ok((
                "open".to_string(),
                vec!["-b".to_string(), trimmed.to_string()],
            ))
        } else {
            Ok((
                "open".to_string(),
                vec!["-a".to_string(), trimmed.to_string()],
            ))
        }
    } else if trimmed.ends_with(".desktop") || trimmed.contains('/') {
        Ok((
            "gio".to_string(),
            vec!["launch".to_string(), trimmed.to_string()],
        ))
    } else {
        Ok(("gtk-launch".to_string(), vec![trimmed.to_string()]))
    }
}

/// Spawns the platform launcher for `target` without blocking the input thread.
pub fn launch_app(target: &str) -> Result<(), InjectorError> {
    let (program, args) = build_launch_command(std::env::consts::OS, target)?;
    Command::new(&program)
        .args(&args)
        .spawn()
        .map(|_| ())
        .map_err(|e| InjectorError(format!("failed to launch '{target}' via {program}: {e}")))
}
