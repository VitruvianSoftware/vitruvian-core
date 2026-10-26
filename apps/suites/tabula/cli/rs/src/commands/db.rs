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
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use crate::utils::config::get_config_from;

/// Build environment map for Prisma/DB commands, injecting `DATABASE_URL` from
/// `.tabula/config.json` when `!is_local`.
pub fn get_db_env(
    base_dir: &Path,
    is_local: bool,
    ambient_env: &BTreeMap<String, String>,
) -> BTreeMap<String, String> {
    let mut env = ambient_env.clone();
    if !is_local {
        if let Ok(config) = get_config_from(base_dir) {
            if let Some(db_url) = config.database_url {
                if !db_url.is_empty() {
                    env.insert("DATABASE_URL".to_string(), db_url);
                }
            }
        }
    }
    env
}

pub fn api_dir(base_dir: &Path) -> PathBuf {
    base_dir.join("api")
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DbActionPlan {
    Init {
        local: bool,
        cwd: PathBuf,
        commands: Vec<Vec<String>>,
    },
    Migrate {
        local: bool,
        name: String,
        cwd: PathBuf,
        command: Vec<String>,
    },
    Reset {
        local: bool,
        force: bool,
        cwd: PathBuf,
        command: Option<Vec<String>>,
    },
    Studio {
        local: bool,
        cwd: PathBuf,
        command: Vec<String>,
    },
    List {
        local: bool,
        model: String,
        cwd: PathBuf,
        command: Vec<String>,
    },
    Status {
        local: bool,
        cwd: PathBuf,
        command: Vec<String>,
    },
}

pub fn plan_db_command(base_dir: &Path, args: &[String]) -> Result<DbActionPlan, String> {
    if args.is_empty() {
        return Err("Missing db subcommand".to_string());
    }
    let cwd = api_dir(base_dir);
    let sub = args[0].as_str();
    let rest = &args[1..];
    let local = rest.iter().any(|a| a == "-l" || a == "--local");

    match sub {
        "init" => Ok(DbActionPlan::Init {
            local,
            cwd,
            commands: vec![
                vec![
                    "npx".to_string(),
                    "prisma".to_string(),
                    "generate".to_string(),
                ],
                vec![
                    "npx".to_string(),
                    "prisma".to_string(),
                    "migrate".to_string(),
                    "deploy".to_string(),
                ],
            ],
        }),
        "migrate" => {
            let mut name = "migration".to_string();
            let mut i = 0;
            while i < rest.len() {
                if rest[i] == "--name" {
                    i += 1;
                    name = rest.get(i).ok_or("Missing value for --name")?.clone();
                } else if let Some(v) = rest[i].strip_prefix("--name=") {
                    name = v.to_string();
                }
                i += 1;
            }
            Ok(DbActionPlan::Migrate {
                local,
                command: vec![
                    "npx".to_string(),
                    "prisma".to_string(),
                    "migrate".to_string(),
                    "dev".to_string(),
                    "--name".to_string(),
                    name.clone(),
                ],
                name,
                cwd,
            })
        }
        "reset" => {
            let force = rest.iter().any(|a| a == "-f" || a == "--force");
            let command = if force {
                Some(vec![
                    "npx".to_string(),
                    "prisma".to_string(),
                    "migrate".to_string(),
                    "reset".to_string(),
                    "--force".to_string(),
                ])
            } else {
                None
            };
            Ok(DbActionPlan::Reset {
                local,
                force,
                cwd,
                command,
            })
        }
        "studio" => Ok(DbActionPlan::Studio {
            local,
            cwd,
            command: vec![
                "npx".to_string(),
                "prisma".to_string(),
                "studio".to_string(),
            ],
        }),
        "list" => {
            let model = rest
                .iter()
                .find(|a| !a.starts_with('-'))
                .ok_or("Model name is required for `tabcli db list <model>`")?
                .clone();
            Ok(DbActionPlan::List {
                local,
                command: vec![
                    "npx".to_string(),
                    "tsx".to_string(),
                    "scripts/db-list.ts".to_string(),
                    model.clone(),
                ],
                model,
                cwd,
            })
        }
        "status" => Ok(DbActionPlan::Status {
            local,
            cwd,
            command: vec![
                "npx".to_string(),
                "prisma".to_string(),
                "migrate".to_string(),
                "status".to_string(),
            ],
        }),
        other => Err(format!("Unknown db subcommand: {other}")),
    }
}

pub fn run_db_command(args: &[String]) -> Result<String, String> {
    if args.is_empty() || args[0] == "--help" || args[0] == "-h" {
        return Ok(
            "Usage: tabcli db <command>\n\nDatabase management commands\n\nCommands:\n  init             Initialize database with schema\n  migrate          Run database migrations\n  reset            Reset database (WARNING: deletes all data)\n  studio           Open Prisma Studio (database GUI)\n  list <model>     List database records for a model\n  status           Check database connection and migration status"
                .to_string(),
        );
    }

    let cwd = std::env::current_dir().map_err(|e| e.to_string())?;
    let ambient: BTreeMap<String, String> = std::env::vars().collect();
    let plan = plan_db_command(&cwd, args)?;

    match plan {
        DbActionPlan::Reset { force: false, .. } => Ok(
            "⚠ This will delete all data in the database!\nUse --force to skip this confirmation"
                .to_string(),
        ),
        DbActionPlan::Init {
            local,
            cwd: api_path,
            commands,
        } => {
            let env = get_db_env(&cwd, local, &ambient);
            for cmd in commands {
                let status = Command::new(&cmd[0])
                    .args(&cmd[1..])
                    .current_dir(&api_path)
                    .envs(&env)
                    .status()
                    .map_err(|e| format!("Database initialization failed: {e}"))?;
                if !status.success() {
                    return Err("Database initialization failed".to_string());
                }
            }
            Ok("Database initialized successfully\n✓ Database is ready".to_string())
        }
        DbActionPlan::Migrate {
            local,
            cwd: api_path,
            command,
            ..
        } => {
            let env = get_db_env(&cwd, local, &ambient);
            let status = Command::new(&command[0])
                .args(&command[1..])
                .current_dir(&api_path)
                .envs(&env)
                .status()
                .map_err(|e| format!("Migration failed: {e}"))?;
            if !status.success() {
                return Err("Migration failed".to_string());
            }
            Ok("Migrations completed".to_string())
        }
        DbActionPlan::Reset {
            local,
            force: true,
            cwd: api_path,
            command: Some(command),
        } => {
            let env = get_db_env(&cwd, local, &ambient);
            let status = Command::new(&command[0])
                .args(&command[1..])
                .current_dir(&api_path)
                .envs(&env)
                .status()
                .map_err(|e| format!("Database reset failed: {e}"))?;
            if !status.success() {
                return Err("Database reset failed".to_string());
            }
            Ok("Database reset successfully".to_string())
        }
        DbActionPlan::Reset {
            force: true,
            command: None,
            ..
        } => unreachable!(),
        DbActionPlan::Studio {
            local,
            cwd: api_path,
            command,
        } => {
            let env = get_db_env(&cwd, local, &ambient);
            let status = Command::new(&command[0])
                .args(&command[1..])
                .current_dir(&api_path)
                .envs(&env)
                .status()
                .map_err(|e| format!("Failed to open Prisma Studio: {e}"))?;
            if !status.success() {
                return Err("Failed to open Prisma Studio".to_string());
            }
            Ok("Opening Prisma Studio...".to_string())
        }
        DbActionPlan::List {
            local,
            model,
            cwd: api_path,
            command,
        } => {
            let env = get_db_env(&cwd, local, &ambient);
            let output = Command::new(&command[0])
                .args(&command[1..])
                .current_dir(&api_path)
                .envs(&env)
                .stdin(Stdio::null())
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .output()
                .map_err(|_| {
                    "Failed to list records\nMake sure the model name exists and database is connected."
                        .to_string()
                })?;
            if !output.status.success() {
                return Err(
                    "Failed to list records\nMake sure the model name exists and database is connected."
                        .to_string(),
                );
            }
            let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if stdout == "[]" || stdout.is_empty() {
                Ok(format!("No records found for model \"{model}\"."))
            } else {
                Ok(format!("\n{model} Records:\n{stdout}"))
            }
        }
        DbActionPlan::Status {
            local,
            cwd: api_path,
            command,
        } => {
            let env = get_db_env(&cwd, local, &ambient);
            let output = Command::new(&command[0])
                .args(&command[1..])
                .current_dir(&api_path)
                .envs(&env)
                .output()
                .map_err(|e| format!("Failed to check database status: {e}"))?;
            if !output.status.success() {
                return Err("Failed to check database status".to_string());
            }
            let stdout = String::from_utf8_lossy(&output.stdout);
            Ok(format!("Database status checked\n\n{stdout}"))
        }
    }
}
