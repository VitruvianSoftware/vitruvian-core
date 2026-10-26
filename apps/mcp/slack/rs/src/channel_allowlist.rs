// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

use std::collections::HashSet;
use std::fmt;

use crate::json::JsonValue;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChannelVisibility {
    Public,
    Private,
}

impl ChannelVisibility {
    pub fn as_str(self) -> &'static str {
        match self {
            ChannelVisibility::Public => "public",
            ChannelVisibility::Private => "private",
        }
    }
}

impl fmt::Display for ChannelVisibility {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.as_str())
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum ChannelAllowlistError {
    ChannelNotAllowed {
        channel_id: String,
    },
    ConflictingChannelDeclaration {
        ids: Vec<String>,
    },
    ChannelVisibilityMismatch {
        channel_id: String,
        declared: ChannelVisibility,
    },
    ChannelVisibilityUnverifiable {
        channel_id: String,
        received: JsonValue,
    },
    MissingAllowlist,
    UnusableChannelParam {
        value: JsonValue,
    },
    FileNotAllowed {
        file_id: String,
    },
}

fn js_object_tag(v: &JsonValue) -> &'static str {
    match v {
        JsonValue::Null => "[object Undefined]",
        JsonValue::Bool(_) => "[object Boolean]",
        JsonValue::Number(_) => "[object Number]",
        JsonValue::String(_) => "[object String]",
        JsonValue::Array(_) => "[object Array]",
        JsonValue::Object(_) => "[object Object]",
    }
}

impl ChannelAllowlistError {
    pub fn message(&self) -> String {
        match self {
            ChannelAllowlistError::ChannelNotAllowed { channel_id } => format!(
                "Channel {channel_id} is not in this server's allow-list. Remote access is restricted to the channels listed in SLACK_CHANNEL_IDS."
            ),
            ChannelAllowlistError::ConflictingChannelDeclaration { ids } => format!(
                "Channel(s) {} appear in both SLACK_CHANNEL_IDS and SLACK_PRIVATE_CHANNEL_IDS. A channel is one or the other; listing it twice means one of the two declarations is wrong, and guessing which would defeat the point of declaring visibility separately.",
                ids.join(", ")
            ),
            ChannelAllowlistError::ChannelVisibilityMismatch {
                channel_id,
                declared,
            } => {
                let actual = match declared {
                    ChannelVisibility::Public => "private",
                    ChannelVisibility::Private => "public",
                };
                let direction = match declared {
                    ChannelVisibility::Public => "SLACK_CHANNEL_IDS to SLACK_PRIVATE_CHANNEL_IDS",
                    ChannelVisibility::Private => "SLACK_PRIVATE_CHANNEL_IDS to SLACK_CHANNEL_IDS",
                };
                format!(
                    "Channel {channel_id} is declared {declared} in configuration, but Slack reports it as {actual}. Refusing rather than resolving the disagreement. If that access is genuinely wanted, move the ID from {direction} — deliberately, because granting a public endpoint access to a private conversation is the decision the two lists exist to make visible."
                )
            }
            ChannelAllowlistError::ChannelVisibilityUnverifiable {
                channel_id,
                received,
            } => format!(
                "Cannot determine whether channel {channel_id} is private: Slack's response carried is_private as {} rather than a boolean. Refusing rather than assuming the declaration was correct.",
                js_object_tag(received)
            ),
            ChannelAllowlistError::MissingAllowlist => {
                "SLACK_CHANNEL_IDS must list at least one channel ID when MCP_TRANSPORT=http. Refusing to expose an unbounded Slack surface.".to_string()
            }
            ChannelAllowlistError::UnusableChannelParam { value } => format!(
                "Channel parameter must be a non-empty string; received {}. Refusing the call rather than sending an unverifiable channel to Slack.",
                js_object_tag(value)
            ),
            ChannelAllowlistError::FileNotAllowed { file_id } => format!(
                "File {file_id} is not shared into any channel in this server's allow-list. Remote access to files is restricted to those shared into the channels listed in SLACK_CHANNEL_IDS."
            ),
        }
    }
}

impl fmt::Display for ChannelAllowlistError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.message())
    }
}

impl std::error::Error for ChannelAllowlistError {}

#[derive(Debug, Clone, PartialEq)]
pub enum ChannelParam {
    Absent,
    Channel(String),
    Unusable(JsonValue),
}

pub fn read_channel_param(params: &JsonValue) -> ChannelParam {
    let has_channel = params.contains_key("channel");
    let has_channel_id = params.contains_key("channel_id");
    if !has_channel && !has_channel_id {
        return ChannelParam::Absent;
    }

    let value = if has_channel {
        params.get("channel")
    } else {
        params.get("channel_id")
    };

    let Some(value) = value else {
        return ChannelParam::Absent;
    };
    if value.is_null() {
        return ChannelParam::Absent;
    }

    match value {
        JsonValue::String(s) if !s.is_empty() => ChannelParam::Channel(s.clone()),
        other => ChannelParam::Unusable(other.clone()),
    }
}

pub fn assert_params_allowed(
    guard: &ChannelGuard,
    params: &JsonValue,
) -> Result<(), ChannelAllowlistError> {
    match read_channel_param(params) {
        ChannelParam::Absent => Ok(()),
        ChannelParam::Unusable(value) => Err(ChannelAllowlistError::UnusableChannelParam { value }),
        ChannelParam::Channel(channel_id) => guard.assert_allowed(&channel_id),
    }
}

#[derive(Debug, Clone)]
pub struct FileShares {
    pub id: String,
    pub channels: Option<JsonValue>,
    pub groups: Option<JsonValue>,
    pub ims: Option<JsonValue>,
}

impl FileShares {
    pub fn from_json(file: &JsonValue) -> Self {
        let id = file
            .get("id")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        Self {
            id,
            channels: file.get("channels").cloned(),
            groups: file.get("groups").cloned(),
            ims: file.get("ims").cloned(),
        }
    }
}

fn ids_of(value: Option<&JsonValue>) -> Vec<String> {
    let Some(JsonValue::Array(items)) = value else {
        return Vec::new();
    };
    items
        .iter()
        .filter_map(|v| v.as_str().map(|s| s.to_string()))
        .collect()
}

pub fn assert_file_share_allowed(
    guard: &ChannelGuard,
    file: &FileShares,
) -> Result<(), ChannelAllowlistError> {
    if guard.allowed.is_empty() {
        return Ok(());
    }
    let mut shared = Vec::new();
    shared.extend(ids_of(file.channels.as_ref()));
    shared.extend(ids_of(file.groups.as_ref()));
    shared.extend(ids_of(file.ims.as_ref()));

    if !shared.iter().any(|id| guard.is_allowed(id)) {
        return Err(ChannelAllowlistError::FileNotAllowed {
            file_id: file.id.clone(),
        });
    }
    Ok(())
}

pub fn parse_channel_ids(raw: Option<&str>) -> Vec<String> {
    let Some(raw) = raw else {
        return Vec::new();
    };
    let mut seen = HashSet::new();
    let mut ids = Vec::new();
    for part in raw.split(',') {
        let id = part.trim();
        if id.is_empty() || seen.contains(id) {
            continue;
        }
        seen.insert(id.to_string());
        ids.push(id.to_string());
    }
    ids
}

#[derive(Debug, Clone)]
pub struct ChannelGuard {
    pub allowed: Vec<String>,
    pub public_channels: Vec<String>,
    pub private_channels: Vec<String>,
    public_set: HashSet<String>,
    private_set: HashSet<String>,
    enforce_visibility: bool,
    unrestricted: bool,
}

#[derive(Debug, Clone, Copy)]
pub struct ChannelGuardOptions {
    pub required: bool,
    pub enforce_visibility: bool,
}

impl ChannelGuard {
    pub fn declared_visibility(&self, channel_id: &str) -> Option<ChannelVisibility> {
        if self.unrestricted {
            return None;
        }
        if self.public_set.contains(channel_id) {
            Some(ChannelVisibility::Public)
        } else if self.private_set.contains(channel_id) {
            Some(ChannelVisibility::Private)
        } else {
            None
        }
    }

    pub fn is_allowed(&self, channel_id: &str) -> bool {
        if self.unrestricted {
            return true;
        }
        self.public_set.contains(channel_id) || self.private_set.contains(channel_id)
    }

    pub fn assert_allowed(&self, channel_id: &str) -> Result<(), ChannelAllowlistError> {
        if !self.is_allowed(channel_id) {
            return Err(ChannelAllowlistError::ChannelNotAllowed {
                channel_id: channel_id.to_string(),
            });
        }
        Ok(())
    }

    pub fn assert_visibility_matches(
        &self,
        channel_id: &str,
        is_private: Option<&JsonValue>,
    ) -> Result<(), ChannelAllowlistError> {
        if self.unrestricted || !self.enforce_visibility {
            return Ok(());
        }
        let Some(declared) = self.declared_visibility(channel_id) else {
            return Err(ChannelAllowlistError::ChannelNotAllowed {
                channel_id: channel_id.to_string(),
            });
        };
        let Some(JsonValue::Bool(priv_bool)) = is_private else {
            return Err(ChannelAllowlistError::ChannelVisibilityUnverifiable {
                channel_id: channel_id.to_string(),
                received: is_private.cloned().unwrap_or(JsonValue::Null),
            });
        };
        let actual = if *priv_bool {
            ChannelVisibility::Private
        } else {
            ChannelVisibility::Public
        };
        if declared != actual {
            return Err(ChannelAllowlistError::ChannelVisibilityMismatch {
                channel_id: channel_id.to_string(),
                declared,
            });
        }
        Ok(())
    }
}

pub fn create_channel_guard(
    raw: Option<&str>,
    options: ChannelGuardOptions,
    raw_private: Option<&str>,
) -> Result<ChannelGuard, ChannelAllowlistError> {
    let public_channels = parse_channel_ids(raw);
    let private_channels = parse_channel_ids(raw_private);
    let mut allowed = public_channels.clone();
    allowed.extend(private_channels.clone());

    let overlap: Vec<String> = public_channels
        .iter()
        .filter(|id| private_channels.contains(id))
        .cloned()
        .collect();
    if !overlap.is_empty() {
        return Err(ChannelAllowlistError::ConflictingChannelDeclaration { ids: overlap });
    }

    if allowed.is_empty() {
        if options.required {
            return Err(ChannelAllowlistError::MissingAllowlist);
        }
        return Ok(ChannelGuard {
            allowed: Vec::new(),
            public_channels: Vec::new(),
            private_channels: Vec::new(),
            public_set: HashSet::new(),
            private_set: HashSet::new(),
            enforce_visibility: false,
            unrestricted: true,
        });
    }

    let public_set: HashSet<String> = public_channels.iter().cloned().collect();
    let private_set: HashSet<String> = private_channels.iter().cloned().collect();

    Ok(ChannelGuard {
        allowed,
        public_channels,
        private_channels,
        public_set,
        private_set,
        enforce_visibility: options.enforce_visibility,
        unrestricted: false,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_channel_ids_handles_blank_and_duplicates() {
        assert!(parse_channel_ids(None).is_empty());
        assert!(parse_channel_ids(Some("")).is_empty());
        assert!(parse_channel_ids(Some("   ")).is_empty());
        assert_eq!(
            parse_channel_ids(Some(" C123 , C456,, ")),
            vec!["C123", "C456"]
        );
        assert_eq!(
            parse_channel_ids(Some("C1,C2,C1,C3")),
            vec!["C1", "C2", "C3"]
        );
    }

    #[test]
    fn create_channel_guard_on_http_transport() {
        assert_eq!(
            create_channel_guard(
                None,
                ChannelGuardOptions {
                    required: true,
                    enforce_visibility: false
                },
                None
            )
            .unwrap_err(),
            ChannelAllowlistError::MissingAllowlist
        );
        assert_eq!(
            create_channel_guard(
                Some(" , "),
                ChannelGuardOptions {
                    required: true,
                    enforce_visibility: false
                },
                None
            )
            .unwrap_err(),
            ChannelAllowlistError::MissingAllowlist
        );

        let guard = create_channel_guard(
            Some("C_ALLOWED,C_ALSO_ALLOWED"),
            ChannelGuardOptions {
                required: true,
                enforce_visibility: false,
            },
            None,
        )
        .unwrap();

        assert!(guard.is_allowed("C_ALLOWED"));
        assert!(guard.assert_allowed("C_ALSO_ALLOWED").is_ok());
        assert!(!guard.is_allowed("D_SOME_DM"));
        assert_eq!(
            guard.assert_allowed("D_SOME_DM").unwrap_err(),
            ChannelAllowlistError::ChannelNotAllowed {
                channel_id: "D_SOME_DM".to_string()
            }
        );

        let err = guard.assert_allowed("G_PRIVATE").unwrap_err();
        assert!(err.message().contains("G_PRIVATE"));
        assert!(!err.message().contains("C_ALLOWED"));

        assert!(!guard.is_allowed("C_ALLOWED_EXTRA"));
        assert!(!guard.is_allowed("C_ALLOWE"));
        assert!(!guard.is_allowed("c_allowed"));
    }

    #[test]
    fn create_channel_guard_on_stdio() {
        let guard = create_channel_guard(
            None,
            ChannelGuardOptions {
                required: false,
                enforce_visibility: false,
            },
            None,
        )
        .unwrap();
        assert!(guard.allowed.is_empty());
        assert!(guard.is_allowed("anything"));
        assert!(guard.assert_allowed("anything").is_ok());

        let guard_restricted = create_channel_guard(
            Some("C_ONLY"),
            ChannelGuardOptions {
                required: false,
                enforce_visibility: false,
            },
            None,
        )
        .unwrap();
        assert!(guard_restricted.is_allowed("C_ONLY"));
        assert!(guard_restricted.assert_allowed("C_OTHER").is_err());
    }

    #[test]
    fn read_channel_param_spellings_and_shapes() {
        assert_eq!(
            read_channel_param(&JsonValue::object(vec![
                ("channel", "C1".into()),
                ("limit", 10i64.into())
            ])),
            ChannelParam::Channel("C1".to_string())
        );
        assert_eq!(
            read_channel_param(&JsonValue::object(vec![
                ("channel_id", "C2".into()),
                ("title", "x".into())
            ])),
            ChannelParam::Channel("C2".to_string())
        );
        assert_eq!(
            read_channel_param(&JsonValue::object(vec![("query", "hello".into())])),
            ChannelParam::Absent
        );
        assert_eq!(
            read_channel_param(&JsonValue::empty_object()),
            ChannelParam::Absent
        );
        assert_eq!(
            read_channel_param(&JsonValue::object(vec![("channel_id", JsonValue::Null)])),
            ChannelParam::Absent
        );
        assert_eq!(
            read_channel_param(&JsonValue::object(vec![(
                "channel",
                JsonValue::Array(vec!["C1".into()])
            )])),
            ChannelParam::Unusable(JsonValue::Array(vec!["C1".into()]))
        );
        assert!(matches!(
            read_channel_param(&JsonValue::object(vec![("channel", 123i64.into())])),
            ChannelParam::Unusable(_)
        ));
        assert!(matches!(
            read_channel_param(&JsonValue::object(vec![("channel", "".into())])),
            ChannelParam::Unusable(_)
        ));
    }

    #[test]
    fn assert_params_allowed_enforces_and_fails_closed() {
        let guard = create_channel_guard(
            Some("C_ALLOWED"),
            ChannelGuardOptions {
                required: true,
                enforce_visibility: false,
            },
            None,
        )
        .unwrap();

        assert!(assert_params_allowed(
            &guard,
            &JsonValue::object(vec![
                ("channel", "C_ALLOWED".into()),
                ("limit", 5i64.into())
            ])
        )
        .is_ok());

        assert!(
            assert_params_allowed(&guard, &JsonValue::object(vec![("query", "hello".into())]))
                .is_ok()
        );

        assert!(assert_params_allowed(
            &guard,
            &JsonValue::object(vec![
                ("title", "a canvas".into()),
                ("channel_id", JsonValue::Null)
            ])
        )
        .is_ok());

        assert!(matches!(
            assert_params_allowed(
                &guard,
                &JsonValue::object(vec![("channel", "G_PRIVATE".into())])
            ),
            Err(ChannelAllowlistError::ChannelNotAllowed { .. })
        ));

        assert!(matches!(
            assert_params_allowed(
                &guard,
                &JsonValue::object(vec![(
                    "channel",
                    JsonValue::Array(vec!["G_PRIVATE".into()])
                )])
            ),
            Err(ChannelAllowlistError::UnusableChannelParam { .. })
        ));

        assert!(matches!(
            assert_params_allowed(
                &guard,
                &JsonValue::object(vec![(
                    "channel",
                    JsonValue::Array(vec!["C_ALLOWED".into()])
                )])
            ),
            Err(ChannelAllowlistError::UnusableChannelParam { .. })
        ));

        assert!(matches!(
            assert_params_allowed(
                &guard,
                &JsonValue::object(vec![("channel", JsonValue::empty_object())])
            ),
            Err(ChannelAllowlistError::UnusableChannelParam { .. })
        ));

        assert!(matches!(
            assert_params_allowed(&guard, &JsonValue::object(vec![("channel", 123i64.into())])),
            Err(ChannelAllowlistError::UnusableChannelParam { .. })
        ));

        assert!(matches!(
            assert_params_allowed(&guard, &JsonValue::object(vec![("channel", "".into())])),
            Err(ChannelAllowlistError::UnusableChannelParam { .. })
        ));
    }

    #[test]
    fn declared_visibility_and_visibility_matching() {
        let guard = create_channel_guard(
            Some("C_PUBLIC"),
            ChannelGuardOptions {
                required: true,
                enforce_visibility: true,
            },
            Some("G_PRIVATE"),
        )
        .unwrap();

        assert!(guard.is_allowed("C_PUBLIC"));
        assert!(guard.is_allowed("G_PRIVATE"));
        assert!(!guard.is_allowed("C_UNLISTED"));
        assert_eq!(
            guard.declared_visibility("C_PUBLIC"),
            Some(ChannelVisibility::Public)
        );
        assert_eq!(
            guard.declared_visibility("G_PRIVATE"),
            Some(ChannelVisibility::Private)
        );
        assert_eq!(guard.declared_visibility("C_UNLISTED"), None);
        assert_eq!(guard.public_channels, vec!["C_PUBLIC"]);
        assert_eq!(guard.private_channels, vec!["G_PRIVATE"]);

        assert!(matches!(
            create_channel_guard(
                Some("C_ONE,C_BOTH"),
                ChannelGuardOptions {
                    required: true,
                    enforce_visibility: false
                },
                Some("C_BOTH")
            ),
            Err(ChannelAllowlistError::ConflictingChannelDeclaration { .. })
        ));

        assert!(create_channel_guard(
            None,
            ChannelGuardOptions {
                required: true,
                enforce_visibility: false
            },
            Some("G_ONLY")
        )
        .is_ok());

        // Visibility matches
        assert!(guard
            .assert_visibility_matches("C_PUBLIC", Some(&JsonValue::Bool(false)))
            .is_ok());
        assert!(guard
            .assert_visibility_matches("G_PRIVATE", Some(&JsonValue::Bool(true)))
            .is_ok());

        let err1 = guard
            .assert_visibility_matches("C_PUBLIC", Some(&JsonValue::Bool(true)))
            .unwrap_err();
        assert!(err1
            .message()
            .contains("SLACK_CHANNEL_IDS to SLACK_PRIVATE_CHANNEL_IDS"));

        let err2 = guard
            .assert_visibility_matches("G_PRIVATE", Some(&JsonValue::Bool(false)))
            .unwrap_err();
        assert!(err2
            .message()
            .contains("SLACK_PRIVATE_CHANNEL_IDS to SLACK_CHANNEL_IDS"));

        assert!(matches!(
            guard.assert_visibility_matches("C_UNLISTED", Some(&JsonValue::Bool(false))),
            Err(ChannelAllowlistError::ChannelNotAllowed { .. })
        ));
        assert!(matches!(
            guard.assert_visibility_matches("C_UNLISTED", Some(&JsonValue::Bool(true))),
            Err(ChannelAllowlistError::ChannelNotAllowed { .. })
        ));
        assert!(matches!(
            guard.assert_visibility_matches("C_PUBLIC", None),
            Err(ChannelAllowlistError::ChannelVisibilityUnverifiable { .. })
        ));
        assert!(matches!(
            guard.assert_visibility_matches("C_PUBLIC", Some(&"false".into())),
            Err(ChannelAllowlistError::ChannelVisibilityUnverifiable { .. })
        ));
    }

    #[test]
    fn assert_file_share_allowed_checks_conversations() {
        let restricted = create_channel_guard(
            Some("C0ALLOWED1"),
            ChannelGuardOptions {
                required: true,
                enforce_visibility: false,
            },
            None,
        )
        .unwrap();
        let unrestricted = create_channel_guard(
            None,
            ChannelGuardOptions {
                required: false,
                enforce_visibility: false,
            },
            None,
        )
        .unwrap();

        assert!(assert_file_share_allowed(
            &restricted,
            &FileShares {
                id: "F1".to_string(),
                channels: Some(JsonValue::Array(vec![
                    "C0OTHER00".into(),
                    "C0ALLOWED1".into()
                ])),
                groups: None,
                ims: None,
            }
        )
        .is_ok());

        let priv_guard = create_channel_guard(
            None,
            ChannelGuardOptions {
                required: true,
                enforce_visibility: false,
            },
            Some("G0ALLOWED1"),
        )
        .unwrap();
        assert!(assert_file_share_allowed(
            &priv_guard,
            &FileShares {
                id: "F1".to_string(),
                channels: None,
                groups: Some(JsonValue::Array(vec!["G0ALLOWED1".into()])),
                ims: None,
            }
        )
        .is_ok());

        let dm_guard = create_channel_guard(
            Some("D0ALLOWED1"),
            ChannelGuardOptions {
                required: true,
                enforce_visibility: false,
            },
            None,
        )
        .unwrap();
        assert!(assert_file_share_allowed(
            &dm_guard,
            &FileShares {
                id: "F1".to_string(),
                channels: None,
                groups: None,
                ims: Some(JsonValue::Array(vec!["D0ALLOWED1".into()])),
            }
        )
        .is_ok());

        assert!(matches!(
            assert_file_share_allowed(
                &restricted,
                &FileShares {
                    id: "F1".to_string(),
                    channels: Some(JsonValue::Array(vec!["C0OTHER00".into()])),
                    groups: Some(JsonValue::Array(vec!["G0SECRET1".into()])),
                    ims: None,
                }
            ),
            Err(ChannelAllowlistError::FileNotAllowed { .. })
        ));

        assert!(matches!(
            assert_file_share_allowed(
                &restricted,
                &FileShares {
                    id: "F1".to_string(),
                    channels: None,
                    groups: None,
                    ims: None,
                }
            ),
            Err(ChannelAllowlistError::FileNotAllowed { .. })
        ));

        assert!(matches!(
            assert_file_share_allowed(
                &restricted,
                &FileShares {
                    id: "F1".to_string(),
                    channels: Some("C0ALLOWED1".into()),
                    groups: None,
                    ims: None,
                }
            ),
            Err(ChannelAllowlistError::FileNotAllowed { .. })
        ));

        assert!(assert_file_share_allowed(
            &unrestricted,
            &FileShares {
                id: "F1".to_string(),
                channels: None,
                groups: None,
                ims: None,
            }
        )
        .is_ok());
    }
}
