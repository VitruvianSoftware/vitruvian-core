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

use std::env;

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();

    if args.iter().any(|a| a == "--list") {
        for profile in app_profiles::PROFILES {
            println!(
                "{}: {} ({} buttons)",
                profile.name,
                profile.app,
                profile.buttons.len()
            );
        }
        return;
    }

    let (bundle_id, app_name) = if args.len() >= 2 {
        (args[0].as_str(), args[1].as_str())
    } else if args.len() == 1 {
        ("", args[0].as_str())
    } else {
        let (b, n) = app_profiles::get_frontmost_app();
        let profile = app_profiles::get_profile_for_bundle_and_name(&b, &n);
        println!("{}", app_profiles::build_app_payload(profile));
        return;
    };

    let profile = app_profiles::get_profile_for_bundle_and_name(bundle_id, app_name);
    println!("{}", app_profiles::build_app_payload(profile));
}
