// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

use crate::GChatError;
use base64::Engine as _;
use prost_reflect::{DynamicMessage, FieldDescriptor, Kind, MessageDescriptor, ReflectMessage};
use serde_json::Value;

pub const MAX_PBLITE_DEPTH: usize = 64;

/// Decodes a 1-indexed pblite JSON array value into a protobuf message of type `M`
/// using `prost_reflect::MessageDescriptor`.
pub fn decode_pblite<M: prost::Message + Default>(
    desc: &MessageDescriptor,
    value: &Value,
) -> Result<M, GChatError> {
    let dynamic = decode_pblite_dynamic(desc, value, 0)?;
    dynamic
        .transcode_to::<M>()
        .map_err(|e| GChatError::Protocol(format!("pblite transcode failed: {e}")))
}

pub fn decode_pblite_dynamic(
    desc: &MessageDescriptor,
    value: &Value,
    depth: usize,
) -> Result<DynamicMessage, GChatError> {
    if depth > MAX_PBLITE_DEPTH {
        return Err(GChatError::Protocol(
            "max pblite nesting depth 64 exceeded".to_string(),
        ));
    }
    let arr = value
        .as_array()
        .ok_or_else(|| GChatError::Protocol("pblite value must be a JSON array".to_string()))?;

    let mut msg = DynamicMessage::new(desc.clone());
    if arr.is_empty() {
        return Ok(msg);
    }

    let mut pos_len = arr.len();
    let mut trailing_map: Option<&serde_json::Map<String, Value>> = None;
    if let Some(Value::Object(map)) = arr.last() {
        let last_tag = u32::try_from(arr.len()).ok();
        let is_proto_map = last_tag
            .and_then(|tag| desc.get_field(tag))
            .is_some_and(|f| f.is_map());
        if !is_proto_map {
            pos_len = arr.len() - 1;
            trailing_map = Some(map);
        }
    }

    for (i, elem) in arr[..pos_len].iter().enumerate() {
        if elem.is_null() {
            continue;
        }
        let Ok(tag) = u32::try_from(i + 1) else {
            continue;
        };
        decode_tag(&mut msg, desc, tag, elem, depth)?;
    }

    if let Some(map) = trailing_map {
        let mut keyed: Vec<(u32, &Value)> = Vec::with_capacity(map.len());
        for (k, v) in map {
            if let Ok(parsed) = k.parse::<i32>() {
                if let Ok(tag) = u32::try_from(parsed) {
                    if tag > 0 {
                        keyed.push((tag, v));
                    }
                }
            }
        }
        keyed.sort_by_key(|(tag, _)| *tag);
        for (tag, elem) in keyed {
            if elem.is_null() {
                continue;
            }
            decode_tag(&mut msg, desc, tag, elem, depth)?;
        }
    }

    Ok(msg)
}

fn decode_tag(
    msg: &mut DynamicMessage,
    desc: &MessageDescriptor,
    tag: u32,
    val: &Value,
    depth: usize,
) -> Result<(), GChatError> {
    let Some(fd) = desc.get_field(tag) else {
        // Check nested arrays even on unknown fields if needed? No, unknown tags are skipped cleanly.
        return Ok(());
    };
    decode_field(msg, &fd, val, depth)
}

fn decode_field(
    msg: &mut DynamicMessage,
    fd: &FieldDescriptor,
    val: &Value,
    depth: usize,
) -> Result<(), GChatError> {
    if fd.is_map() {
        return Ok(());
    }
    if fd.is_list() {
        let Some(items) = val.as_array() else {
            return Ok(());
        };
        let mut list = Vec::with_capacity(items.len());
        for item in items {
            if item.is_null() {
                continue;
            }
            if let Some(decoded) = decode_singular_value(&fd.kind(), item, depth)? {
                list.push(decoded);
            }
        }
        msg.set_field(fd, prost_reflect::Value::List(list));
        return Ok(());
    }

    if let Some(decoded) = decode_singular_value(&fd.kind(), val, depth)? {
        msg.set_field(fd, decoded);
    }
    Ok(())
}

fn decode_singular_value(
    kind: &Kind,
    val: &Value,
    depth: usize,
) -> Result<Option<prost_reflect::Value>, GChatError> {
    match kind {
        Kind::Message(sub_desc) => {
            if !val.is_array() {
                return Ok(None);
            }
            let sub = decode_pblite_dynamic(sub_desc, val, depth + 1)?;
            Ok(Some(prost_reflect::Value::Message(sub)))
        }
        Kind::Enum(enum_desc) => {
            let num = match val {
                Value::Number(n) => n.as_i64().and_then(|v| i32::try_from(v).ok()),
                Value::String(s) => s.parse::<i32>().ok(),
                _ => None,
            };
            if let Some(n) = num {
                if enum_desc.get_value(n).is_some() {
                    return Ok(Some(prost_reflect::Value::EnumNumber(n)));
                }
            }
            Ok(None)
        }
        Kind::Bool => {
            let b = match val {
                Value::Bool(b) => Some(*b),
                Value::Number(n) => n
                    .as_i64()
                    .map(|i| i != 0)
                    .or_else(|| n.as_f64().map(|f| f != 0.0)),
                Value::String(s) => match s.as_str() {
                    "1" | "true" => Some(true),
                    "0" | "false" => Some(false),
                    _ => None,
                },
                _ => None,
            };
            Ok(b.map(prost_reflect::Value::Bool))
        }
        Kind::Int64 | Kind::Sint64 | Kind::Sfixed64 => {
            let n = match val {
                Value::String(s) => s.parse::<i64>().ok(),
                Value::Number(num) => num.as_i64().or_else(|| num.as_f64().map(|f| f as i64)),
                _ => None,
            };
            Ok(n.map(prost_reflect::Value::I64))
        }
        Kind::Uint64 | Kind::Fixed64 => {
            let n = match val {
                Value::String(s) => s.parse::<u64>().ok(),
                Value::Number(num) => num.as_u64().or_else(|| num.as_f64().map(|f| f as u64)),
                _ => None,
            };
            Ok(n.map(prost_reflect::Value::U64))
        }
        Kind::Int32 | Kind::Sint32 | Kind::Sfixed32 => {
            let n = match val {
                Value::Number(num) => num
                    .as_i64()
                    .and_then(|v| i32::try_from(v).ok())
                    .or_else(|| num.as_f64().map(|f| f as i32)),
                Value::String(s) => s.parse::<i32>().ok(),
                _ => None,
            };
            Ok(n.map(prost_reflect::Value::I32))
        }
        Kind::Uint32 | Kind::Fixed32 => {
            let n = match val {
                Value::Number(num) => num
                    .as_u64()
                    .and_then(|v| u32::try_from(v).ok())
                    .or_else(|| num.as_f64().map(|f| f as u32)),
                Value::String(s) => s.parse::<u32>().ok(),
                _ => None,
            };
            Ok(n.map(prost_reflect::Value::U32))
        }
        Kind::Float => {
            let n = match val {
                Value::Number(num) => num.as_f64().map(|f| f as f32),
                Value::String(s) => s.parse::<f32>().ok(),
                _ => None,
            };
            Ok(n.map(prost_reflect::Value::F32))
        }
        Kind::Double => {
            let n = match val {
                Value::Number(num) => num.as_f64(),
                Value::String(s) => s.parse::<f64>().ok(),
                _ => None,
            };
            Ok(n.map(prost_reflect::Value::F64))
        }
        Kind::String => match val {
            Value::String(s) => Ok(Some(prost_reflect::Value::String(s.clone()))),
            _ => Ok(None),
        },
        Kind::Bytes => match val {
            Value::String(s) => {
                let decoded = base64::engine::general_purpose::STANDARD
                    .decode(s)
                    .or_else(|_| base64::engine::general_purpose::URL_SAFE.decode(s))
                    .ok();
                Ok(decoded.map(|b| prost_reflect::Value::Bytes(b.into())))
            }
            _ => Ok(None),
        },
    }
}

/// Encodes a protobuf message into a 1-indexed pblite JSON array value.
pub fn encode_pblite<M: prost::Message>(
    desc: &MessageDescriptor,
    message: &M,
) -> Result<Value, GChatError> {
    let bytes = message.encode_to_vec();
    let dynamic = DynamicMessage::decode(desc.clone(), bytes.as_slice())
        .map_err(|e| GChatError::Protocol(format!("failed to decode message for pblite: {e}")))?;
    encode_pblite_dynamic(&dynamic)
}

pub fn encode_pblite_dynamic(msg: &DynamicMessage) -> Result<Value, GChatError> {
    let desc = msg.descriptor();
    let mut max_field = 0u32;
    for fd in desc.fields() {
        if msg.has_field(&fd) {
            if fd.number() > max_field {
                max_field = fd.number();
            }
        }
    }
    if max_field == 0 {
        return Ok(Value::Array(Vec::new()));
    }
    let mut out = vec![Value::Null; max_field as usize];
    for fd in desc.fields() {
        if !msg.has_field(&fd) {
            continue;
        }
        if fd.is_map() {
            return Err(GChatError::Protocol(
                "pblite does not support map fields".to_string(),
            ));
        }
        let val = msg.get_field(&fd);
        let json_val = if fd.is_list() {
            let Some(list) = val.as_list() else {
                continue;
            };
            let mut arr = Vec::with_capacity(list.len());
            for item in list {
                arr.push(encode_singular_value(&fd.kind(), item)?);
            }
            Value::Array(arr)
        } else {
            encode_singular_value(&fd.kind(), &val)?
        };
        out[(fd.number() - 1) as usize] = json_val;
    }
    Ok(Value::Array(out))
}

fn encode_singular_value(kind: &Kind, val: &prost_reflect::Value) -> Result<Value, GChatError> {
    match (kind, val) {
        (Kind::Message(_), prost_reflect::Value::Message(sub)) => encode_pblite_dynamic(sub),
        (Kind::Bytes, prost_reflect::Value::Bytes(b)) => Ok(Value::String(
            base64::engine::general_purpose::STANDARD.encode(b),
        )),
        (Kind::Int64 | Kind::Sint64 | Kind::Sfixed64, prost_reflect::Value::I64(n)) => {
            Ok(Value::String(n.to_string()))
        }
        (Kind::Uint64 | Kind::Fixed64, prost_reflect::Value::U64(n)) => {
            Ok(Value::String(n.to_string()))
        }
        (Kind::Int32 | Kind::Sint32 | Kind::Sfixed32, prost_reflect::Value::I32(n)) => {
            Ok(Value::Number((*n).into()))
        }
        (Kind::Uint32 | Kind::Fixed32, prost_reflect::Value::U32(n)) => {
            Ok(Value::Number((*n).into()))
        }
        (Kind::Float, prost_reflect::Value::F32(f)) => serde_json::Number::from_f64(*f as f64)
            .map(Value::Number)
            .ok_or_else(|| GChatError::Protocol("non-finite float in pblite".to_string())),
        (Kind::Double, prost_reflect::Value::F64(f)) => serde_json::Number::from_f64(*f)
            .map(Value::Number)
            .ok_or_else(|| GChatError::Protocol("non-finite double in pblite".to_string())),
        (Kind::Enum(_), prost_reflect::Value::EnumNumber(n)) => Ok(Value::Number((*n).into())),
        (Kind::Bool, prost_reflect::Value::Bool(b)) => Ok(Value::Bool(*b)),
        (Kind::String, prost_reflect::Value::String(s)) => Ok(Value::String(s.clone())),
        _ => Err(GChatError::Protocol(format!(
            "mismatched pblite value for kind {kind:?}"
        ))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{pb, DESCRIPTOR_POOL};
    use serde_json::json;

    #[test]
    fn test_pblite_maps_one_indexed_array_positions_to_field_numbers() {
        let desc = DESCRIPTOR_POOL
            .get_message_by_name("googlechat.User")
            .expect("User descriptor");
        // User: 1=user_id, 2=name, 3=avatar_url, 4=email, 5=first_name, 6=last_name, 7=deleted
        let raw = json!([
            ["112233445566778899001", 0],
            "Alice Example",
            "https://lh3.googleusercontent.com/a/alice",
            "alice@example.com",
            "Alice",
            "Example",
            false
        ]);
        let user: pb::User = decode_pblite(&desc, &raw).expect("decode User");
        assert_eq!(
            user.user_id.as_ref().and_then(|u| u.id.as_deref()),
            Some("112233445566778899001")
        );
        assert_eq!(user.name.as_deref(), Some("Alice Example"));
        assert_eq!(
            user.avatar_url.as_deref(),
            Some("https://lh3.googleusercontent.com/a/alice")
        );
        assert_eq!(user.email.as_deref(), Some("alice@example.com"));
        assert_eq!(user.first_name.as_deref(), Some("Alice"));
        assert_eq!(user.last_name.as_deref(), Some("Example"));
        assert_eq!(user.deleted, Some(false));
    }

    #[test]
    fn test_pblite_merges_trailing_sparse_object_keys_in_numeric_order() {
        // 1. Check sparse keys {"100": [...], "15": [...]} and numeric ascending order on Annotation oneof:
        // In serde_json::Map (BTreeMap), "100" < "15" < "8" lexicographically, whereas numeric order is 8 < 15 < 100.
        // Annotation oneof Metadata has format_metadata = 8 and slash_command_metadata = 15.
        // With {"15": [[null, "deploy"], 1], "8": [1]}, lexicographical order would apply 15 then 8 (leaving 8 active),
        // whereas ascending numeric order applies 8 then 15 (leaving 15 slash_command_metadata active).
        let ann_desc = DESCRIPTOR_POOL
            .get_message_by_name("googlechat.Annotation")
            .expect("Annotation descriptor");
        let sparse_ann: Value =
            serde_json::from_str(r#"[16, 0, 7, {"15": [null, null, "deploy"], "8": [1]}]"#)
                .expect("valid json");
        let ann: pb::Annotation = decode_pblite(&ann_desc, &sparse_ann).expect("decode Annotation");
        match ann.metadata {
            Some(pb::annotation::Metadata::SlashCommandMetadata(ref sc)) => {
                assert_eq!(sc.command_name.as_deref(), Some("deploy"));
            }
            other => panic!(
                "expected SlashCommandMetadata (field 15) to win over FormatMetadata (field 8) in numeric order, got {other:?}"
            ),
        }

        // 2. Also verify sparse object with keys "100" and "15" on Message + StreamEventsRequest
        let msg_desc = DESCRIPTOR_POOL
            .get_message_by_name("googlechat.Message")
            .expect("Message descriptor");
        let sparse_msg: Value = serde_json::from_str(
            r#"[null, {"100": ["ignored-unknown"], "37": [null, "1711234567890123"], "15": [[[ "<b>card</b>" ]]]}]"#,
        )
        .expect("valid json");
        let msg: pb::Message = decode_pblite(&msg_desc, &sparse_msg).expect("decode Message");
        assert_eq!(msg.attachments.len(), 1);
        assert_eq!(
            msg.reply_to.as_ref().and_then(|r| r.create_time),
            Some(1_711_234_567_890_123)
        );
    }

    #[test]
    fn test_pblite_preserves_64bit_integer_precision_from_strings() {
        let msg_desc = DESCRIPTOR_POOL
            .get_message_by_name("googlechat.Message")
            .expect("Message descriptor");
        // Message: 1=id, 2=creator (User: 1=user_id [id, type]), 3=create_time (int64)
        let raw = json!([
            [null, "msg-1"],
            [["112233445566778899001", 0], "Alice Example"],
            "1711234567890123",
            "9007199254740993"
        ]);
        let msg: pb::Message = decode_pblite(&msg_desc, &raw).expect("decode Message");
        assert_eq!(msg.create_time, Some(1_711_234_567_890_123));
        assert_eq!(msg.last_update_time, Some(9_007_199_254_740_993));
        assert_eq!(
            msg.creator
                .as_ref()
                .and_then(|c| c.user_id.as_ref())
                .and_then(|u| u.id.as_deref()),
            Some("112233445566778899001")
        );
    }

    #[test]
    fn test_pblite_decodes_bool_from_0_1_and_bytes_from_base64() {
        let bm_desc = DESCRIPTOR_POOL
            .get_message_by_name("googlechat.BackendMetadata")
            .expect("BackendMetadata descriptor");
        let raw_bytes = vec![0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x42];
        let b64 = base64::engine::general_purpose::STANDARD.encode(&raw_bytes);

        // BackendMetadata: 3 = dispatch_random_filler (bytes), 6 = user_targeted_event_dual_dispatch (bool)
        let val_one = json!([null, null, b64, null, null, 1]);
        let bm1: pb::BackendMetadata =
            decode_pblite(&bm_desc, &val_one).expect("decode BackendMetadata with 1");
        assert_eq!(
            bm1.dispatch_random_filler.as_deref(),
            Some(raw_bytes.as_slice())
        );
        assert_eq!(bm1.user_targeted_event_dual_dispatch, Some(true));

        let val_zero = json!([null, null, null, null, null, 0]);
        let bm0: pb::BackendMetadata =
            decode_pblite(&bm_desc, &val_zero).expect("decode BackendMetadata with 0");
        assert_eq!(bm0.user_targeted_event_dual_dispatch, Some(false));
    }

    #[test]
    fn test_pblite_skips_null_and_unknown_tags_without_error() {
        let desc = DESCRIPTOR_POOL
            .get_message_by_name("googlechat.GroupId")
            .expect("GroupId descriptor");
        for sample in [
            json!([
                ["space-abc"],
                null,
                null,
                null,
                "unknown-positional",
                {"9999": "unknown-sparse", "4294967298": 1}
            ]),
            json!([]),
            json!([{"8888": [1, 2, 3]}]),
        ] {
            let res: Result<pb::GroupId, GChatError> = decode_pblite(&desc, &sample);
            assert!(
                res.is_ok(),
                "expected permissive decode to succeed, got {res:?}"
            );
        }
    }

    #[test]
    fn test_pblite_enforces_max_depth_64() {
        let desc = DESCRIPTOR_POOL
            .get_message_by_name("googlechat.Message")
            .expect("Message descriptor");
        // Message.last_reply is field 12 (0-based index 11). Build a 65-level nested array.
        let mut nested = json!([]);
        for _ in 0..65 {
            nested =
                json!([null, null, null, null, null, null, null, null, null, null, null, nested]);
        }
        let err = decode_pblite::<pb::Message>(&desc, &nested)
            .expect_err("65-level nested pblite array must fail with max depth error");
        match err {
            GChatError::Protocol(msg) => {
                assert_eq!(msg, "max pblite nesting depth 64 exceeded");
            }
            other => panic!("expected GChatError::Protocol, got {other:?}"),
        }
    }

    #[test]
    fn test_pblite_decodes_webchannel_event_with_nested_event_bodies() {
        let desc = DESCRIPTOR_POOL
            .get_message_by_name("googlechat.WebChannelEvent")
            .expect("WebChannelEvent descriptor");
        // WebChannelEvent field 1 = Event.
        // Event: field 1 = group_id, field 3 = type (MESSAGE_POSTED = 6), field 4 = body (EventBody),
        // field 8 = bodies (repeated EventBody).
        // EventBody: field 6 = message_posted (MessageEvent: field 1 = Message: field 10 = text_body),
        // field 12 = event_type.
        let body_one = json!([
            null,
            null,
            null,
            null,
            null,
            [[
                null,
                null,
                "1711234567000001",
                null,
                null,
                null,
                null,
                null,
                null,
                "First body message"
            ]],
            null,
            null,
            null,
            null,
            null,
            6
        ]);
        let body_two = json!([
            null,
            null,
            null,
            null,
            null,
            [[
                null,
                null,
                "1711234567000002",
                null,
                null,
                null,
                null,
                null,
                null,
                "Second body message"
            ]],
            null,
            null,
            null,
            null,
            null,
            6
        ]);
        let event_arr = json!([
            [["space-xyz"]],
            null,
            6,
            body_one,
            null,
            null,
            null,
            [body_two]
        ]);
        let wc_arr = json!([event_arr, "sample-1"]);

        let wc: pb::WebChannelEvent =
            decode_pblite(&desc, &wc_arr).expect("decode WebChannelEvent");
        let event = wc.event.expect("event present");
        assert_eq!(
            event
                .body
                .as_ref()
                .and_then(|b| match &b.r#type {
                    Some(pb::event::event_body::Type::MessagePosted(mp)) => mp.message.as_ref(),
                    _ => None,
                })
                .and_then(|m| m.text_body.as_deref()),
            Some("First body message")
        );
        assert_eq!(event.bodies.len(), 1);
        assert_eq!(
            match &event.bodies[0].r#type {
                Some(pb::event::event_body::Type::MessagePosted(mp)) => {
                    mp.message.as_ref().and_then(|m| m.text_body.as_deref())
                }
                _ => None,
            },
            Some("Second body message")
        );
    }
}
