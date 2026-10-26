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
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

// ============================================================================
// 1. Prisma Client Generation & Post-Processing (`generate-client.cjs`)
// ============================================================================

pub const GENERATED_DIR: &str = "src/generated/prisma";
pub const DEFAULT_PRISMA_SCHEMA: &str = "prisma/schema.prisma";

/// Recursively collect `.ts` source files (excluding `.d.ts` declaration files)
/// inside `dir` in deterministic sorted order.
pub fn collect_ts_files(dir: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let entries = match fs::read_dir(dir) {
        Ok(rd) => rd,
        Err(_) => return out,
    };
    let mut paths: Vec<PathBuf> = entries.filter_map(|e| e.ok().map(|de| de.path())).collect();
    paths.sort();

    for p in paths {
        if p.is_dir() {
            out.extend(collect_ts_files(&p));
        } else if let Some(name) = p.file_name().and_then(|n| n.to_str()) {
            if name.ends_with(".ts") && !name.ends_with(".d.ts") {
                out.push(p);
            }
        }
    }
    out
}

/// Remove the `.ts` source files after TypeScript compilation so downstream
/// `ts_project` targets consume `.d.ts` for types and `.js` at runtime.
pub fn strip_ts_sources(files: &[PathBuf]) -> Result<usize, String> {
    let mut removed = 0usize;
    for f in files {
        fs::remove_file(f).map_err(|e| format!("Failed to unlink {}: {e}", f.display()))?;
        removed += 1;
    }
    Ok(removed)
}

pub fn run_generate_client(schema_path: &str, generated_dir: &Path) -> Result<usize, String> {
    let status = Command::new("npx")
        .args(["prisma", "generate", &format!("--schema={schema_path}")])
        .status()
        .map_err(|e| format!("Failed to execute prisma generate: {e}"))?;
    if !status.success() {
        return Err(format!(
            "prisma generate failed with exit code {}",
            status.code().unwrap_or(1)
        ));
    }

    let files = collect_ts_files(generated_dir);
    if !files.is_empty() {
        let mut tsc_cmd = Command::new("npx");
        tsc_cmd.args([
            "tsc",
            "--module",
            "NodeNext",
            "--target",
            "ES2022",
            "--moduleResolution",
            "NodeNext",
            "--declaration",
            "--esModuleInterop",
            "--resolveJsonModule",
            "--skipLibCheck",
        ]);
        for f in &files {
            tsc_cmd.arg(f);
        }
        let tsc_status = tsc_cmd
            .status()
            .map_err(|e| format!("Failed to execute tsc on generated Prisma client: {e}"))?;
        if !tsc_status.success() {
            return Err(format!(
                "tsc failed on generated Prisma client with exit code {}",
                tsc_status.code().unwrap_or(1)
            ));
        }
    }

    strip_ts_sources(&files)
}

// ============================================================================
// 2. Migration Deployment & Expand/Contract Phase Guard (`migrate-deploy.cjs`)
// ============================================================================

pub const DEFAULT_DEPLOY_SCHEMA: &str = "apps/suites/tabula/api/prisma/schema.prisma";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MigrationPhase {
    Expand,
    Contract,
}

impl MigrationPhase {
    pub fn parse(raw: &str) -> Result<Self, String> {
        match raw {
            "expand" => Ok(Self::Expand),
            "contract" => Ok(Self::Contract),
            other => Err(format!(
                "migrate-deploy: --phase must be \"expand\" or \"contract\" (got \"{other}\")"
            )),
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Expand => "expand",
            Self::Contract => "contract",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MigrateDeployConfig {
    pub schema: String,
    pub phase: MigrationPhase,
}

pub fn parse_migrate_deploy_args(args: &[String]) -> Result<MigrateDeployConfig, (i32, String)> {
    let mut schema = DEFAULT_DEPLOY_SCHEMA.to_string();
    let mut phase_str = "expand".to_string();

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--schema" => {
                if let Some(val) = args.get(i + 1) {
                    schema = val.clone();
                    i += 1;
                }
            }
            "--phase" => {
                if let Some(val) = args.get(i + 1) {
                    phase_str = val.clone();
                    i += 1;
                }
            }
            other => {
                if let Some(v) = other.strip_prefix("--schema=") {
                    schema = v.to_string();
                } else if let Some(v) = other.strip_prefix("--phase=") {
                    phase_str = v.to_string();
                }
            }
        }
        i += 1;
    }

    let phase = MigrationPhase::parse(&phase_str).map_err(|msg| (2, msg))?;
    Ok(MigrateDeployConfig { schema, phase })
}

pub fn prisma_config_path_for_schema(schema: &str) -> PathBuf {
    let schema_dir = Path::new(schema).parent().unwrap_or_else(|| Path::new("."));
    schema_dir.join("..").join("prisma.config.ts")
}

pub fn prepare_migrate_env(
    ambient: &BTreeMap<String, String>,
    cwd: &Path,
) -> BTreeMap<String, String> {
    let mut env = ambient.clone();
    env.insert("PRISMA_HIDE_UPDATE_MESSAGE".to_string(), "1".to_string());

    for key in ["PRISMA_SCHEMA_ENGINE_BINARY", "PRISMA_QUERY_ENGINE_LIBRARY"] {
        if let Some(val) = env.get(key).cloned() {
            if !val.is_empty() {
                let p = Path::new(&val);
                let resolved = if p.is_absolute() {
                    p.to_path_buf()
                } else {
                    cwd.join(p)
                };
                env.insert(key.to_string(), resolved.display().to_string());
            }
        }
    }
    env
}

/// Pure parser (unit-testable without Prisma or a database): extracts unique
/// `*_contract` migration names that Prisma lists under `"…have not yet been applied"`.
pub fn contracts_in_status(status_output: &str) -> Vec<String> {
    let lower = status_output.to_ascii_lowercase();
    let marker = match lower.find("not yet been applied") {
        Some(idx) => idx,
        None => return Vec::new(),
    };
    let tail = &status_output[marker..];
    let candidates = extract_migration_identifiers(tail);
    let mut unique = Vec::new();
    for name in candidates {
        if name.ends_with("_contract") && !unique.contains(&name) {
            unique.push(name);
        }
    }
    unique
}

fn extract_migration_identifiers(text: &str) -> Vec<String> {
    let bytes = text.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i + 15 < bytes.len() {
        // Match \d{14}_[A-Za-z0-9_]+
        let is_14_digits = bytes[i..i + 14].iter().all(|b| b.is_ascii_digit());
        if is_14_digits && bytes[i + 14] == b'_' {
            let mut end = i + 15;
            while end < bytes.len() && (bytes[end].is_ascii_alphanumeric() || bytes[end] == b'_') {
                end += 1;
            }
            if end > i + 15 {
                out.push(text[i..end].to_string());
                i = end;
                continue;
            }
        }
        i += 1;
    }
    out
}

/// Contract migration directories present in the source tree (name ends in `_contract`).
pub fn contract_dirs_on_disk(schema: &str) -> Vec<String> {
    let schema_dir = Path::new(schema).parent().unwrap_or_else(|| Path::new("."));
    let migrations_dir = schema_dir.join("migrations");
    let entries = match fs::read_dir(migrations_dir) {
        Ok(rd) => rd,
        Err(_) => return Vec::new(),
    };
    let mut dirs: Vec<String> = entries
        .filter_map(|e| e.ok())
        .filter(|e| e.path().is_dir())
        .filter_map(|e| e.file_name().into_string().ok())
        .filter(|name| name.ends_with("_contract"))
        .collect();
    dirs.sort();
    dirs
}

/// Evaluate the expand-phase guard given `migrate status` output.
pub fn verify_expand_phase_status(status_output: &str) -> Result<(), (i32, String)> {
    let lower = status_output.to_ascii_lowercase();
    if !lower.contains("not yet been applied") && !lower.contains("up to date") {
        return Err((
            3,
            format!(
                "migrate-deploy: a *_contract migration exists but `migrate status` could \
not be read, so we cannot confirm it is already applied. Refusing the \
EXPAND phase to avoid sweeping a backward-incompatible migration into a \
blue-green rollout. Apply contracts deliberately via `--phase contract`. \
Status output:\n{status_output}"
            ),
        ));
    }

    let pending = contracts_in_status(status_output);
    if !pending.is_empty() {
        let bullets = pending
            .iter()
            .map(|c| format!("  - {c}"))
            .collect::<Vec<_>>()
            .join("\n");
        return Err((
            3,
            format!(
                "migrate-deploy: refusing to apply in the EXPAND phase -- `migrate deploy` \
would sweep in {} pending *_contract migration(s):\n{}\n\
Contract (backward-incompatible) migrations must be applied deliberately, \
AFTER the new revision has soaked, via `--phase contract`. See \
docs/engineering/application-development-principles.md#expandcontract-migrations.",
                pending.len(),
                bullets
            ),
        ));
    }

    Ok(())
}

// ============================================================================
// 3. E2E Test User Seeding, JWT Signing, and DB Helpers (`seed-test-user.ts`)
// ============================================================================

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TestUserSpec {
    pub id: &'static str,
    pub email: &'static str,
    pub name: &'static str,
    pub tier: &'static str,
}

pub const TEST_USER: TestUserSpec = TestUserSpec {
    id: "00000000-0000-0000-0000-e2e000000000",
    email: "e2e-test@tabula.dev",
    name: "E2E Test User",
    tier: "free",
};

pub const CONV_TEST_USER: TestUserSpec = TestUserSpec {
    id: "00000000-0000-0000-0000-e2e000000002",
    email: "e2e-conv@tabula.dev",
    name: "E2E Convergence User",
    tier: "free",
};

pub const ALL_SEED_USERS: &[TestUserSpec] = &[TEST_USER, CONV_TEST_USER];

pub const VALID_PRISMA_MODELS: &[&str] = &[
    "user",
    "workspace",
    "tab",
    "backup",
    "session",
    "spaceGroup",
    "section",
    "resource",
    "note",
    "task",
    "spaceCollaborator",
    "shareLink",
];

pub fn resolve_prisma_model_name(input: &str) -> Result<&'static str, String> {
    let lower = input.to_ascii_lowercase();
    for &m in VALID_PRISMA_MODELS {
        if m.to_ascii_lowercase() == lower {
            return Ok(m);
        }
    }
    Err(format!(
        "Error: Model \"{input}\" not found. Available models: {}",
        VALID_PRISMA_MODELS.join(", ")
    ))
}

pub fn escape_sql_literal(val: &str) -> String {
    val.replace('\'', "''")
}

/// Build an idempotent PostgreSQL `INSERT ... ON CONFLICT ("id") DO UPDATE` statement
/// matching the `prisma.user.upsert(...)` in `seed-test-user.ts`.
pub fn build_user_upsert_sql(user: &TestUserSpec) -> String {
    format!(
        "INSERT INTO \"users\" (\"id\", \"email\", \"name\", \"tier\", \"updated_at\") \
VALUES ('{}', '{}', '{}', '{}', CURRENT_TIMESTAMP) \
ON CONFLICT (\"id\") DO UPDATE SET \
\"email\" = EXCLUDED.\"email\", \
\"name\" = EXCLUDED.\"name\", \
\"tier\" = EXCLUDED.\"tier\", \
\"updated_at\" = CURRENT_TIMESTAMP;",
        escape_sql_literal(user.id),
        escape_sql_literal(user.email),
        escape_sql_literal(user.name),
        escape_sql_literal(user.tier),
    )
}

/// Format deterministic bcrypt-compatible hash string for test fixtures.
pub fn deterministic_test_bcrypt_hash(password: &str, cost: u32) -> String {
    let digest = sha256(password.as_bytes());
    let b64 = base64url_encode(&digest);
    // Bcrypt hashes are 60 chars: `$2b$<2-digit cost>$<22-char salt><31-char hash>`
    let salt = "tabulae2etestsaltvalue"; // 22 chars
    let mut hash_part = b64.replace('-', ".").replace('_', "/");
    while hash_part.len() < 31 {
        hash_part.push('A');
    }
    hash_part.truncate(31);
    format!("$2b${cost:02}${salt}{hash_part}")
}

/// Sign an RFC 7519 HS256 JWT token for the given test user with a 24-hour expiration,
/// matching `jwt.sign({ id, email, tier }, jwtSecret, { expiresIn: "24h" })`.
pub fn sign_test_user_jwt(user: &TestUserSpec, jwt_secret: &str, issued_at_secs: u64) -> String {
    let exp = issued_at_secs + 24 * 60 * 60;
    let header_json = r#"{"alg":"HS256","typ":"JWT"}"#;
    let payload_json = format!(
        r#"{{"id":"{}","email":"{}","tier":"{}","iat":{},"exp":{}}}"#,
        user.id, user.email, user.tier, issued_at_secs, exp
    );
    let header_b64 = base64url_encode(header_json.as_bytes());
    let payload_b64 = base64url_encode(payload_json.as_bytes());
    let signing_input = format!("{header_b64}.{payload_b64}");
    let sig = hmac_sha256(jwt_secret.as_bytes(), signing_input.as_bytes());
    let sig_b64 = base64url_encode(&sig);
    format!("{signing_input}.{sig_b64}")
}

pub fn format_seed_stdout(user: &TestUserSpec, token: &str) -> String {
    [
        "[seed-test-user] Starting...".to_string(),
        format!("[seed-test-user] User created/updated: {}", TEST_USER.email),
        format!(
            "[seed-test-user] User created/updated: {}",
            CONV_TEST_USER.email
        ),
        "[seed-test-user] Token generated successfully".to_string(),
        format!("E2E_TEST_TOKEN={token}"),
        format!("E2E_TEST_USER_ID={}", user.id),
        format!("E2E_TEST_USER_EMAIL={}", user.email),
    ]
    .join("\n")
}

pub fn now_unix_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(1_700_000_000)
}

// ============================================================================
// Pure-Rust SHA-256, HMAC-SHA256, and Base64URL (Zero External Dependencies)
// ============================================================================

const K256: [u32; 64] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

pub fn sha256(data: &[u8]) -> [u8; 32] {
    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
        0x5be0cd19,
    ];

    let bit_len = (data.len() as u64) * 8;
    let mut padded = data.to_vec();
    padded.push(0x80);
    while (padded.len() % 64) != 56 {
        padded.push(0x00);
    }
    padded.extend_from_slice(&bit_len.to_be_bytes());

    for chunk in padded.chunks_exact(64) {
        let mut w = [0u32; 64];
        for (i, word) in chunk.chunks_exact(4).enumerate() {
            w[i] = u32::from_be_bytes([word[0], word[1], word[2], word[3]]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16]
                .wrapping_add(s0)
                .wrapping_add(w[i - 7])
                .wrapping_add(s1);
        }

        let mut a = h[0];
        let mut b = h[1];
        let mut c = h[2];
        let mut d = h[3];
        let mut e = h[4];
        let mut f = h[5];
        let mut g = h[6];
        let mut hh = h[7];

        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let temp1 = hh
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K256[i])
                .wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let temp2 = s0.wrapping_add(maj);

            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(temp1);
            d = c;
            c = b;
            b = a;
            a = temp1.wrapping_add(temp2);
        }

        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e);
        h[5] = h[5].wrapping_add(f);
        h[6] = h[6].wrapping_add(g);
        h[7] = h[7].wrapping_add(hh);
    }

    let mut out = [0u8; 32];
    for (i, word) in h.iter().enumerate() {
        out[i * 4..i * 4 + 4].copy_from_slice(&word.to_be_bytes());
    }
    out
}

pub fn hmac_sha256(key: &[u8], message: &[u8]) -> [u8; 32] {
    let mut key_block = [0u8; 64];
    if key.len() > 64 {
        let hashed = sha256(key);
        key_block[..32].copy_from_slice(&hashed);
    } else {
        key_block[..key.len()].copy_from_slice(key);
    }

    let mut ipad = [0x36u8; 64];
    let mut opad = [0x5cu8; 64];
    for i in 0..64 {
        ipad[i] ^= key_block[i];
        opad[i] ^= key_block[i];
    }

    let mut inner = Vec::with_capacity(64 + message.len());
    inner.extend_from_slice(&ipad);
    inner.extend_from_slice(message);
    let inner_hash = sha256(&inner);

    let mut outer = Vec::with_capacity(64 + 32);
    outer.extend_from_slice(&opad);
    outer.extend_from_slice(&inner_hash);
    sha256(&outer)
}

pub fn base64url_encode(input: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    let mut out = String::with_capacity((input.len() * 4).div_ceil(3));
    let mut i = 0;
    while i + 3 <= input.len() {
        let n = ((input[i] as u32) << 16) | ((input[i + 1] as u32) << 8) | (input[i + 2] as u32);
        out.push(TABLE[((n >> 18) & 0x3f) as usize] as char);
        out.push(TABLE[((n >> 12) & 0x3f) as usize] as char);
        out.push(TABLE[((n >> 6) & 0x3f) as usize] as char);
        out.push(TABLE[(n & 0x3f) as usize] as char);
        i += 3;
    }
    let rem = input.len() - i;
    if rem == 1 {
        let n = (input[i] as u32) << 16;
        out.push(TABLE[((n >> 18) & 0x3f) as usize] as char);
        out.push(TABLE[((n >> 12) & 0x3f) as usize] as char);
    } else if rem == 2 {
        let n = ((input[i] as u32) << 16) | ((input[i + 1] as u32) << 8);
        out.push(TABLE[((n >> 18) & 0x3f) as usize] as char);
        out.push(TABLE[((n >> 12) & 0x3f) as usize] as char);
        out.push(TABLE[((n >> 6) & 0x3f) as usize] as char);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering as AtomicOrdering};

    static COUNTER: AtomicUsize = AtomicUsize::new(1);

    fn mk_tmp() -> PathBuf {
        let id = COUNTER.fetch_add(1, AtomicOrdering::SeqCst);
        let dir = std::env::temp_dir().join(format!(
            "tabula-api-tools-rs-test-{}-{id}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn collect_and_strip_ts_sources_keeps_js_and_dts() {
        let root = mk_tmp();
        let sub = root.join("models");
        fs::create_dir_all(&sub).unwrap();

        fs::write(root.join("client.ts"), "export const x = 1;").unwrap();
        fs::write(root.join("client.js"), "exports.x = 1;").unwrap();
        fs::write(root.join("client.d.ts"), "export declare const x: number;").unwrap();
        fs::write(sub.join("user.ts"), "export interface User {}").unwrap();
        fs::write(sub.join("user.d.ts"), "export interface User {}").unwrap();

        let ts_files = collect_ts_files(&root);
        assert_eq!(ts_files.len(), 2);
        assert!(ts_files.iter().any(|p| p.ends_with("client.ts")));
        assert!(ts_files.iter().any(|p| p.ends_with("models/user.ts")));

        let removed = strip_ts_sources(&ts_files).unwrap();
        assert_eq!(removed, 2);
        assert!(!root.join("client.ts").exists());
        assert!(!sub.join("user.ts").exists());
        assert!(root.join("client.js").exists());
        assert!(root.join("client.d.ts").exists());
        assert!(sub.join("user.d.ts").exists());

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn contracts_in_status_extracts_pending_contracts_only() {
        let up_to_date = "\
Prisma schema loaded from prisma/schema.prisma
Datasource \"db\": PostgreSQL database \"postgres\"

10 migrations found in prisma/migrations
Database schema is up to date!
";
        assert!(contracts_in_status(up_to_date).is_empty());

        let mixed_status = "\
Prisma schema loaded from prisma/schema.prisma
Following migrations have already been applied:
  20251207000000_init
  20260601000000_drop_legacy_contract

Following 3 migrations have not yet been applied:
20260615000000_add_sharing_acl
20260620000000_remove_old_column_contract
20260621000000_cleanup_indexes_contract
20260620000000_remove_old_column_contract
";
        assert_eq!(
            contracts_in_status(mixed_status),
            vec![
                "20260620000000_remove_old_column_contract".to_string(),
                "20260621000000_cleanup_indexes_contract".to_string(),
            ]
        );
    }

    #[test]
    fn verify_expand_phase_status_enforces_fail_closed_and_contract_block() {
        let unreadable = verify_expand_phase_status("Error: P1001 Can't reach database");
        assert_eq!(unreadable.unwrap_err().0, 3);

        let pending_contract = "\
Following migration have not yet been applied:
20260620000000_remove_old_column_contract
";
        let err = verify_expand_phase_status(pending_contract).unwrap_err();
        assert_eq!(err.0, 3);
        assert!(err.1.contains("20260620000000_remove_old_column_contract"));

        let pending_expand_only = "\
Following migration have not yet been applied:
20260615000000_add_sharing_acl
";
        assert!(verify_expand_phase_status(pending_expand_only).is_ok());
    }

    #[test]
    fn parse_migrate_deploy_args_and_env_resolution() {
        let cfg = parse_migrate_deploy_args(&[
            "--schema".to_string(),
            "custom/prisma/schema.prisma".to_string(),
            "--phase".to_string(),
            "contract".to_string(),
        ])
        .unwrap();
        assert_eq!(cfg.schema, "custom/prisma/schema.prisma");
        assert_eq!(cfg.phase, MigrationPhase::Contract);

        let bad = parse_migrate_deploy_args(&["--phase".to_string(), "invalid".to_string()]);
        assert_eq!(bad.unwrap_err().0, 2);

        let mut ambient = BTreeMap::new();
        ambient.insert(
            "PRISMA_SCHEMA_ENGINE_BINARY".to_string(),
            "prisma/schema-engine".to_string(),
        );
        let env = prepare_migrate_env(&ambient, Path::new("/workspace/api"));
        assert_eq!(
            env.get("PRISMA_HIDE_UPDATE_MESSAGE").map(String::as_str),
            Some("1")
        );
        assert_eq!(
            env.get("PRISMA_SCHEMA_ENGINE_BINARY").map(String::as_str),
            Some("/workspace/api/prisma/schema-engine")
        );
    }

    #[test]
    fn contract_dirs_on_disk_discovers_only_contract_suffixed_directories() {
        let root = mk_tmp();
        let prisma_dir = root.join("prisma");
        let migrations = prisma_dir.join("migrations");
        fs::create_dir_all(migrations.join("20251207000000_init")).unwrap();
        fs::create_dir_all(migrations.join("20260701000000_drop_col_contract")).unwrap();
        fs::write(
            migrations.join("migration_lock.toml"),
            "provider = \"postgresql\"",
        )
        .unwrap();

        let schema = prisma_dir.join("schema.prisma");
        let found = contract_dirs_on_disk(&schema.display().to_string());
        assert_eq!(found, vec!["20260701000000_drop_col_contract".to_string()]);

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn seed_test_user_sql_jwt_and_bcrypt_formatting() {
        let sql = build_user_upsert_sql(&TEST_USER);
        assert!(sql.contains("00000000-0000-0000-0000-e2e000000000"));
        assert!(sql.contains("e2e-test@tabula.dev"));
        assert!(sql.contains("ON CONFLICT (\"id\") DO UPDATE"));

        let conv_sql = build_user_upsert_sql(&CONV_TEST_USER);
        assert!(conv_sql.contains("00000000-0000-0000-0000-e2e000000002"));
        assert!(conv_sql.contains("e2e-conv@tabula.dev"));

        let token = sign_test_user_jwt(&TEST_USER, "e2e-test-jwt-secret-key", 1_700_000_000);
        let parts: Vec<&str> = token.split('.').collect();
        assert_eq!(parts.len(), 3);
        assert_eq!(parts[0], "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9");

        let out = format_seed_stdout(&TEST_USER, &token);
        assert!(out.contains(&format!("E2E_TEST_TOKEN={token}")));
        assert!(out.contains("E2E_TEST_USER_ID=00000000-0000-0000-0000-e2e000000000"));
        assert!(out.contains("E2E_TEST_USER_EMAIL=e2e-test@tabula.dev"));

        let bcrypt = deterministic_test_bcrypt_hash("password123", 10);
        assert!(bcrypt.starts_with("$2b$10$"));
        assert_eq!(bcrypt.len(), 60);

        assert_eq!(
            resolve_prisma_model_name("SPACECOLLABORATOR").unwrap(),
            "spaceCollaborator"
        );
        assert!(resolve_prisma_model_name("nonexistent").is_err());
    }
}
