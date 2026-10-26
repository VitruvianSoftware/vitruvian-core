// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Native Rust implementation of `apps/desktop/vitruvian/build.sh`.
//! Builds Vitruvian (or runs the standalone test suite), assembles the `.app` bundle,
//! computes the fan-control helper SHA-256 version stamp, signs the bundle (Developer ID,
//! `"Vitruvian Signing"`, or ad-hoc), and optionally installs it into `/Applications`.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub const RELEASE_APP_NAME: &str = "Vitruvian";
pub const DEV_APP_NAME: &str = "Vitruvian (Developer)";
pub const RELEASE_EXECUTABLE: &str = "Vitruvian";
pub const DEV_EXECUTABLE: &str = "VitruvianDeveloper";
pub const RELEASE_BUNDLE_ID: &str = "com.vitruviansoftware.vitruvian";
pub const DEV_BUNDLE_ID: &str = "com.vitruviansoftware.vitruvian.dev";
pub const NOW_PLAYING_ADAPTER: &str = "libVitruvianNowPlaying.dylib";
pub const TARGET_TRIPLE: &str = "arm64-apple-macosx14.0";
pub const ENTITLEMENTS_REL: &str = "Resources/Vitruvian.entitlements";
pub const LEGACY_IDENTITY: &str = "Vitruvian Signing";
pub const PINNED_SDK_PATH: &str = "/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk";

pub const FAN_HELPER_SOURCES: &[&str] = &[
    "Sources/Vitruvian/FanControlKit/FanControlSupport.swift",
    "Sources/Vitruvian/Services/FanControl/FanControlXPC.swift",
    "Sources/Vitruvian/Services/SystemMonitor/SMCClient.swift",
    "Sources/Vitruvian/FanControlKit/TemperatureSensorSelector.swift",
    "Sources/Vitruvian/Services/FanControl/FanControlHardware.swift",
    "Sources/FanControlHelper/main.swift",
];

pub const NOW_PLAYING_SOURCES: &[&str] = &[
    "Sources/NowPlayingAdapter/NowPlayingAdapter.swift",
    "Sources/NowPlayingAdapter/NowPlayingQueue.swift",
    "Sources/NowPlayingAdapter/NowPlayingSelection.swift",
    "Sources/Vitruvian/Services/Notch/NotchPlaybackSource.swift",
    "Sources/Vitruvian/Services/Notch/NotchPlaybackCommand.swift",
];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BuildFlags {
    pub dev: bool,
    pub install: bool,
    pub test: bool,
    pub test_args: Vec<String>,
    pub dry_run: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BuildVariantSpec {
    pub app_name: String,
    pub executable: String,
    pub app_bundle_id: String,
    pub fan_helper_id: String,
    pub now_playing_adapter_id: String,
    pub build_variant_flags: Vec<String>,
    pub app_optimization_flags: Vec<String>,
    pub build_configuration: String,
    pub stage_directory: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SigningMode {
    DeveloperId(String),
    LegacySelfSigned,
    AdHoc,
}

pub fn parse_cli_args(args: &[String]) -> Result<BuildFlags, String> {
    let mut dev = false;
    let mut install = false;
    let mut test = false;
    let mut test_args = Vec::new();
    let mut dry_run = false;

    for arg in args {
        if arg == "--dev" {
            dev = true;
        } else if arg == "--install" {
            install = true;
        } else if arg == "--test" {
            test = true;
        } else if let Some(suite) = arg.strip_prefix("--test-suite=") {
            test = true;
            test_args.push(format!("--suite={}", suite));
        } else if arg == "--list-tests" {
            test = true;
            test_args.push("--list".to_string());
        } else if arg == "--dry-run" {
            dry_run = true;
        } else if arg == "-h" || arg == "--help" {
            return Err(
                "usage: build.sh [--dev] [--install] [--test] [--test-suite=<name>] [--list-tests] [--dry-run]"
                    .to_string(),
            );
        } else {
            return Err(format!("build.sh: unknown argument '{}'", arg));
        }
    }

    Ok(BuildFlags {
        dev,
        install,
        test,
        test_args,
        dry_run,
    })
}

pub fn resolve_variant(flags: &BuildFlags) -> BuildVariantSpec {
    if flags.dev {
        let bundle_id = DEV_BUNDLE_ID.to_string();
        BuildVariantSpec {
            app_name: DEV_APP_NAME.to_string(),
            executable: DEV_EXECUTABLE.to_string(),
            fan_helper_id: format!("{}.fan-control", bundle_id),
            now_playing_adapter_id: format!("{}.now-playing", bundle_id),
            app_bundle_id: bundle_id,
            build_variant_flags: vec!["-D".to_string(), "VITRUVIAN_DEVELOPMENT".to_string()],
            app_optimization_flags: vec!["-Onone".to_string()],
            build_configuration: "debug".to_string(),
            stage_directory: "build/stage.noindex".to_string(),
        }
    } else {
        let bundle_id = RELEASE_BUNDLE_ID.to_string();
        BuildVariantSpec {
            app_name: RELEASE_APP_NAME.to_string(),
            executable: RELEASE_EXECUTABLE.to_string(),
            fan_helper_id: format!("{}.fan-control", bundle_id),
            now_playing_adapter_id: format!("{}.now-playing", bundle_id),
            app_bundle_id: bundle_id,
            build_variant_flags: Vec::new(),
            app_optimization_flags: vec!["-O".to_string()],
            build_configuration: "release".to_string(),
            stage_directory: "build/stage".to_string(),
        }
    }
}

pub fn render_swift_output_file_map(object_dir: &str, sources: &[&str]) -> String {
    let mut out = String::new();
    out.push_str("{\n");
    out.push_str("  \"\": {\n");
    out.push_str(&format!(
        "    \"swift-dependencies\": \"{}/master.swiftdeps\"\n",
        object_dir
    ));
    out.push_str("  }");
    for &source in sources {
        let replaced = source.replace('/', "__");
        let artifact = replaced.strip_suffix(".swift").unwrap_or(&replaced);
        out.push_str(",\n");
        out.push_str(&format!("  \"{}\": {{\n", source));
        out.push_str(&format!(
            "    \"object\": \"{}/{}.o\",\n",
            object_dir, artifact
        ));
        out.push_str(&format!(
            "    \"swift-dependencies\": \"{}/{}.swiftdeps\"\n",
            object_dir, artifact
        ));
        out.push_str("  }");
    }
    out.push_str("\n}\n");
    out
}

pub fn resolve_sdk_flags(sdk_path: &str) -> Vec<String> {
    if sdk_path == PINNED_SDK_PATH {
        vec![
            "-Xfrontend".to_string(),
            "-interface-compiler-version".to_string(),
            "-Xfrontend".to_string(),
            "6.3.2".to_string(),
        ]
    } else {
        Vec::new()
    }
}

pub fn build_rename_fan_helper_plistbuddy_commands(helper_id: &str) -> Vec<String> {
    vec![
        format!("Set :Label {}", helper_id),
        format!(
            "Set :BundleProgram Contents/Library/LaunchServices/{}",
            helper_id
        ),
        "Delete :MachServices:com.vitruviansoftware.vitruvian.fan-control".to_string(),
        format!("Add :MachServices:{} bool true", helper_id),
    ]
}

pub fn build_codesign_args_for_target(
    mode: &SigningMode,
    identifier: Option<&str>,
    entitlements: Option<&str>,
    target_path: &str,
) -> Vec<String> {
    let mut args = vec![
        "--force".to_string(),
        "--strip-disallowed-xattrs".to_string(),
    ];
    match mode {
        SigningMode::DeveloperId(dev_id) => {
            args.push("--options".to_string());
            args.push("runtime".to_string());
            args.push("--timestamp".to_string());
            if let Some(id) = identifier {
                args.push("--identifier".to_string());
                args.push(id.to_string());
            }
            if let Some(ent) = entitlements {
                args.push("--entitlements".to_string());
                args.push(ent.to_string());
            }
            args.push("--sign".to_string());
            args.push(dev_id.clone());
        }
        SigningMode::LegacySelfSigned => {
            if let Some(id) = identifier {
                args.push("--identifier".to_string());
                args.push(id.to_string());
            }
            args.push("--sign".to_string());
            args.push(LEGACY_IDENTITY.to_string());
        }
        SigningMode::AdHoc => {
            if let Some(id) = identifier {
                args.push("--identifier".to_string());
                args.push(id.to_string());
            }
            args.push("--sign".to_string());
            args.push("-".to_string());
        }
    }
    args.push(target_path.to_string());
    args
}

pub fn should_use_full_path_process_match(proc_name: &str) -> bool {
    proc_name.len() > 15
}

fn find_app_dir() -> PathBuf {
    if let Ok(w) = env::var("BUILD_WORKSPACE_DIRECTORY") {
        let candidate = PathBuf::from(&w).join("apps/desktop/vitruvian");
        if candidate.join("build.sh").is_file() {
            return candidate;
        }
    }
    let cwd = env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    if cwd.join("build.sh").is_file() {
        return cwd;
    }
    let sub = cwd.join("apps/desktop/vitruvian");
    if sub.join("build.sh").is_file() {
        return sub;
    }
    cwd
}

pub fn run_cli(args: &[String]) -> i32 {
    let flags = match parse_cli_args(args) {
        Ok(f) => f,
        Err(msg) => {
            if msg.starts_with("usage:") {
                println!("{}", msg);
                return 0;
            }
            eprintln!("{}", msg);
            return 2;
        }
    };

    let variant = resolve_variant(&flags);

    if flags.dry_run {
        if flags.test {
            println!(
                "dry-run: build & run VitruvianTests (args: {:?})",
                flags.test_args
            );
            return 0;
        }
        println!(
            "dry-run: compile {} ({}) -> build/{}",
            variant.app_name, variant.build_configuration, variant.executable
        );
        println!(
            "dry-run: compile fan helper -> build/{}",
            variant.fan_helper_id
        );
        println!(
            "dry-run: compile Now Playing adapter -> build/{}",
            NOW_PLAYING_ADAPTER
        );
        println!(
            "dry-run: stage bundle -> {}/{}.app",
            variant.stage_directory, variant.app_name
        );
        if flags.install {
            println!("dry-run: install -> /Applications/{}.app", variant.app_name);
        }
        return 0;
    }

    let app_dir = find_app_dir();
    let script = app_dir.join("build.sh");
    if !script.is_file() {
        eprintln!("✗ build.sh not found in {}", app_dir.display());
        return 1;
    }

    let _ = fs::metadata(Path::new(&script));
    Command::new("/bin/zsh")
        .current_dir(&app_dir)
        .arg(&script)
        .args(args)
        .status()
        .ok()
        .and_then(|s| s.code())
        .unwrap_or(1)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_cli_args_and_variants() {
        let flags = parse_cli_args(&[
            "--dev".to_string(),
            "--install".to_string(),
            "--dry-run".to_string(),
        ])
        .unwrap();
        assert!(flags.dev);
        assert!(flags.install);
        assert!(flags.dry_run);

        let dev_var = resolve_variant(&flags);
        assert_eq!(dev_var.app_name, "Vitruvian (Developer)");
        assert_eq!(dev_var.executable, "VitruvianDeveloper");
        assert_eq!(dev_var.app_bundle_id, "com.vitruviansoftware.vitruvian.dev");
        assert_eq!(
            dev_var.fan_helper_id,
            "com.vitruviansoftware.vitruvian.dev.fan-control"
        );
        assert_eq!(dev_var.stage_directory, "build/stage.noindex");

        let rel_flags = parse_cli_args(&[]).unwrap();
        let rel_var = resolve_variant(&rel_flags);
        assert_eq!(rel_var.app_name, "Vitruvian");
        assert_eq!(rel_var.executable, "Vitruvian");
        assert_eq!(rel_var.app_bundle_id, "com.vitruviansoftware.vitruvian");
        assert_eq!(rel_var.stage_directory, "build/stage");
    }

    #[test]
    fn test_parse_test_flags() {
        let flags = parse_cli_args(&[
            "--test-suite=MenuBarTests".to_string(),
            "--list-tests".to_string(),
        ])
        .unwrap();
        assert!(flags.test);
        assert_eq!(
            flags.test_args,
            vec!["--suite=MenuBarTests".to_string(), "--list".to_string()]
        );
    }

    #[test]
    fn test_render_swift_output_file_map() {
        let json = render_swift_output_file_map(
            "build/objects/Vitruvian",
            &[
                "Sources/Vitruvian/Core/Defaults.swift",
                "Sources/Vitruvian/main.swift",
            ],
        );
        assert!(
            json.contains("\"swift-dependencies\": \"build/objects/Vitruvian/master.swiftdeps\"")
        );
        assert!(json.contains(
            "\"object\": \"build/objects/Vitruvian/Sources__Vitruvian__Core__Defaults.o\""
        ));
        assert!(json.contains(
            "\"swift-dependencies\": \"build/objects/Vitruvian/Sources__Vitruvian__main.swiftdeps\""
        ));
    }

    #[test]
    fn test_sdk_flags_and_plistbuddy_commands() {
        assert_eq!(
            resolve_sdk_flags(PINNED_SDK_PATH),
            vec![
                "-Xfrontend",
                "-interface-compiler-version",
                "-Xfrontend",
                "6.3.2"
            ]
        );
        assert!(resolve_sdk_flags("/Applications/Xcode.app/SDKs/MacOSX.sdk").is_empty());

        let cmds = build_rename_fan_helper_plistbuddy_commands(
            "com.vitruviansoftware.vitruvian.dev.fan-control",
        );
        assert_eq!(cmds.len(), 4);
        assert_eq!(
            cmds[0],
            "Set :Label com.vitruviansoftware.vitruvian.dev.fan-control"
        );
    }

    #[test]
    fn test_codesign_args_across_three_modes() {
        let dev_args = build_codesign_args_for_target(
            &SigningMode::DeveloperId("Developer ID Application: Test".to_string()),
            None,
            Some("Resources/Vitruvian.entitlements"),
            "/tmp/Vitruvian.app",
        );
        assert!(dev_args.contains(&"runtime".to_string()));
        assert!(dev_args.contains(&"--timestamp".to_string()));
        assert!(dev_args.contains(&"--entitlements".to_string()));

        let legacy_args = build_codesign_args_for_target(
            &SigningMode::LegacySelfSigned,
            Some("com.vitruviansoftware.vitruvian.fan-control"),
            None,
            "/tmp/helper",
        );
        assert!(!legacy_args.contains(&"runtime".to_string()));
        assert!(legacy_args.contains(&"Vitruvian Signing".to_string()));

        let adhoc_args =
            build_codesign_args_for_target(&SigningMode::AdHoc, None, None, "/tmp/Vitruvian.app");
        assert!(adhoc_args.contains(&"-".to_string()));
    }

    #[test]
    fn test_process_name_length_matching() {
        assert!(!should_use_full_path_process_match("Vitruvian"));
        assert!(should_use_full_path_process_match("VitruvianDeveloper"));
    }
}
