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

use std::collections::BTreeMap;
use std::process::Command;

use tabula_api_tools_rs_lib::{
    contract_dirs_on_disk, parse_migrate_deploy_args, prepare_migrate_env,
    prisma_config_path_for_schema, verify_expand_phase_status, MigrationPhase,
};

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let cfg = match parse_migrate_deploy_args(&args) {
        Ok(c) => c,
        Err((code, msg)) => {
            eprintln!("{msg}");
            std::process::exit(code);
        }
    };

    let cwd = std::env::current_dir().unwrap_or_else(|_| std::path::PathBuf::from("."));
    let ambient: BTreeMap<String, String> = std::env::vars().collect();
    let env = prepare_migrate_env(&ambient, &cwd);
    let prisma_config = prisma_config_path_for_schema(&cfg.schema);

    if cfg.phase == MigrationPhase::Expand && !contract_dirs_on_disk(&cfg.schema).is_empty() {
        let out = Command::new("npx")
            .args([
                "prisma",
                "migrate",
                "status",
                &format!("--schema={}", cfg.schema),
                &format!("--config={}", prisma_config.display()),
            ])
            .envs(&env)
            .output();
        let combined = match out {
            Ok(o) => format!(
                "{}{}",
                String::from_utf8_lossy(&o.stdout),
                String::from_utf8_lossy(&o.stderr)
            ),
            Err(e) => e.to_string(),
        };
        if let Err((code, msg)) = verify_expand_phase_status(&combined) {
            eprintln!("{msg}");
            std::process::exit(code);
        }
    }

    let status = Command::new("npx")
        .args([
            "prisma",
            "migrate",
            "deploy",
            &format!("--schema={}", cfg.schema),
            &format!("--config={}", prisma_config.display()),
        ])
        .envs(&env)
        .status();

    match status {
        Ok(s) => std::process::exit(s.code().unwrap_or(1)),
        Err(e) => {
            eprintln!("Failed to run prisma migrate deploy: {e}");
            std::process::exit(1);
        }
    }
}
