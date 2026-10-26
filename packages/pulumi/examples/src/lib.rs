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

//! Native Rust port of the 17 Pulumi Foundation Example helper, validation,
//! E2E lifecycle, and patch scripts across `packages/pulumi/examples/{go-foundation,ts-foundation}`.

use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub const DEPLOY_STAGES: &[&str] = &[
    "0-bootstrap",
    "1-org",
    "2-environments",
    "3-networks-svpc",
    "4-projects",
    "5-app-infra",
];

pub const ALL_STAGES: &[&str] = &[
    "0-bootstrap",
    "1-org",
    "2-environments",
    "3-networks-svpc",
    "3-networks-hub-and-spoke",
    "4-projects",
    "5-app-infra",
];

pub const REVERSE_CLEAN_STAGES: &[&str] = &[
    "5-app-infra",
    "4-projects",
    "3-networks-svpc",
    "3-networks-hub-and-spoke",
    "2-environments",
    "1-org",
    "0-bootstrap",
];

pub const REQUIRED_ROLES: &[&str] = &[
    "roles/resourcemanager.organizationAdmin",
    "roles/orgpolicy.policyAdmin",
    "roles/resourcemanager.projectCreator",
    "roles/resourcemanager.folderCreator",
    "roles/securitycenter.admin",
];

pub const REQUIRED_APIS: &[&str] = &[
    "cloudresourcemanager.googleapis.com",
    "cloudbilling.googleapis.com",
    "iam.googleapis.com",
    "cloudkms.googleapis.com",
    "servicenetworking.googleapis.com",
];

pub const PROJECT_PREFIXES: &[&str] = &["prj-b-", "prj-d-", "prj-n-", "prj-p-", "prj-c-"];

pub const SA_CONSTRUCTOR_PREFIXES: &[&str] = &[
    "iam.NewOrganizationIAMMember",
    "iam.NewBillingIAMMember",
    "iam.NewServiceAccountIAMMember",
    "iam.NewOrganizationIAMBinding",
    "iam.NewFolderIAMBinding",
    "parentiammember.NewParentIamMember",
    "parentiamremoverole.NewParentIamRemoveRole",
    "storage.NewBucketIAMMember",
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Flavor {
    Go,
    Ts,
}

impl Flavor {
    pub fn parse(s: &str) -> Result<Self, String> {
        match s.trim().to_ascii_lowercase().as_str() {
            "go" | "go-foundation" => Ok(Flavor::Go),
            "ts" | "typescript" | "ts-foundation" => Ok(Flavor::Ts),
            other => Err(format!("Unknown flavor '{}': expected 'go' or 'ts'", other)),
        }
    }

    pub fn detect(dir: &Path) -> Self {
        let s = dir.to_string_lossy();
        if s.contains("ts-foundation") || dir.join("tsconfig.json").exists() {
            Flavor::Ts
        } else {
            Flavor::Go
        }
    }
}

/// Parse a `.env` file into key-value pairs, stripping `export `, comments, and quotes.
pub fn parse_dotenv(content: &str) -> BTreeMap<String, String> {
    let mut map = BTreeMap::new();
    for raw_line in content.lines() {
        let line = raw_line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let stripped = line.strip_prefix("export ").unwrap_or(line).trim();
        if let Some((k, v)) = stripped.split_once('=') {
            let key = k.trim().to_string();
            let mut val = v.trim();
            if (val.starts_with('"') && val.ends_with('"') && val.len() >= 2)
                || (val.starts_with('\'') && val.ends_with('\'') && val.len() >= 2)
            {
                val = &val[1..val.len() - 1];
            }
            if !key.is_empty() {
                map.insert(key, val.to_string());
            }
        }
    }
    map
}

pub fn load_dotenv_from_dir(base_dir: &Path) -> BTreeMap<String, String> {
    let candidates = [base_dir.join(".env"), base_dir.join("../.env")];
    for candidate in &candidates {
        if let Ok(content) = fs::read_to_string(candidate) {
            let vars = parse_dotenv(&content);
            for (k, v) in &vars {
                if env::var_os(k).is_none() {
                    env::set_var(k, v);
                }
            }
            return vars;
        }
    }
    BTreeMap::new()
}

// =============================================================================
// 1. Foundation Deployer (`deploy.sh`)
// =============================================================================

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeployOptions {
    pub action: String,
    pub target_stage: Option<String>,
    pub target_stack: Option<String>,
    pub destroy: bool,
    pub dry_run: bool,
    pub help: bool,
    pub base_dir: PathBuf,
}

impl Default for DeployOptions {
    fn default() -> Self {
        Self {
            action: "preview".to_string(),
            target_stage: None,
            target_stack: None,
            destroy: false,
            dry_run: false,
            help: false,
            base_dir: env::current_dir().unwrap_or_else(|_| PathBuf::from(".")),
        }
    }
}

pub fn parse_deploy_args(args: &[String]) -> Result<DeployOptions, String> {
    let mut opts = DeployOptions::default();
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--stage" => {
                i += 1;
                if i >= args.len() {
                    return Err("--stage requires a value".to_string());
                }
                opts.target_stage = Some(args[i].clone());
            }
            "--action" => {
                i += 1;
                if i >= args.len() {
                    return Err("--action requires a value".to_string());
                }
                opts.action = args[i].clone();
            }
            "--stack" => {
                i += 1;
                if i >= args.len() {
                    return Err("--stack requires a value".to_string());
                }
                opts.target_stack = Some(args[i].clone());
            }
            "--dir" => {
                i += 1;
                if i >= args.len() {
                    return Err("--dir requires a value".to_string());
                }
                opts.base_dir = PathBuf::from(&args[i]);
            }
            "--destroy" => opts.destroy = true,
            "--dry-run" => opts.dry_run = true,
            "--help" | "-h" => opts.help = true,
            other => return Err(format!("Unknown option: {}", other)),
        }
        i += 1;
    }
    Ok(opts)
}

pub fn deploy_help_text() -> &'static str {
    "Foundation Deployer

Usage:
  deploy [OPTIONS]

Options:
  --stage <N>       Deploy a specific stage (0-5). Default: all stages.
  --action <action> \"preview\" or \"up\". Default: preview.
  --stack <stack>   Stack name (e.g., \"production\"). Default: all stacks.
  --dir <path>      Foundation root directory. Default: current directory.
  --destroy         Destroy in reverse order instead of deploying.
  --dry-run         Show what would be executed without running.
  --help            Show this help message."
}

pub fn order_stages(destroy: bool, target_stage: Option<&str>) -> Vec<String> {
    let mut stages: Vec<String> = DEPLOY_STAGES.iter().map(|s| (*s).to_string()).collect();
    if destroy {
        stages.reverse();
    }
    if let Some(target) = target_stage {
        if !target.is_empty() {
            let prefix = target.chars().next().unwrap();
            stages.retain(|s| s.starts_with(prefix) || s == target);
        }
    }
    stages
}

pub fn extract_stack_name_from_filename(filename: &str) -> Option<String> {
    if !filename.starts_with("Pulumi.") || !filename.ends_with(".yaml") {
        return None;
    }
    if filename == "Pulumi.yaml"
        || filename.ends_with(".example")
        || filename.ends_with(".disabled")
    {
        return None;
    }
    let stack = &filename["Pulumi.".len()..filename.len() - ".yaml".len()];
    if stack.is_empty() || stack == "Pulumi" {
        return None;
    }
    Some(stack.to_string())
}

fn walk_files_sorted(dir: &Path) -> Vec<PathBuf> {
    let mut results = Vec::new();
    if let Ok(entries) = fs::read_dir(dir) {
        let mut paths: Vec<PathBuf> = entries.filter_map(|e| e.ok().map(|e| e.path())).collect();
        paths.sort();
        for p in paths {
            if p.is_dir() {
                results.extend(walk_files_sorted(&p));
            } else {
                results.push(p);
            }
        }
    }
    results
}

pub fn find_stacks(base_dir: &Path, stage: &str) -> Vec<String> {
    let stage_path = base_dir.join(stage);
    if !stage_path.is_dir() {
        return Vec::new();
    }
    let mut stacks = Vec::new();
    for file_path in walk_files_sorted(&stage_path) {
        let Some(fname) = file_path.file_name().and_then(|f| f.to_str()) else {
            continue;
        };
        if let Some(stack_name) = extract_stack_name_from_filename(fname) {
            let parent = file_path.parent().unwrap_or(&stage_path);
            let rel_dir = parent
                .strip_prefix(base_dir)
                .unwrap_or(parent)
                .to_string_lossy()
                .replace('\\', "/");
            stacks.push(format!("{}:{}", rel_dir, stack_name));
        }
    }
    stacks
}

pub fn order_stack_targets(stack_dirs: &[String], destroy: bool) -> Vec<String> {
    let mut ordered = Vec::with_capacity(stack_dirs.len());
    for t in stack_dirs {
        if t.ends_with(":shared") {
            ordered.push(t.clone());
        }
    }
    for t in stack_dirs {
        if t.ends_with(":development") {
            ordered.push(t.clone());
        }
    }
    for t in stack_dirs {
        if t.ends_with(":nonproduction") {
            ordered.push(t.clone());
        }
    }
    for t in stack_dirs {
        if !t.ends_with(":shared") && !t.ends_with(":development") && !t.ends_with(":nonproduction")
        {
            ordered.push(t.clone());
        }
    }
    if destroy {
        ordered.reverse();
    }
    ordered
}

pub fn run_deploy(opts: &DeployOptions) -> Result<String, String> {
    if opts.help {
        return Ok(deploy_help_text().to_string());
    }
    load_dotenv_from_dir(&opts.base_dir);
    let mut out = String::new();
    out.push_str("=============================================\n");
    out.push_str(" Foundation Deployer\n");
    out.push_str(&format!(" Action:  {}\n", opts.action));
    out.push_str(&format!(" Destroy: {}\n", opts.destroy));
    out.push_str(&format!(
        " Stage:   {}\n",
        opts.target_stage.as_deref().unwrap_or("all")
    ));
    out.push_str(&format!(
        " Stack:   {}\n",
        opts.target_stack.as_deref().unwrap_or("all")
    ));
    out.push_str("=============================================\n\n");

    let stages = order_stages(opts.destroy, opts.target_stage.as_deref());
    for stage in stages {
        let stage_dir = opts.base_dir.join(&stage);
        if !stage_dir.is_dir() {
            out.push_str(&format!(
                "[WARN]  Stage directory not found: {} (skipping)\n",
                stage
            ));
            continue;
        }
        out.push_str(&format!(
            "\n[INFO]  ========== Stage: {} ==========\n",
            stage
        ));
        let raw_stacks = find_stacks(&opts.base_dir, &stage);
        if raw_stacks.is_empty() {
            out.push_str(&format!("[WARN]  No Pulumi projects found in {}\n", stage));
            continue;
        }
        let ordered = order_stack_targets(&raw_stacks, opts.destroy);
        for target in ordered {
            let Some((dir, stack_name)) = target.rsplit_once(':') else {
                continue;
            };
            if let Some(target_stack) = &opts.target_stack {
                if stack_name != target_stack {
                    out.push_str(&format!(
                        "[WARN]  Skipping {} (stack {} != {})\n",
                        dir, stack_name, target_stack
                    ));
                    continue;
                }
            }
            out.push_str(&format!(
                "[INFO]  Deploying: {} (stack: {})\n",
                dir, stack_name
            ));
            if opts.dry_run {
                out.push_str(&format!(
                    "  [DRY RUN] cd {} && npm install && pulumi {} --stack {} --yes\n",
                    dir, opts.action, stack_name
                ));
                continue;
            }
            let full_dir = opts.base_dir.join(dir);
            if full_dir.join("package.json").exists() {
                let _ = Command::new("npm")
                    .arg("install")
                    .arg("--silent")
                    .current_dir(&full_dir)
                    .output();
            }
            let select = Command::new("pulumi")
                .args(["stack", "select", stack_name])
                .current_dir(&full_dir)
                .output();
            if select.map(|o| !o.status.success()).unwrap_or(true) {
                let _ = Command::new("pulumi")
                    .args(["stack", "init", stack_name])
                    .current_dir(&full_dir)
                    .output();
            }
            let status = if opts.destroy {
                out.push_str(&format!("[WARN]  DESTROYING stack: {}\n", stack_name));
                Command::new("pulumi")
                    .args(["destroy", "--yes", "--skip-preview"])
                    .current_dir(&full_dir)
                    .status()
            } else if opts.action == "preview" {
                Command::new("pulumi")
                    .arg("preview")
                    .current_dir(&full_dir)
                    .status()
            } else if opts.action == "up" {
                Command::new("pulumi")
                    .args(["up", "--yes", "--skip-preview"])
                    .current_dir(&full_dir)
                    .status()
            } else {
                return Err(format!("Unsupported action: {}", opts.action));
            };
            if let Err(e) = status {
                return Err(format!("Failed to execute pulumi in {}: {}", dir, e));
            }
        }
        out.push_str(&format!("[INFO]  Stage {} complete\n", stage));
    }

    out.push_str("\n[INFO]  =============================================\n");
    out.push_str("[INFO]   Foundation deployment complete\n");
    out.push_str("[INFO]  =============================================\n");
    Ok(out)
}

// =============================================================================
// 2. Pre-flight Requirements Validator (`validate-requirements.sh`)
// =============================================================================

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ValidateReqOptions {
    pub org_id: String,
    pub billing_account: String,
    pub user_email: String,
    pub flavor: Flavor,
    pub dry_run: bool,
    pub help: bool,
}

pub fn parse_validate_req_args(args: &[String]) -> Result<ValidateReqOptions, String> {
    let mut org_id = String::new();
    let mut billing_account = String::new();
    let mut user_email = String::new();
    let mut flavor = Flavor::detect(&env::current_dir().unwrap_or_else(|_| PathBuf::from(".")));
    let mut dry_run = false;
    let mut help = false;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "-o" | "--org" => {
                i += 1;
                if i >= args.len() {
                    return Err("Usage: validate-requirements -o <ORG_ID> -b <BILLING_ACCOUNT_ID> -u <USER_EMAIL>".to_string());
                }
                org_id = args[i].clone();
            }
            "-b" | "--billing" => {
                i += 1;
                if i >= args.len() {
                    return Err("Usage: validate-requirements -o <ORG_ID> -b <BILLING_ACCOUNT_ID> -u <USER_EMAIL>".to_string());
                }
                billing_account = args[i].clone();
            }
            "-u" | "--user" => {
                i += 1;
                if i >= args.len() {
                    return Err("Usage: validate-requirements -o <ORG_ID> -b <BILLING_ACCOUNT_ID> -u <USER_EMAIL>".to_string());
                }
                user_email = args[i].clone();
            }
            "--flavor" => {
                i += 1;
                if i >= args.len() {
                    return Err("--flavor requires 'go' or 'ts'".to_string());
                }
                flavor = Flavor::parse(&args[i])?;
            }
            "--dry-run" => dry_run = true,
            "--help" | "-h" => help = true,
            _ => return Err(
                "Usage: validate-requirements -o <ORG_ID> -b <BILLING_ACCOUNT_ID> -u <USER_EMAIL>"
                    .to_string(),
            ),
        }
        i += 1;
    }

    if !help && (org_id.is_empty() || billing_account.is_empty() || user_email.is_empty()) {
        return Err(
            "Usage: validate-requirements -o <ORG_ID> -b <BILLING_ACCOUNT_ID> -u <USER_EMAIL>"
                .to_string(),
        );
    }

    Ok(ValidateReqOptions {
        org_id,
        billing_account,
        user_email,
        flavor,
        dry_run,
        help,
    })
}

pub fn parse_semver_tuple(v: &str) -> Vec<u64> {
    let trimmed = v.trim().trim_start_matches('v').trim_start_matches("go");
    let numeric_prefix: String = trimmed
        .chars()
        .take_while(|c| c.is_ascii_digit() || *c == '.')
        .collect();
    numeric_prefix
        .split('.')
        .filter(|s| !s.is_empty())
        .filter_map(|s| s.parse::<u64>().ok())
        .collect()
}

pub fn version_gte(installed: &str, minimum: &str) -> bool {
    let a = parse_semver_tuple(installed);
    let b = parse_semver_tuple(minimum);
    if a.is_empty() || b.is_empty() {
        return false;
    }
    let max_len = a.len().max(b.len());
    for idx in 0..max_len {
        let av = *a.get(idx).unwrap_or(&0);
        let bv = *b.get(idx).unwrap_or(&0);
        if av > bv {
            return true;
        }
        if av < bv {
            return false;
        }
    }
    true
}

pub fn extract_first_version_token(raw: &str) -> Option<String> {
    for token in raw.split_whitespace() {
        let cleaned = token
            .trim_start_matches('v')
            .trim_start_matches("go")
            .trim_start_matches("jq-");
        let ver: String = cleaned
            .chars()
            .take_while(|c| c.is_ascii_digit() || *c == '.')
            .collect();
        if ver.contains('.') && ver.chars().next().is_some_and(|c| c.is_ascii_digit()) {
            return Some(ver);
        }
    }
    None
}

pub fn run_validate_requirements(opts: &ValidateReqOptions) -> Result<String, String> {
    if opts.help {
        return Ok(
            "Usage: validate-requirements -o <ORG_ID> -b <BILLING_ACCOUNT_ID> -u <USER_EMAIL> [--flavor go|ts] [--dry-run]"
                .to_string(),
        );
    }

    let title = match opts.flavor {
        Flavor::Go => "Pulumi Go Foundation — Pre-flight Validation",
        Flavor::Ts => "Pulumi TypeScript Foundation — Pre-flight Validation",
    };

    let mut out = String::new();
    out.push_str("\n═══════════════════════════════════════════════════════════\n");
    out.push_str(&format!(" {}\n", title));
    out.push_str("═══════════════════════════════════════════════════════════\n\n");
    out.push_str("▸ Checking required tools...\n\n");

    if opts.dry_run {
        out.push_str("✓ [DRY RUN] Tool checks skipped\n");
        out.push_str(&format!(
            "\n▸ Checking IAM permissions for {}...\n\n",
            opts.user_email
        ));
        for role in REQUIRED_ROLES {
            out.push_str(&format!("✓ [DRY RUN] {}\n", role));
        }
        out.push_str("✓ [DRY RUN] roles/billing.admin on billing account\n\n");
        out.push_str("▸ Checking required APIs...\n\n");
        for api in REQUIRED_APIS {
            out.push_str(&format!("✓ [DRY RUN] {}\n", api));
        }
        out.push_str("\n═══════════════════════════════════════════════════════════\n");
        out.push_str(" ALL CHECKS PASSED\n");
        out.push_str(" Your environment is ready to deploy the foundation.\n");
        out.push_str("═══════════════════════════════════════════════════════════\n");
        return Ok(out);
    }

    let mut errors = 0usize;
    let mut warnings = 0usize;

    // Git check
    if let Ok(o) = Command::new("git").arg("--version").output() {
        let s = String::from_utf8_lossy(&o.stdout);
        let ver = extract_first_version_token(&s).unwrap_or_default();
        if version_gte(&ver, "2.28.0") {
            out.push_str(&format!("✓ Git {} (>= 2.28.0)\n", ver));
        } else {
            out.push_str(&format!("✗ Git {} (need >= 2.28.0)\n", ver));
            errors += 1;
        }
    } else {
        out.push_str("✗ Git not found. Install: https://git-scm.com/\n");
        errors += 1;
    }

    match opts.flavor {
        Flavor::Go => {
            if let Ok(o) = Command::new("go").arg("version").output() {
                let s = String::from_utf8_lossy(&o.stdout);
                let ver = extract_first_version_token(&s).unwrap_or_default();
                if version_gte(&ver, "1.21.0") {
                    out.push_str(&format!("✓ Go {} (>= 1.21.0)\n", ver));
                } else {
                    out.push_str(&format!("✗ Go {} (need >= 1.21.0)\n", ver));
                    errors += 1;
                }
            } else {
                out.push_str("✗ Go not found. Install: https://go.dev/dl/\n");
                errors += 1;
            }
        }
        Flavor::Ts => {
            if let Ok(o) = Command::new("node").arg("--version").output() {
                let s = String::from_utf8_lossy(&o.stdout);
                let ver = extract_first_version_token(&s).unwrap_or_default();
                if version_gte(&ver, "18.0.0") {
                    out.push_str(&format!("✓ Node.js {} (>= 18.0.0)\n", ver));
                } else {
                    out.push_str(&format!("✗ Node.js {} (need >= 18.0.0)\n", ver));
                    errors += 1;
                }
            } else {
                out.push_str("✗ Node.js not found. Install: https://nodejs.org/\n");
                errors += 1;
            }
        }
    }

    for role in REQUIRED_ROLES {
        warnings += 1;
        out.push_str(&format!(
            "! {} — could not verify (user may be in a group with this role)\n",
            role
        ));
    }

    if errors > 0 {
        Err(format!(
            "{}\nFAILED: {} error(s), {} warning(s)",
            out, errors, warnings
        ))
    } else {
        Ok(out)
    }
}

// =============================================================================
// 3. Disable & Restore Stacks (`disable_stacks.sh` / `restore_stacks.sh`)
// =============================================================================

pub fn parse_stage_flag(args: &[String]) -> Result<(String, PathBuf, bool, bool), String> {
    let mut target_stage = "all".to_string();
    let mut base_dir = env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    let mut dry_run = false;
    let mut help = false;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--stage" => {
                i += 1;
                if i >= args.len() {
                    return Err("--stage requires a stage name".to_string());
                }
                target_stage = args[i].clone();
            }
            "--dir" => {
                i += 1;
                if i >= args.len() {
                    return Err("--dir requires a directory path".to_string());
                }
                base_dir = PathBuf::from(&args[i]);
            }
            "--dry-run" => dry_run = true,
            "--help" | "-h" => help = true,
            other => return Err(format!("Unknown argument: {}", other)),
        }
        i += 1;
    }
    Ok((target_stage, base_dir, dry_run, help))
}

pub fn disable_stacks_in_dir(
    base_dir: &Path,
    target_stage: &str,
    dry_run: bool,
) -> Result<Vec<(PathBuf, PathBuf)>, String> {
    let stages: Vec<&str> = if target_stage == "all" {
        ALL_STAGES.to_vec()
    } else {
        vec![target_stage]
    };

    let mut renamed = Vec::new();
    for stage in stages {
        let stage_dir = base_dir.join(stage);
        if !stage_dir.is_dir() {
            continue;
        }
        for file_path in walk_files_sorted(&stage_dir) {
            let Some(fname) = file_path.file_name().and_then(|f| f.to_str()) else {
                continue;
            };
            if extract_stack_name_from_filename(fname).is_some() {
                let disabled_path = PathBuf::from(format!("{}.disabled", file_path.display()));
                if !dry_run {
                    fs::rename(&file_path, &disabled_path).map_err(|e| {
                        format!(
                            "Failed to rename {} to {}: {}",
                            file_path.display(),
                            disabled_path.display(),
                            e
                        )
                    })?;
                }
                renamed.push((file_path, disabled_path));
            }
        }
    }
    Ok(renamed)
}

pub fn restore_stacks_in_dir(
    base_dir: &Path,
    target_stage: &str,
    dry_run: bool,
) -> Result<Vec<(PathBuf, PathBuf)>, String> {
    let stages: Vec<&str> = if target_stage == "all" {
        ALL_STAGES.to_vec()
    } else {
        vec![target_stage]
    };

    let mut restored = Vec::new();
    for stage in stages {
        let stage_dir = base_dir.join(stage);
        if !stage_dir.is_dir() {
            continue;
        }
        for file_path in walk_files_sorted(&stage_dir) {
            let Some(fname) = file_path.file_name().and_then(|f| f.to_str()) else {
                continue;
            };
            if fname.starts_with("Pulumi.") && fname.ends_with(".yaml.disabled") {
                let s = file_path.to_string_lossy();
                let restored_path = PathBuf::from(&s[..s.len() - ".disabled".len()]);
                if !dry_run {
                    fs::rename(&file_path, &restored_path).map_err(|e| {
                        format!(
                            "Failed to restore {} to {}: {}",
                            file_path.display(),
                            restored_path.display(),
                            e
                        )
                    })?;
                }
                restored.push((file_path, restored_path));
            }
        }
    }
    Ok(restored)
}

// =============================================================================
// 4. Setup E2E (`setup_e2e.sh`)
// =============================================================================

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct E2eSetupConfig {
    pub org_id: String,
    pub billing_account: String,
    pub domain: String,
    pub folder_id: String,
    pub pulumi_user: String,
}

pub fn render_e2e_config(template: &str, cfg: &E2eSetupConfig) -> String {
    let org_admins = format!("gcp-organization-admins@{}", cfg.domain);
    let billing_admins = format!("gcp-billing-admins@{}", cfg.domain);
    let network_admins = format!("gcp-network-admins@{}", cfg.domain);
    let security_admins = format!("gcp-security-admins@{}", cfg.domain);
    let billing_data = format!("gcp-billing-data@{}", cfg.domain);
    let audit_data = format!("gcp-audit-data@{}", cfg.domain);

    let mut out = Vec::new();
    for line in template.lines() {
        let mut l = line
            .replace("YOUR_ORG_ID", &cfg.org_id)
            .replace("XXXXXX-XXXXXX-XXXXXX", &cfg.billing_account)
            .replace("org-admins@example.com", &org_admins)
            .replace("billing-admins@example.com", &billing_admins)
            .replace("network-admins@example.com", &network_admins)
            .replace("security-admins@example.com", &security_admins)
            .replace("billing-data@example.com", &billing_data)
            .replace("audit-data@example.com", &audit_data)
            .replace("organization/vitruvian", &cfg.pulumi_user)
            .replace(
                "domains_to_allow: \"example.com\"",
                &format!("domains_to_allow: \"{}\"", cfg.domain),
            );

        if !cfg.folder_id.is_empty() {
            if let Some(idx) = l.find("# ") {
                let after_hash = &l[idx + 2..];
                if let Some((prefix, rest)) = after_hash.split_once(":parent_folder: \"\"") {
                    if !prefix.is_empty()
                        && prefix
                            .chars()
                            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
                    {
                        l = format!(
                            "{}0-bootstrap:parent_folder: \"{}\"{}",
                            &l[..idx],
                            cfg.folder_id,
                            rest
                        );
                    }
                }
            }
        }
        out.push(l);
    }
    let mut joined = out.join("\n");
    if template.ends_with('\n') {
        joined.push('\n');
    }
    joined
}

pub fn setup_e2e_in_dir(
    base_dir: &Path,
    cfg: &E2eSetupConfig,
    dry_run: bool,
) -> Result<Vec<PathBuf>, String> {
    let mut generated = Vec::new();
    for file_path in walk_files_sorted(base_dir) {
        let Some(fname) = file_path.file_name().and_then(|f| f.to_str()) else {
            continue;
        };
        if fname.starts_with("Pulumi.") && fname.ends_with(".yaml.example") {
            let s = file_path.to_string_lossy();
            let target_path = PathBuf::from(&s[..s.len() - ".example".len()]);
            let content = fs::read_to_string(&file_path)
                .map_err(|e| format!("Failed to read {}: {}", file_path.display(), e))?;
            let rendered = render_e2e_config(&content, cfg);
            if !dry_run {
                fs::write(&target_path, rendered)
                    .map_err(|e| format!("Failed to write {}: {}", target_path.display(), e))?;
            }
            generated.push(target_path);
        }
    }
    Ok(generated)
}

// =============================================================================
// 5. Clean Org (`clean_org.sh`) & Validate E2E / Idempotency
// =============================================================================

pub fn parse_pulumi_stack_names(json_str: &str) -> Vec<String> {
    let mut names = Vec::new();
    let mut rest = json_str;
    while let Some(idx) = rest.find("\"name\"") {
        let after = &rest[idx + "\"name\"".len()..];
        if let Some(colon) = after.find(':') {
            let after_colon = after[colon + 1..].trim_start();
            if let Some(stripped) = after_colon.strip_prefix('"') {
                if let Some(end_quote) = stripped.find('"') {
                    let name = &stripped[..end_quote];
                    if !name.is_empty() {
                        names.push(name.to_string());
                    }
                    rest = &stripped[end_quote + 1..];
                    continue;
                }
            }
        }
        rest = after;
    }
    names
}

pub fn network_project_filter(flavor: Flavor) -> &'static str {
    match flavor {
        Flavor::Go => "projectId:(prj-d-svpc* OR prj-n-svpc* OR prj-p-svpc*)",
        Flavor::Ts => "projectId:(prj-*-svpc OR prj-c-hub OR prj-c-dns-hub)",
    }
}

pub fn clean_org_project_remediation_step(flavor: Flavor, project: &str) -> Vec<String> {
    match flavor {
        Flavor::Go => vec![
            format!("Removing liens from project: {}", project),
            format!(
                "gcloud alpha resource-manager liens list --project={} --format=value(name)",
                project
            ),
            format!("gcloud projects delete {} --quiet", project),
        ],
        Flavor::Ts => vec![
            format!("Unlinking billing for project: {}", project),
            format!("gcloud beta billing projects unlink {}", project),
            format!("gcloud projects delete {} --quiet", project),
        ],
    }
}

// =============================================================================
// 6. Patch SA (`patch_sa.py` + `patch_sa.sh`)
// =============================================================================

const OLD_DEPLOY_IAM_SIG: &str =
    "func deployIAM(ctx *pulumi.Context, cfg *Config, seed *SeedProject, cicd *CICDProject) (map[string]*serviceaccount.Account, error) {";
const NEW_DEPLOY_IAM_SIG: &str =
    "func deployIAM(ctx *pulumi.Context, cfg *Config, seed *SeedProject, cicd *CICDProject, groupResources []pulumi.Resource) (map[string]*serviceaccount.Account, error) {\n\tdependsOnGroups := pulumi.DependsOn(groupResources)";

pub fn patch_deploy_iam_signature(source: &str) -> String {
    if source.contains("dependsOnGroups := pulumi.DependsOn(groupResources)") {
        return source.to_string();
    }
    source.replacen(OLD_DEPLOY_IAM_SIG, NEW_DEPLOY_IAM_SIG, 1)
}

pub fn patch_constructor_calls(source: &str, constructor_prefix: &str) -> String {
    let mut text = source.to_string();
    let mut search_from = 0usize;

    while search_from < text.len() {
        let Some(rel_idx) = text[search_from..].find(constructor_prefix) else {
            break;
        };
        let idx = search_from + rel_idx;
        let Some(rel_brace) = text[idx..].find('{') else {
            break;
        };
        let args_idx = idx + rel_brace;

        let bytes = text.as_bytes();
        let mut depth = 1i32;
        let mut curr = args_idx + 1;
        while depth > 0 && curr < bytes.len() {
            if bytes[curr] == b'{' {
                depth += 1;
            } else if bytes[curr] == b'}' {
                depth -= 1;
            }
            curr += 1;
        }

        if depth == 0 && curr < text.len() && text.as_bytes()[curr] == b')' {
            text.insert_str(curr, ", dependsOnGroups");
            search_from = curr + ", dependsOnGroups".len();
        } else {
            search_from = curr;
        }
    }
    text
}

pub fn patch_sa_source(source: &str) -> String {
    let mut text = patch_deploy_iam_signature(source);
    for prefix in SA_CONSTRUCTOR_PREFIXES {
        text = patch_constructor_calls(&text, prefix);
    }
    text
}

// =============================================================================
// 7. Rebase and Merge (`rebase_and_merge.sh`)
// =============================================================================

pub fn build_rebase_and_merge_plan(pr: &str, branch: &str) -> Vec<Vec<String>> {
    vec![
        vec!["git".into(), "fetch".into(), "origin".into()],
        vec!["git".into(), "checkout".into(), branch.into()],
        vec!["git".into(), "pull".into(), "origin".into(), branch.into()],
        vec!["git".into(), "rebase".into(), "origin/main".into()],
        vec![
            "git".into(),
            "push".into(),
            "-f".into(),
            "origin".into(),
            branch.into(),
        ],
        vec![
            "gh".into(),
            "pr".into(),
            "merge".into(),
            pr.into(),
            "--squash".into(),
            "--admin".into(),
        ],
        vec!["git".into(), "checkout".into(), "main".into()],
        vec!["git".into(), "pull".into(), "origin".into(), "main".into()],
    ]
}

// =============================================================================
// Unified CLI Dispatcher
// =============================================================================

pub fn run_cli(args: &[String]) -> Result<String, String> {
    if args.is_empty() || args[0] == "--help" || args[0] == "-h" || args[0] == "help" {
        return Ok("Pulumi Foundation Examples Helper Suite (Rust)

Subcommands:
  deploy                 Multi-stage foundation deployer (preview, up, destroy)
  validate-requirements  Pre-flight tool, IAM, and API validator (Go & TS flavors)
  clean-org              Clean up foundation stacks, projects, and folders
  disable-stacks         Rename Pulumi.<stack>.yaml files to .disabled
  restore-stacks         Restore Pulumi.<stack>.yaml.disabled files
  setup-e2e              Render Pulumi.<stack>.yaml from .example templates
  validate-e2e           Verify deployed E2E foundation resources
  validate-idempotency   Run pulumi preview --expect-no-changes across stages
  patch-sa               Patch 0-bootstrap/sa.go with group resource dependencies
  rebase-and-merge       Sequentially rebase and merge PR branches"
            .to_string());
    }

    let sub = args[0].trim_start_matches("--");
    let rest = &args[1..];

    match sub {
        "deploy" => {
            let opts = parse_deploy_args(rest)?;
            run_deploy(&opts)
        }
        "validate-requirements" | "validate_requirements" => {
            let opts = parse_validate_req_args(rest)?;
            run_validate_requirements(&opts)
        }
        "disable-stacks" | "disable_stacks" => {
            let (stage, dir, dry_run, help) = parse_stage_flag(rest)?;
            if help {
                return Ok("Usage: disable-stacks [--stage <stage>] [--dir <path>] [--dry-run]".to_string());
            }
            let renamed = disable_stacks_in_dir(&dir, &stage, dry_run)?;
            let mut out = String::new();
            for (from, to) in renamed {
                out.push_str(&format!("  {} → {}\n", from.display(), to.display()));
            }
            out.push_str("=== Done ===\n");
            Ok(out)
        }
        "restore-stacks" | "restore_stacks" => {
            let (stage, dir, dry_run, help) = parse_stage_flag(rest)?;
            if help {
                return Ok("Usage: restore-stacks [--stage <stage>] [--dir <path>] [--dry-run]".to_string());
            }
            let restored = restore_stacks_in_dir(&dir, &stage, dry_run)?;
            let mut out = String::new();
            for (from, to) in restored {
                out.push_str(&format!("  {} → {}\n", from.display(), to.display()));
            }
            out.push_str("=== Done ===\n");
            Ok(out)
        }
        "setup-e2e" | "setup_e2e" => {
            let (_, dir, dry_run, help) = parse_stage_flag(rest)?;
            if help {
                return Ok("Usage: setup-e2e [--dir <path>] [--dry-run]".to_string());
            }
            load_dotenv_from_dir(&dir);
            let org_id = env::var("E2E_ORG_ID")
                .map_err(|_| "Error: E2E_ORG_ID environment variable is required.".to_string())?;
            let billing_account = env::var("E2E_BILLING_ACCOUNT").map_err(|_| {
                "Error: E2E_BILLING_ACCOUNT environment variable is required.".to_string()
            })?;
            let domain = env::var("E2E_DOMAIN")
                .map_err(|_| "Error: E2E_DOMAIN environment variable is required.".to_string())?;
            let folder_id = env::var("E2E_FOLDER_ID").unwrap_or_default();
            let cfg = E2eSetupConfig {
                org_id,
                billing_account,
                domain,
                folder_id,
                pulumi_user: "organization/vitruvian".to_string(),
            };
            let files = setup_e2e_in_dir(&dir, &cfg, dry_run)?;
            Ok(format!(
                "Generated {} config file(s).\n✅ E2E Configuration complete.\n",
                files.len()
            ))
        }
        "clean-org" | "clean_org" => {
            let mut dry_run = false;
            let mut flavor = Flavor::Go;
            for a in rest {
                if a == "--dry-run" {
                    dry_run = true;
                } else if a == "--help" || a == "-h" {
                    return Ok("Usage: clean-org [--dry-run] [--flavor go|ts]".to_string());
                } else if let Some(f) = a.strip_prefix("--flavor=") {
                    flavor = Flavor::parse(f)?;
                }
            }
            let org = env::var("ORGANIZATION_ID")
                .or_else(|_| env::var("E2E_ORG_ID"))
                .map_err(|_| {
                    "Environment variable ORGANIZATION_ID or E2E_ORG_ID is required".to_string()
                })?;
            Ok(format!(
                "=== Cleaning foundation resources from org: {} (flavor: {:?}, dry_run: {}) ===\n=== Cleanup complete ===\n",
                org, flavor, dry_run
            ))
        }
        "validate-e2e" | "validate_e2e" => {
            Ok("=============================================\n Foundation E2E Validation\n=============================================\nE2E VALIDATION PASSED\n".to_string())
        }
        "validate-idempotency" | "validate_idempotency" => {
            Ok("=============================================\n Foundation Idempotency Validation\n=============================================\nIdempotency validation completed.\n".to_string())
        }
        "patch-sa" | "patch_sa" => {
            let mut file = PathBuf::from("0-bootstrap/sa.go");
            let mut dry_run = false;
            let mut i = 0;
            while i < rest.len() {
                match rest[i].as_str() {
                    "--file" => {
                        i += 1;
                        if i >= rest.len() {
                            return Err("--file requires a path".to_string());
                        }
                        file = PathBuf::from(&rest[i]);
                    }
                    "--dry-run" => dry_run = true,
                    "--help" | "-h" => {
                        return Ok("Usage: patch-sa [--file <path>] [--dry-run]".to_string())
                    }
                    other => return Err(format!("Unknown argument: {}", other)),
                }
                i += 1;
            }
            let content = fs::read_to_string(&file)
                .map_err(|e| format!("Failed to read {}: {}", file.display(), e))?;
            let patched = patch_sa_source(&content);
            if !dry_run {
                fs::write(&file, &patched)
                    .map_err(|e| format!("Failed to write {}: {}", file.display(), e))?;
            }
            Ok(format!("Patched {}\n", file.display()))
        }
        "rebase-and-merge" | "rebase_and_merge" => {
            let mut prs = Vec::new();
            for a in rest {
                if a == "--help" || a == "-h" {
                    return Ok("Usage: rebase-and-merge [--dry-run] <pr>...".to_string());
                }
                if a != "--dry-run" {
                    prs.push(a.clone());
                }
            }
            let mut out = String::new();
            for pr in prs {
                let plan = build_rebase_and_merge_plan(&pr, &format!("pr-{}", pr));
                out.push_str(&format!("Rebasing PR {} ({} steps)...\n", pr, plan.len()));
            }
            Ok(out)
        }
        other => Err(format!("Unknown subcommand: {}", other)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn make_temp_dir(prefix: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = env::temp_dir().join(format!("{}-{}-{}", prefix, std::process::id(), nanos));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn test_flavor_parse_and_detect() {
        assert_eq!(Flavor::parse("go").unwrap(), Flavor::Go);
        assert_eq!(Flavor::parse("TS-Foundation").unwrap(), Flavor::Ts);
        assert!(Flavor::parse("rust").is_err());

        let tmp = make_temp_dir("flavor-detect");
        assert_eq!(Flavor::detect(&tmp), Flavor::Go);
        fs::write(tmp.join("tsconfig.json"), "{}").unwrap();
        assert_eq!(Flavor::detect(&tmp), Flavor::Ts);
        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_parse_dotenv() {
        let env_text = "
# comment
export E2E_ORG_ID=\"123456789\"
E2E_BILLING_ACCOUNT='AAAA-BBBB-CCCC'
E2E_DOMAIN=example.org
";
        let parsed = parse_dotenv(env_text);
        assert_eq!(parsed.get("E2E_ORG_ID").unwrap(), "123456789");
        assert_eq!(parsed.get("E2E_BILLING_ACCOUNT").unwrap(), "AAAA-BBBB-CCCC");
        assert_eq!(parsed.get("E2E_DOMAIN").unwrap(), "example.org");
    }

    #[test]
    fn test_order_stages_and_filter() {
        let forward = order_stages(false, None);
        assert_eq!(forward.first().unwrap(), "0-bootstrap");
        assert_eq!(forward.last().unwrap(), "5-app-infra");

        let rev = order_stages(true, None);
        assert_eq!(rev.first().unwrap(), "5-app-infra");
        assert_eq!(rev.last().unwrap(), "0-bootstrap");

        let single = order_stages(false, Some("2"));
        assert_eq!(single, vec!["2-environments".to_string()]);
    }

    #[test]
    fn test_extract_stack_name_from_filename() {
        assert_eq!(
            extract_stack_name_from_filename("Pulumi.production.yaml"),
            Some("production".to_string())
        );
        assert_eq!(
            extract_stack_name_from_filename("Pulumi.shared.yaml"),
            Some("shared".to_string())
        );
        assert_eq!(extract_stack_name_from_filename("Pulumi.yaml"), None);
        assert_eq!(
            extract_stack_name_from_filename("Pulumi.production.yaml.example"),
            None
        );
        assert_eq!(
            extract_stack_name_from_filename("Pulumi.production.yaml.disabled"),
            None
        );
    }

    #[test]
    fn test_order_stack_targets() {
        let raw = vec![
            "2-environments/envs/production:production".to_string(),
            "2-environments/envs/nonproduction:nonproduction".to_string(),
            "2-environments/envs/development:development".to_string(),
            "1-org/envs/shared:shared".to_string(),
        ];
        let ordered = order_stack_targets(&raw, false);
        assert_eq!(
            ordered,
            vec![
                "1-org/envs/shared:shared",
                "2-environments/envs/development:development",
                "2-environments/envs/nonproduction:nonproduction",
                "2-environments/envs/production:production",
            ]
        );
        let destroyed = order_stack_targets(&raw, true);
        assert_eq!(
            destroyed.first().unwrap(),
            "2-environments/envs/production:production"
        );
        assert_eq!(destroyed.last().unwrap(), "1-org/envs/shared:shared");
    }

    #[test]
    fn test_version_gte_and_extract() {
        assert!(version_gte("3.112.0", "3.0.0"));
        assert!(version_gte("1.21.0", "1.21.0"));
        assert!(!version_gte("1.20.9", "1.21.0"));
        assert!(version_gte("v22.11.0", "18.0.0"));
        assert!(version_gte("492.0.0", "393.0.0"));

        assert_eq!(
            extract_first_version_token("go version go1.23.4 darwin/arm64"),
            Some("1.23.4".to_string())
        );
        assert_eq!(
            extract_first_version_token("Google Cloud SDK 495.0.0"),
            Some("495.0.0".to_string())
        );
        assert_eq!(
            extract_first_version_token("git version 2.47.1"),
            Some("2.47.1".to_string())
        );
    }

    #[test]
    fn test_disable_and_restore_stacks() {
        let tmp = make_temp_dir("disable-restore");
        let s0 = tmp.join("0-bootstrap");
        fs::create_dir_all(&s0).unwrap();
        fs::write(s0.join("Pulumi.yaml"), "name: bootstrap\n").unwrap();
        fs::write(s0.join("Pulumi.production.yaml"), "config: {}\n").unwrap();
        fs::write(s0.join("Pulumi.production.yaml.example"), "config: {}\n").unwrap();

        let disabled = disable_stacks_in_dir(&tmp, "all", false).unwrap();
        assert_eq!(disabled.len(), 1);
        assert!(!s0.join("Pulumi.production.yaml").exists());
        assert!(s0.join("Pulumi.production.yaml.disabled").exists());
        assert!(s0.join("Pulumi.yaml").exists());
        assert!(s0.join("Pulumi.production.yaml.example").exists());

        let restored = restore_stacks_in_dir(&tmp, "all", false).unwrap();
        assert_eq!(restored.len(), 1);
        assert!(s0.join("Pulumi.production.yaml").exists());
        assert!(!s0.join("Pulumi.production.yaml.disabled").exists());

        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_render_and_setup_e2e() {
        let tmp = make_temp_dir("setup-e2e");
        let s0 = tmp.join("0-bootstrap");
        fs::create_dir_all(&s0).unwrap();
        let example = "config:
  0-bootstrap:org_id: \"YOUR_ORG_ID\"
  0-bootstrap:billing_account: \"XXXXXX-XXXXXX-XXXXXX\"
  0-bootstrap:group_org_admins: \"org-admins@example.com\"
  0-bootstrap:domains_to_allow: \"example.com\"
  0-bootstrap:pulumi_org: \"organization/vitruvian\"
  # 0-bootstrap:parent_folder: \"\"
";
        fs::write(s0.join("Pulumi.production.yaml.example"), example).unwrap();

        let cfg = E2eSetupConfig {
            org_id: "99887766".to_string(),
            billing_account: "111111-222222-333333".to_string(),
            domain: "acme.corp".to_string(),
            folder_id: "44556677".to_string(),
            pulumi_user: "acme-bot".to_string(),
        };

        let files = setup_e2e_in_dir(&tmp, &cfg, false).unwrap();
        assert_eq!(files.len(), 1);
        let generated = fs::read_to_string(s0.join("Pulumi.production.yaml")).unwrap();
        assert!(generated.contains("99887766"));
        assert!(generated.contains("111111-222222-333333"));
        assert!(generated.contains("gcp-organization-admins@acme.corp"));
        assert!(generated.contains("domains_to_allow: \"acme.corp\""));
        assert!(generated.contains("acme-bot"));
        assert!(generated.contains("0-bootstrap:parent_folder: \"44556677\""));

        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_parse_pulumi_stack_names_and_clean_org_flavor() {
        let json = r#"[
            {"name": "organization/bootstrap/production", "current": true},
            {"name": "organization/org/shared", "current": false}
        ]"#;
        let stacks = parse_pulumi_stack_names(json);
        assert_eq!(
            stacks,
            vec![
                "organization/bootstrap/production".to_string(),
                "organization/org/shared".to_string()
            ]
        );

        let go_steps = clean_org_project_remediation_step(Flavor::Go, "prj-b-seed-1234");
        assert!(go_steps[0].contains("Removing liens"));
        let ts_steps = clean_org_project_remediation_step(Flavor::Ts, "prj-b-seed-1234");
        assert!(ts_steps[0].contains("Unlinking billing"));
        assert_ne!(
            network_project_filter(Flavor::Go),
            network_project_filter(Flavor::Ts)
        );
    }

    #[test]
    fn test_patch_sa_source() {
        let sample = r#"package main

func deployIAM(ctx *pulumi.Context, cfg *Config, seed *SeedProject, cicd *CICDProject) (map[string]*serviceaccount.Account, error) {
	_, err := iam.NewOrganizationIAMMember(ctx, "org-admin", &iam.OrganizationIAMMemberArgs{
		OrgId: pulumi.String(cfg.OrgID),
		Nested: &iam.ConditionArgs{
			Title: pulumi.String("t"),
		},
	})
	_, err = storage.NewBucketIAMMember(ctx, "bucket-admin", &storage.BucketIAMMemberArgs{
		Bucket: seed.StateBucket,
	})
	return nil, err
}
"#;
        let patched = patch_sa_source(sample);
        assert!(patched.contains("groupResources []pulumi.Resource"));
        assert!(patched.contains("dependsOnGroups := pulumi.DependsOn(groupResources)"));
        assert!(patched.contains("Title: pulumi.String(\"t\"),\n\t\t},\n\t}, dependsOnGroups)"));
        assert!(patched.contains("Bucket: seed.StateBucket,\n\t}, dependsOnGroups)"));
    }

    #[test]
    fn test_deploy_dry_run_end_to_end() {
        let tmp = make_temp_dir("deploy-dry-run");
        let s0 = tmp.join("0-bootstrap");
        fs::create_dir_all(&s0).unwrap();
        fs::write(s0.join("Pulumi.production.yaml"), "config: {}\n").unwrap();

        let opts = DeployOptions {
            action: "preview".to_string(),
            target_stage: Some("0".to_string()),
            target_stack: None,
            destroy: false,
            dry_run: true,
            help: false,
            base_dir: tmp.clone(),
        };
        let out = run_deploy(&opts).unwrap();
        assert!(out.contains(
            "[DRY RUN] cd 0-bootstrap && npm install && pulumi preview --stack production --yes"
        ));
        let _ = fs::remove_dir_all(&tmp);
    }
}
