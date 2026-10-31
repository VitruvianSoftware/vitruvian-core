// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

#[macro_export]
macro_rules! edition2021 {
    ($($item:tt)*) => {
        $($item)*
    };
}

pub mod auth;
pub mod channel;
pub mod cookies;
pub mod ffi;
pub mod fmt;
#[cfg(any(test, feature = "test-loopback"))]
pub mod fuzz_tests;
pub mod media;
pub mod netguard;
pub mod pblite;
pub mod rpc;

pub use ffi::GChatClient;

pub mod pb {
    #![allow(clippy::all, dead_code, non_camel_case_types, non_snake_case)]
    include!(concat!(env!("OUT_DIR"), "/googlechat.rs"));
}

pub use pb as googlechat;

use once_cell::sync::Lazy as LazyLock;
use prost_reflect::DescriptorPool;
use thiserror::Error;

pub const FILE_DESCRIPTOR_SET: &[u8] =
    include_bytes!(concat!(env!("OUT_DIR"), "/googlechat_descriptor.bin"));

pub static DESCRIPTOR_POOL: LazyLock<DescriptorPool> = LazyLock::new(|| {
    DescriptorPool::decode(FILE_DESCRIPTOR_SET).expect("valid googlechat.proto descriptor set")
});

#[derive(Debug, Error)]
pub enum GChatError {
    #[error("cookie validation failed: {0}")]
    CookieValidation(String),
    #[error("authentication expired or invalid: {0}")]
    AuthExpired(String),
    #[error("blocked by network guard: {0}")]
    SsrfBlocked(String),
    #[error("rate limited by Google Chat")]
    RateLimited,
    #[error("HTTP status {0}: {1}")]
    HttpStatus(u16, String),
    #[error("network error: {0}")]
    Network(String),
    #[error("protobuf error: {0}")]
    Proto(String),
    #[error("protocol error: {0}")]
    Protocol(String),
    #[error("internal error: {0}")]
    Internal(String),
}

#[cfg(test)]
mod tests {
    use super::*;
    use prost::Message;
    use prost_reflect::DynamicMessage;

    #[test]
    fn descriptor_pool_loads_googlechat_proto() {
        let header_desc = DESCRIPTOR_POOL
            .get_message_by_name("googlechat.RequestHeader")
            .expect("RequestHeader descriptor must exist");

        let req = crate::pb::RequestHeader {
            trace_id: Some(42),
            client_type: Some(crate::pb::request_header::ClientType::Web as i32),
            client_version: Some(2440378181258),
            locale: Some("en".to_string()),
            client_feature_capabilities: Some(crate::pb::ClientFeatureCapabilities {
                spam_room_invites_level: Some(
                    crate::pb::client_feature_capabilities::CapabilityLevel::FullySupported as i32,
                ),
                ..Default::default()
            }),
        };
        let encoded = req.encode_to_vec();
        let dynamic = DynamicMessage::decode(header_desc, encoded.as_slice())
            .expect("DynamicMessage::decode succeeded");
        let json = serde_json::to_value(&dynamic).expect("ProtoJSON serialize succeeded");
        assert_eq!(json["clientType"], "WEB");
        assert_eq!(json["locale"], "en");

        assert!(DESCRIPTOR_POOL
            .get_message_by_name("googlechat.Event")
            .is_some());
        assert!(DESCRIPTOR_POOL
            .get_message_by_name("googlechat.Message")
            .is_some());
        assert!(DESCRIPTOR_POOL
            .get_message_by_name("googlechat.Annotation")
            .is_some());
        let attachment_desc = DESCRIPTOR_POOL
            .get_message_by_name("googlechat.Attachment")
            .expect("Attachment descriptor must exist");
        let field_15 = attachment_desc
            .get_field(15)
            .expect("Attachment field 15 (app_card_data) must exist");
        assert_eq!(field_15.name(), "app_card_data");
        assert!(DESCRIPTOR_POOL
            .get_message_by_name("googlechat.WebChannelEvent")
            .is_some());
        assert!(DESCRIPTOR_POOL
            .get_message_by_name("googlechat.PaginatedWorldResponse")
            .is_some());
    }
}
