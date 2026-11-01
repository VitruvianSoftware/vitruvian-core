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

use std::process::Command;

use tabula_api_tools::store::PgClient;
use tabula_api_tools::{
    build_user_upsert_sql, format_seed_stdout, now_unix_secs, sign_test_user_jwt, ALL_SEED_USERS,
    TEST_USER,
};

fn main() {
    let jwt_secret = match std::env::var("JWT_SECRET") {
        Ok(v) if !v.is_empty() => v,
        _ => {
            eprintln!("ERROR: JWT_SECRET environment variable is required");
            std::process::exit(1);
        }
    };

    if let Ok(db_url) = std::env::var("DATABASE_URL") {
        if !db_url.is_empty() && std::env::var("TABULA_SEED_DRY_RUN").as_deref() != Ok("1") {
            let mut used_pg_client = false;
            if let Ok(pg) = PgClient::from_url(&db_url) {
                let mut all_ok = true;
                for user in ALL_SEED_USERS {
                    let sql = build_user_upsert_sql(user);
                    if pg.execute_simple(&sql).is_err() {
                        all_ok = false;
                        break;
                    }
                }
                used_pg_client = all_ok;
            }
            if !used_pg_client {
                for user in ALL_SEED_USERS {
                    let sql = build_user_upsert_sql(user);
                    let status = Command::new("psql")
                        .args([&db_url, "-v", "ON_ERROR_STOP=1", "-c", &sql])
                        .status();
                    if let Ok(s) = status {
                        if !s.success() {
                            eprintln!("[seed-test-user] Error upserting user {}", user.email);
                            std::process::exit(1);
                        }
                    }
                }
            }
        }
    }

    let token = sign_test_user_jwt(&TEST_USER, &jwt_secret, now_unix_secs());
    println!("{}", format_seed_stdout(&TEST_USER, &token));
}
