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
// SPDX-License-Identifier: MIT

//! Roborock cloud login by emailed verification code (the v4 flow).

use crate::config::{self, Credentials};
use serde_json::{Map, Value};
use std::collections::HashMap;
use std::fmt;
use std::sync::{Arc, Mutex};

pub const SETUP_HINT: &str =
    "Not logged in to Roborock. Run `rrctl setup`, or call the setup_login tool with your account email.";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AuthError {
    Failed(String),
    NotAuthenticated(String),
}

impl AuthError {
    pub fn failed(msg: impl Into<String>) -> Self {
        Self::Failed(msg.into())
    }

    pub fn not_authenticated() -> Self {
        Self::NotAuthenticated(SETUP_HINT.to_string())
    }

    pub fn not_authenticated_with(msg: impl Into<String>) -> Self {
        Self::NotAuthenticated(msg.into())
    }

    pub fn is_not_authenticated(&self) -> bool {
        matches!(self, Self::NotAuthenticated(_))
    }

    pub fn message(&self) -> &str {
        match self {
            Self::Failed(m) | Self::NotAuthenticated(m) => m,
        }
    }
}

impl fmt::Display for AuthError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.message())
    }
}

impl std::error::Error for AuthError {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ApiError {
    pub class_name: String,
    pub message: String,
}

impl ApiError {
    pub fn new(class_name: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            class_name: class_name.into(),
            message: message.into(),
        }
    }
}

impl fmt::Display for ApiError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}: {}", self.class_name, self.message)
    }
}

impl std::error::Error for ApiError {}

pub trait ApiClient: Send + Sync {
    fn request_code_v4(&self) -> Result<(), ApiError>;
    fn code_login_v4(&self, code: &str) -> Result<Map<String, Value>, ApiError>;
    fn base_url(&self) -> Option<String> {
        None
    }
}

pub type ClientFactory = Arc<dyn Fn(&str) -> Arc<dyn ApiClient> + Send + Sync>;

pub fn explain_api_error(err: &ApiError) -> String {
    match err.class_name.as_str() {
        "RoborockAccountDoesNotExist" => "No Roborock account uses that email address.".to_string(),
        "RoborockInvalidEmail" => "That is not a valid email address.".to_string(),
        "RoborockInvalidCode" => {
            "That verification code is wrong or has expired. Request a new one.".to_string()
        }
        "RoborockTooFrequentCodeRequests" => {
            "A code was requested too recently. Wait a minute and try again.".to_string()
        }
        "RoborockRateLimit" | "RoborockTooManyRequest" => {
            "Roborock is rate limiting logins from here. Try again later.".to_string()
        }
        "RoborockInvalidUserAgreement" => {
            "Accept the latest user agreement in the Roborock app, then try again.".to_string()
        }
        "RoborockNoUserAgreement" => {
            "Accept the user agreement in the Roborock app, then try again.".to_string()
        }
        "RoborockNoResponseFromBaseURL" => {
            "Could not reach the Roborock cloud. Check the network and try again.".to_string()
        }
        "RoborockUrlException" => {
            "Could not find the Roborock region for that account.".to_string()
        }
        _ => format!("Roborock login failed: {}", err.message),
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AuthStatus {
    pub authenticated: bool,
    pub email: Option<String>,
    pub credentials_path: Option<String>,
    pub migrated_from: Option<String>,
    pub error: Option<String>,
}

impl AuthStatus {
    pub fn as_dict(&self) -> Map<String, Value> {
        let mut doc = Map::new();
        doc.insert("authenticated".to_string(), Value::Bool(self.authenticated));
        if let Some(ref email) = self.email {
            if !email.is_empty() {
                doc.insert(
                    "email".to_string(),
                    Value::String(config::mask_email(email)),
                );
            }
        }
        if let Some(ref path) = self.credentials_path {
            if !path.is_empty() {
                doc.insert("credentials_path".to_string(), Value::String(path.clone()));
            }
        }
        if let Some(ref migrated) = self.migrated_from {
            if !migrated.is_empty() {
                doc.insert("migrated_from".to_string(), Value::String(migrated.clone()));
            }
        }
        if let Some(ref error) = self.error {
            if !error.is_empty() {
                doc.insert("error".to_string(), Value::String(error.clone()));
            }
        }
        if !self.authenticated {
            doc.insert("hint".to_string(), Value::String(SETUP_HINT.to_string()));
        }
        doc
    }

    pub fn as_value(&self) -> Value {
        Value::Object(self.as_dict())
    }
}

pub fn auth_status() -> AuthStatus {
    match config::load_credentials() {
        Err(err) => AuthStatus {
            authenticated: false,
            email: None,
            credentials_path: None,
            migrated_from: None,
            error: Some(err.to_string()),
        },
        Ok(None) => AuthStatus {
            authenticated: false,
            email: None,
            credentials_path: None,
            migrated_from: None,
            error: None,
        },
        Ok(Some(credentials)) => AuthStatus {
            authenticated: true,
            email: Some(credentials.email),
            credentials_path: Some(config::credentials_path().to_string_lossy().into_owned()),
            migrated_from: credentials.migrated_from,
            error: None,
        },
    }
}

pub fn require_credentials() -> Result<Credentials, AuthError> {
    match config::load_credentials() {
        Err(err) => Err(AuthError::not_authenticated_with(format!(
            "{err}. Run `rrctl setup` to log in again."
        ))),
        Ok(None) => Err(AuthError::not_authenticated()),
        Ok(Some(creds)) => Ok(creds),
    }
}

#[derive(Clone)]
pub struct LoginFlow {
    client_factory: ClientFactory,
    pending: Arc<Mutex<HashMap<String, Arc<dyn ApiClient>>>>,
}

impl Default for LoginFlow {
    fn default() -> Self {
        Self::new(None)
    }
}

impl LoginFlow {
    pub fn new(client_factory: Option<ClientFactory>) -> Self {
        let factory = client_factory.unwrap_or_else(|| {
            Arc::new(|email: &str| -> Arc<dyn ApiClient> {
                Arc::new(crate::cloud::CloudClient::new(email, None))
            })
        });
        Self {
            client_factory: factory,
            pending: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub fn request_code(&self, email: &str) -> Result<(), AuthError> {
        let email = normalise_email(email)?;
        let client = (self.client_factory)(&email);
        client
            .request_code_v4()
            .map_err(|err| AuthError::failed(explain_api_error(&err)))?;
        self.pending
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .insert(email, client);
        Ok(())
    }

    pub fn complete(&self, email: &str, code: &str) -> Result<Credentials, AuthError> {
        let email = normalise_email(email)?;
        let cleaned_code: String = code.split_whitespace().collect();
        if cleaned_code.is_empty() || !cleaned_code.chars().all(|c| c.is_ascii_digit()) {
            return Err(AuthError::failed(
                "The verification code is the number Roborock emailed you.",
            ));
        }
        let client = self
            .pending
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .get(&email)
            .cloned()
            .ok_or_else(|| {
                AuthError::failed(
                    "No code has been requested for that email in this session. Request one first.",
                )
            })?;
        let user_data = client
            .code_login_v4(&cleaned_code)
            .map_err(|err| AuthError::failed(explain_api_error(&err)))?;
        let base_url = client.base_url();
        let mut credentials = Credentials::new(email.clone(), user_data);
        if let Some(url) = base_url {
            credentials = credentials.with_base_url(url);
        }
        config::save_credentials(&credentials).map_err(|err| AuthError::failed(err.to_string()))?;
        self.pending
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .remove(&email);
        Ok(credentials)
    }
}

fn normalise_email(email: &str) -> Result<String, AuthError> {
    let trimmed = email.trim().to_lowercase();
    if !trimmed.contains('@') {
        return Err(AuthError::failed("That is not a valid email address."));
    }
    Ok(trimmed)
}
