// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only
#ifndef COURIER_GCHAT_H
#define COURIER_GCHAT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct GChatClient GChatClient;

typedef enum GChatStatus {
  GCHAT_OK = 0,
  GCHAT_ERR_INVALID_ARG = 1,
  GCHAT_ERR_AUTH_EXPIRED = 2,
  GCHAT_ERR_RATE_LIMITED = 3,
  GCHAT_ERR_TRANSIENT = 4,
  GCHAT_ERR_SSRF_BLOCKED = 5,
  GCHAT_ERR_PROTOCOL = 6,
  GCHAT_ERR_INTERNAL = 7,
} GChatStatus;

typedef enum GChatEventKind {
  GCHAT_EVENT_KIND_EVENT_PROTO = 1,
  GCHAT_EVENT_KIND_AUTH_EXPIRED = 2,
  GCHAT_EVENT_KIND_RESYNC = 3,
  GCHAT_EVENT_KIND_CONNECTED = 4,
  GCHAT_EVENT_KIND_STREAM_ERROR = 5,
} GChatEventKind;

typedef struct GChatByteSlice {
  uint8_t *ptr;
  size_t len;
} GChatByteSlice;

typedef void (*GChatEventCallback)(
    uintptr_t userdata,
    int32_t event_kind,
    const uint8_t *payload_ptr,
    size_t payload_len);

GChatStatus gchat_client_new(
    const uint8_t *config_json_ptr,
    size_t config_json_len,
    GChatClient **out_client,
    GChatByteSlice *out_err);

void gchat_client_free(GChatClient *client);
void gchat_bytes_free(GChatByteSlice slice);

GChatStatus gchat_validate_session(
    GChatClient *client,
    GChatByteSlice *out_self_json,
    GChatByteSlice *out_err);

GChatStatus gchat_start_stream(
    GChatClient *client,
    GChatEventCallback cb,
    uintptr_t userdata,
    GChatByteSlice *out_err);

void gchat_stop_stream(GChatClient *client);

GChatStatus gchat_rpc_call(
    GChatClient *client,
    const char *endpoint_ptr,
    size_t endpoint_len,
    const uint8_t *req_proto_ptr,
    size_t req_proto_len,
    GChatByteSlice *out_resp_proto,
    GChatByteSlice *out_err);

GChatStatus gchat_html_to_annotations(
    const uint8_t *input_json_ptr,
    size_t input_json_len,
    GChatByteSlice *out_result_json,
    GChatByteSlice *out_err);

GChatStatus gchat_annotations_to_html(
    const uint8_t *input_proto_ptr,
    size_t input_proto_len,
    GChatByteSlice *out_result_json,
    GChatByteSlice *out_err);

GChatStatus gchat_upload_media(
    GChatClient *client,
    const uint8_t *req_json_ptr,
    size_t req_json_len,
    const uint8_t *data_ptr,
    size_t data_len,
    GChatByteSlice *out_upload_proto,
    GChatByteSlice *out_err);

GChatStatus gchat_download_media(
    GChatClient *client,
    const uint8_t *req_json_ptr,
    size_t req_json_len,
    GChatByteSlice *out_bytes,
    GChatByteSlice *out_err);

#ifdef __cplusplus
}
#endif

#endif  // COURIER_GCHAT_H
