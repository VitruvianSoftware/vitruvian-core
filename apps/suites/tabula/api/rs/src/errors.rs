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

use serde_json::{json, Value};
use std::fmt;

/// Typed HTTP errors matching `src/lib/errors.ts` and `src/lib/errorHandler.ts`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AppError {
    Conflict {
        message: String,
        current_version: u64,
    },
    Forbidden {
        message: String,
    },
    NotFound {
        message: String,
    },
    BadRequest {
        message: String,
        details: Option<Value>,
    },
    Unauthorized {
        message: String,
    },
    PayloadTooLarge {
        message: String,
    },
    SchemaDrift {
        code: String,
        message: String,
    },
    Status {
        status_code: u16,
        name: String,
        message: String,
    },
    Internal {
        message: String,
    },
}

impl AppError {
    pub fn conflict(message: impl Into<String>, current_version: u64) -> Self {
        Self::Conflict {
            message: message.into(),
            current_version,
        }
    }

    pub fn forbidden(message: impl Into<String>) -> Self {
        Self::Forbidden {
            message: message.into(),
        }
    }

    pub fn forbidden_default() -> Self {
        Self::Forbidden {
            message: "Insufficient permissions for this space".to_string(),
        }
    }

    pub fn not_found(message: impl Into<String>) -> Self {
        Self::NotFound {
            message: message.into(),
        }
    }

    pub fn not_found_default() -> Self {
        Self::NotFound {
            message: "Not found".to_string(),
        }
    }

    pub fn bad_request(message: impl Into<String>) -> Self {
        Self::BadRequest {
            message: message.into(),
            details: None,
        }
    }

    pub fn validation(details: Value) -> Self {
        Self::BadRequest {
            message: "Validation failed".to_string(),
            details: Some(details),
        }
    }

    pub fn unauthorized(message: impl Into<String>) -> Self {
        Self::Unauthorized {
            message: message.into(),
        }
    }

    pub fn internal(message: impl Into<String>) -> Self {
        Self::Internal {
            message: message.into(),
        }
    }

    pub fn status_code(&self) -> u16 {
        match self {
            Self::Conflict { .. } => 409,
            Self::Forbidden { .. } => 403,
            Self::NotFound { .. } => 404,
            Self::BadRequest { .. } => 400,
            Self::Unauthorized { .. } => 401,
            Self::PayloadTooLarge { .. } => 413,
            Self::SchemaDrift { .. } => 503,
            Self::Status { status_code, .. } => *status_code,
            Self::Internal { .. } => 500,
        }
    }

    pub fn name(&self) -> &str {
        match self {
            Self::Conflict { .. } => "ConflictError",
            Self::Forbidden { .. } => "ForbiddenError",
            Self::NotFound { .. } => "NotFoundError",
            Self::BadRequest {
                details: Some(_), ..
            } => "ZodError",
            Self::BadRequest { details: None, .. } => "BadRequest",
            Self::Unauthorized { .. } => "Unauthorized",
            Self::PayloadTooLarge { .. } => "PayloadTooLargeError",
            Self::SchemaDrift { .. } => "PrismaClientKnownRequestError",
            Self::Status { name, .. } => name.as_str(),
            Self::Internal { .. } => "Error",
        }
    }

    pub fn message(&self) -> &str {
        match self {
            Self::Conflict { message, .. }
            | Self::Forbidden { message }
            | Self::NotFound { message }
            | Self::BadRequest { message, .. }
            | Self::Unauthorized { message }
            | Self::PayloadTooLarge { message }
            | Self::SchemaDrift { message, .. }
            | Self::Status { message, .. }
            | Self::Internal { message } => message.as_str(),
        }
    }

    pub fn current_version(&self) -> Option<u64> {
        match self {
            Self::Conflict {
                current_version, ..
            } => Some(*current_version),
            _ => None,
        }
    }

    pub fn is_conflict(&self) -> bool {
        matches!(self, Self::Conflict { .. })
    }

    pub fn is_forbidden(&self) -> bool {
        matches!(self, Self::Forbidden { .. })
    }

    pub fn is_not_found(&self) -> bool {
        matches!(self, Self::NotFound { .. })
    }
}

impl fmt::Display for AppError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.message())
    }
}

/// Detect Prisma schema-drift error shapes (P2021 missing table, P2022 missing column).
pub fn is_schema_drift_error_value(err: &Value) -> bool {
    let Some(obj) = err.as_object() else {
        return false;
    };
    let name = obj.get("name").and_then(Value::as_str).unwrap_or("");
    let code = obj.get("code").and_then(Value::as_str).unwrap_or("");
    name == "PrismaClientKnownRequestError" && (code == "P2021" || code == "P2022")
}

pub fn is_schema_drift_error(err: &AppError) -> bool {
    match err {
        AppError::SchemaDrift { code, .. } => code == "P2021" || code == "P2022",
        _ => false,
    }
}

/// Format an `AppError` into `(status_code, json_body)` matching `src/lib/errorHandler.ts`.
pub fn format_error_response(err: &AppError, is_production: bool) -> (u16, Value) {
    match err {
        AppError::BadRequest {
            details: Some(details),
            ..
        } => (
            400,
            json!({
                "error": "Bad Request",
                "message": "Validation failed",
                "details": details,
            }),
        ),
        AppError::BadRequest {
            message,
            details: None,
        } => (
            400,
            json!({
                "error": "Bad Request",
                "message": message,
            }),
        ),
        AppError::PayloadTooLarge { .. } => (
            413,
            json!({
                "error": "Payload Too Large",
                "message": "Request body exceeds the maximum allowed size",
            }),
        ),
        AppError::SchemaDrift { code, .. } if code == "P2021" || code == "P2022" => (
            503,
            json!({
                "error": "Service Unavailable",
                "message": "The service is temporarily unavailable. Please try again shortly.",
            }),
        ),
        AppError::Conflict {
            message,
            current_version,
        } => (
            409,
            json!({
                "error": "Conflict",
                "message": message,
                "currentVersion": current_version,
            }),
        ),
        AppError::Forbidden { message } => (
            403,
            json!({
                "error": "ForbiddenError",
                "message": message,
            }),
        ),
        AppError::NotFound { message } => (
            404,
            json!({
                "error": "NotFoundError",
                "message": message,
            }),
        ),
        AppError::Unauthorized { message } => (
            401,
            json!({
                "error": "Unauthorized",
                "message": message,
            }),
        ),
        AppError::Status {
            status_code,
            name,
            message,
        } => {
            if *status_code < 500 {
                (
                    *status_code,
                    json!({
                        "error": if name.is_empty() { "Bad Request" } else { name.as_str() },
                        "message": message,
                    }),
                )
            } else {
                (
                    *status_code,
                    json!({
                        "error": "Internal Server Error",
                        "message": if is_production {
                            "An unexpected error occurred"
                        } else {
                            message.as_str()
                        },
                    }),
                )
            }
        }
        AppError::Internal { message } | AppError::SchemaDrift { message, .. } => (
            500,
            json!({
                "error": "Internal Server Error",
                "message": if is_production {
                    "An unexpected error occurred"
                } else {
                    message.as_str()
                },
            }),
        ),
    }
}

/// Convert an arbitrary JSON error object (used by unit tests mirroring Fastify's `errorHandler`)
/// into `(status_code, body)`.
pub fn handle_arbitrary_error(err: &Value, is_production: bool) -> (u16, Value) {
    if is_schema_drift_error_value(err) {
        return format_error_response(
            &AppError::SchemaDrift {
                code: "P2022".to_string(),
                message: String::new(),
            },
            is_production,
        );
    }
    if let Some(obj) = err.as_object() {
        let code = obj.get("code").and_then(Value::as_str).unwrap_or("");
        if code == "FST_ERR_CTP_BODY_TOO_LARGE" {
            return format_error_response(
                &AppError::PayloadTooLarge {
                    message: "Request payload exceeds maximum allowed size".to_string(),
                },
                is_production,
            );
        }
        if obj.get("name").and_then(Value::as_str) == Some("ZodError")
            || obj.contains_key("issues")
            || obj.contains_key("validation")
        {
            let details = obj
                .get("errors")
                .or_else(|| obj.get("issues"))
                .or_else(|| obj.get("validation"))
                .cloned()
                .unwrap_or_else(|| json!([]));
            return (
                400,
                json!({
                    "error": "Bad Request",
                    "message": "Invalid input",
                    "details": details,
                }),
            );
        }
        let status_code = obj
            .get("statusCode")
            .and_then(Value::as_u64)
            .map(|n| n as u16)
            .unwrap_or(500);
        let name = obj
            .get("name")
            .and_then(Value::as_str)
            .unwrap_or("Error")
            .to_string();
        let message = obj
            .get("message")
            .and_then(Value::as_str)
            .unwrap_or("An unexpected error occurred")
            .to_string();
        return format_error_response(
            &AppError::Status {
                status_code,
                name,
                message,
            },
            is_production,
        );
    }
    format_error_response(
        &AppError::Internal {
            message: err
                .as_str()
                .unwrap_or("An unexpected error occurred")
                .to_string(),
        },
        is_production,
    )
}
