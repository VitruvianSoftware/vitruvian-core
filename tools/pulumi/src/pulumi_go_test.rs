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

use crate::tools;

/// Entry point matching pulumi_go_test.sh: cd to the project directory, check
/// for `go`, disable workspace mode and exec `go test ./...`.
pub fn run(args: &[String]) -> i32 {
    let project_dir = match args.first() {
        Some(d) if !d.is_empty() => d.as_str(),
        _ => {
            eprintln!("usage: pulumi_go_test.sh <project_dir>");
            return 1;
        }
    };

    if std::env::set_current_dir(project_dir).is_err() {
        eprintln!("cannot cd to {}", project_dir);
        return 1;
    }

    if !tools::command_on_path("go") {
        eprintln!("go toolchain not found on PATH. This target runs locally only");
        eprintln!("(tagged no-remote-exec) and needs a real 'go' install, same as");
        eprintln!("pulumi_cmd.sh needs 'pulumi' on PATH.");
        return 1;
    }

    std::env::set_var("GOWORK", "off");

    use std::os::unix::process::CommandExt;
    let err = std::process::Command::new("go")
        .args(["test", "./..."])
        .exec();
    eprintln!("exec go test: {}", err);
    1
}
