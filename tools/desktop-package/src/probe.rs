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

//! Test-only: calls the port's helpers one at a time, so package-desktop's
//! shell test and the parity test can hold each to the shell function of the
//! same name.
//!
//!   probe clean_version <raw>
//!   probe cask_name_for_app <name>
//!   probe generate_cask_ruby <cask> <version> <sha> <url> <app> [desc] [homepage]
//!   probe expected_artifact_names <app> <version>
//!   probe required_release_assets <app> <version> [skip_dmg] [skip_thinning] [extra...]
//!   probe missing_assets <required> <present>
//!   probe notary_key_to_file <value> <out>
//!   probe notarize_target <target>

use package_desktop::driver::{Driver, Opts};
use package_desktop::helpers;
use package_desktop::shell::{out, Shell};

fn lines(v: &[String]) {
    for l in v {
        out(l);
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let arg = |i: usize| args.get(i).cloned().unwrap_or_default();
    let driver = || Driver {
        sh: Shell {
            argv0: "package-desktop".to_string(),
        },
        o: Opts::default(),
        program: String::new(),
        stage_root: String::new(),
    };
    let code = match arg(0).as_str() {
        "clean_version" => {
            out(&helpers::clean_version(&arg(1)));
            0
        }
        "cask_name_for_app" => {
            out(&helpers::cask_name_for_app(&arg(1)));
            0
        }
        "generate_cask_ruby" => {
            out(&helpers::generate_cask_ruby(
                &arg(1),
                &arg(2),
                &arg(3),
                &arg(4),
                &arg(5),
                &arg(6),
                &arg(7),
            ));
            0
        }
        "expected_artifact_names" => {
            lines(&helpers::expected_artifact_names(&arg(1), &arg(2)));
            0
        }
        "required_release_assets" => {
            let extra: Vec<String> = args.iter().skip(5).cloned().collect();
            lines(&helpers::required_release_assets(
                &arg(1),
                &arg(2),
                arg(3) == "true",
                arg(4) == "true",
                &extra,
            ));
            0
        }
        "missing_assets" => {
            lines(&helpers::missing_assets(&arg(1), &arg(2)));
            0
        }
        "notary_key_to_file" => match driver().notary_key_to_file(&arg(1), &arg(2)) {
            Ok(()) => 0,
            Err(c) => c,
        },
        "notarize_target" => match driver().notarize_target(&arg(1)) {
            Ok(()) => 0,
            Err(c) => c,
        },
        other => {
            eprintln!("probe: unknown helper '{other}'");
            2
        }
    };
    std::process::exit(code);
}
