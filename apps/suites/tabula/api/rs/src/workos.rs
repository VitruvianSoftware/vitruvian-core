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

use crate::secrets::{get_secret_with, DefaultSecretManagerBackend, SecretManagerBackend};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct WorkOSUser {
    pub email: Option<String>,
    pub first_name: Option<String>,
    pub last_name: Option<String>,
    #[serde(default)]
    pub profile_picture_url: Option<String>,
}

/// Trait abstracting WorkOS UserManagement operations (`src/lib/workos.ts`).
/// Importing or constructing the module is completely inert when `WORKOS_API_KEY`
/// or `WORKOS_CLIENT_ID` are absent, avoiding cold-deploy failures.
pub trait WorkOSProvider: Send + Sync {
    fn get_authorization_url(
        &self,
        client_id: &str,
        provider: &str,
        redirect_uri: &str,
    ) -> Result<String, String>;

    fn authenticate_with_code(&self, client_id: &str, code: &str) -> Result<WorkOSUser, String>;
}

pub struct DefaultWorkOSProvider;

impl WorkOSProvider for DefaultWorkOSProvider {
    fn get_authorization_url(
        &self,
        client_id: &str,
        provider: &str,
        redirect_uri: &str,
    ) -> Result<String, String> {
        Ok(format!(
            "https://api.workos.com/user_management/authorize?client_id={client_id}&provider={provider}&redirect_uri={redirect_uri}&response_type=code"
        ))
    }

    fn authenticate_with_code(&self, _client_id: &str, _code: &str) -> Result<WorkOSUser, String> {
        Err("WorkOS authenticateWithCode requires valid code in live environment".to_string())
    }
}

pub fn get_workos_client_id(
    env: &BTreeMap<String, String>,
    secret_backend: &dyn SecretManagerBackend,
) -> Result<String, String> {
    get_secret_with("WORKOS_CLIENT_ID", env, secret_backend)
}

pub fn get_workos_api_key(
    env: &BTreeMap<String, String>,
    secret_backend: &dyn SecretManagerBackend,
) -> Result<String, String> {
    get_secret_with("WORKOS_API_KEY", env, secret_backend)
}

pub fn get_workos() -> DefaultWorkOSProvider {
    let _ = DefaultSecretManagerBackend;
    DefaultWorkOSProvider
}
