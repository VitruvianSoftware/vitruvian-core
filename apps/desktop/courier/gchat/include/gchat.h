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

typedef void (*GChatEventCallback)(
    uintptr_t userdata,
    const char *event_json_ptr,
    size_t event_json_len
);

void gchat_string_free(char *ptr);

char *gchat_validate_session(
    const char *config_json,
    char **err_out
);

GChatClient *gchat_client_new(
    const char *config_json,
    GChatEventCallback cb,
    uintptr_t userdata,
    char **err_out
);

int gchat_client_connect(
    GChatClient *client,
    char **err_out
);

void gchat_client_disconnect(GChatClient *client);

void gchat_client_free(GChatClient *client);

char *gchat_client_call_json(
    GChatClient *client,
    const char *method,
    const char *req_json,
    char **err_out
);

char *gchat_client_upload_media(
    GChatClient *client,
    const char *group_id,
    const char *filename,
    const char *mime_type,
    const uint8_t *bytes_ptr,
    size_t bytes_len,
    char **err_out
);

int gchat_client_download_media(
    GChatClient *client,
    const char *url,
    uint8_t **bytes_out,
    size_t *len_out,
    char **mime_out,
    char **err_out
);

void gchat_bytes_free(uint8_t *ptr, size_t len);

#ifdef __cplusplus
}
#endif

#endif // COURIER_GCHAT_H
