// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

/*
#include "gchat.h"
#include <stdlib.h>
*/
import "C"

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"unsafe"
)

// ScopedCookie represents a single domain-scoped cookie for Google Chat.
type ScopedCookie struct {
	Name   string `json:"name"`
	Value  string `json:"value"`
	Domain string `json:"domain"`
	Path   string `json:"path"`
}

// SessionConfig is serialized to JSON for gchat_client_new and gchat_validate_session.
type SessionConfig struct {
	Cookies   []ScopedCookie    `json:"cookies,omitempty"`
	CookieMap map[string]string `json:"cookie_map,omitempty"`
	UserAgent string            `json:"user_agent,omitempty"`
	BaseURL   string            `json:"base_url,omitempty"`
}

// ValidatedSession is returned by gchat_validate_session.
type ValidatedSession struct {
	GaiaID    string `json:"gaia_id"`
	Name      string `json:"name"`
	Email     string `json:"email"`
	AvatarURL string `json:"avatar_url"`
}

func takeByteSlice(slice C.GChatByteSlice) []byte {
	if slice.ptr == nil || slice.len == 0 {
		return nil
	}
	defer C.gchat_bytes_free(slice)
	return C.GoBytes(unsafe.Pointer(slice.ptr), C.int(slice.len))
}

func statusError(status C.GChatStatus, errSlice C.GChatByteSlice) error {
	errBytes := takeByteSlice(errSlice)
	if len(errBytes) > 0 {
		return errors.New(string(errBytes))
	}
	return fmt.Errorf("gchat ffi error status %d", int(status))
}

// LinkCheck verifies that libgchat_ffi.a is linked and callable via cgo by
// round-tripping a synthetic Annotation conversion (HTML <-> Message proto).
func LinkCheck() error {
	inputJSON := []byte(`{"html":"<b>Hello</b> World"}`)
	var htmlOut C.GChatByteSlice
	var errOut C.GChatByteSlice
	st := C.gchat_html_to_annotations(
		(*C.uint8_t)(unsafe.Pointer(&inputJSON[0])),
		C.size_t(len(inputJSON)),
		&htmlOut,
		&errOut,
	)
	if st != C.GCHAT_OK {
		return statusError(st, errOut)
	}
	encodedJSON := takeByteSlice(htmlOut)
	var step1 struct {
		Text               string `json:"text"`
		MessageProtoBase64 string `json:"message_proto_base64"`
	}
	if err := json.Unmarshal(encodedJSON, &step1); err != nil {
		return fmt.Errorf("unmarshal html_to_annotations output: %w", err)
	}
	if step1.Text != "Hello World" {
		return fmt.Errorf("unexpected plain text %q", step1.Text)
	}
	protoBytes, err := base64.StdEncoding.DecodeString(step1.MessageProtoBase64)
	if err != nil || len(protoBytes) == 0 {
		return fmt.Errorf("decode message_proto_base64: %w", err)
	}

	var renderOut C.GChatByteSlice
	var renderErr C.GChatByteSlice
	st = C.gchat_annotations_to_html(
		(*C.uint8_t)(unsafe.Pointer(&protoBytes[0])),
		C.size_t(len(protoBytes)),
		&renderOut,
		&renderErr,
	)
	if st != C.GCHAT_OK {
		return statusError(st, renderErr)
	}
	renderedJSON := takeByteSlice(renderOut)
	var step2 struct {
		Text             string `json:"text"`
		HTML             string `json:"html"`
		AnnotationsCount int    `json:"annotations_count"`
	}
	if err := json.Unmarshal(renderedJSON, &step2); err != nil {
		return fmt.Errorf("unmarshal annotations_to_html output: %w", err)
	}
	if step2.HTML != "<b>Hello</b> World" || step2.AnnotationsCount != 1 {
		return fmt.Errorf("unexpected round-trip annotation output: %+v", step2)
	}
	return nil
}

// ValidateSession validates cookies against /u/0/mole/world and /u/0/api/get_self_user_status.
func ValidateSession(cfg SessionConfig) (*ValidatedSession, error) {
	raw, err := json.Marshal(cfg)
	if err != nil {
		return nil, fmt.Errorf("marshal session config: %w", err)
	}
	if len(raw) == 0 {
		return nil, errors.New("empty session config")
	}

	var client *C.GChatClient
	var newErr C.GChatByteSlice
	st := C.gchat_client_new(
		(*C.uint8_t)(unsafe.Pointer(&raw[0])),
		C.size_t(len(raw)),
		&client,
		&newErr,
	)
	if st != C.GCHAT_OK {
		return nil, statusError(st, newErr)
	}
	defer C.gchat_client_free(client)

	var selfJSON C.GChatByteSlice
	var valErr C.GChatByteSlice
	st = C.gchat_validate_session(client, &selfJSON, &valErr)
	if st != C.GCHAT_OK {
		return nil, statusError(st, valErr)
	}
	resBytes := takeByteSlice(selfJSON)
	if len(resBytes) == 0 {
		return nil, errors.New("gchat_validate_session returned empty output")
	}

	var out ValidatedSession
	if err := json.Unmarshal(resBytes, &out); err != nil {
		return nil, fmt.Errorf("unmarshal validated session: %w", err)
	}
	return &out, nil
}
