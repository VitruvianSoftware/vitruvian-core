// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

/*
#include "gchat.h"
#include <stdlib.h>

extern void goGChatEventCallback(uintptr_t userdata, int32_t event_kind, uint8_t* payload_ptr, size_t payload_len);

static inline void gchatEventCallbackTrampoline(uintptr_t userdata, int32_t event_kind, const uint8_t* payload_ptr, size_t payload_len) {
	goGChatEventCallback(userdata, event_kind, (uint8_t*)payload_ptr, payload_len);
}

static inline GChatStatus call_gchat_start_stream(GChatClient* client, uintptr_t userdata, GChatByteSlice* out_err) {
	return gchat_start_stream(client, gchatEventCallbackTrampoline, userdata, out_err);
}
*/
import "C"

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"runtime/cgo"
	"sync"
	"time"
	"unsafe"
)

const (
	EventKindEventProto  int32 = 1
	EventKindAuthExpired int32 = 2
	EventKindResync      int32 = 3
	EventKindConnected   int32 = 4
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

// ConvertedInboundText is returned by gchat_annotations_to_html.
type ConvertedInboundText struct {
	Body             string   `json:"body"`
	FormattedBody    string   `json:"formatted_body"`
	Mentions         []string `json:"mentions"`
	MentionAll       bool     `json:"mention_all"`
	Text             string   `json:"text"`
	HTML             string   `json:"html"`
	AnnotationsCount int      `json:"annotations_count"`
}

// FFIClient wraps a live *C.GChatClient handle.
type FFIClient struct {
	mu           sync.Mutex
	ptr          *C.GChatClient
	streamHandle cgo.Handle
	hasStream    bool
}

// NewFFIClient creates a new Rust GChatClient handle from cfg.
func NewFFIClient(cfg SessionConfig) (*FFIClient, error) {
	raw, err := json.Marshal(cfg)
	if err != nil {
		return nil, fmt.Errorf("marshal session config: %w", err)
	}
	if len(raw) == 0 {
		return nil, errors.New("empty session config")
	}
	var ptr *C.GChatClient
	var newErr C.GChatByteSlice
	st := C.gchat_client_new(
		(*C.uint8_t)(unsafe.Pointer(&raw[0])),
		C.size_t(len(raw)),
		&ptr,
		&newErr,
	)
	if st != C.GCHAT_OK {
		return nil, statusError(st, newErr)
	}
	return &FFIClient{ptr: ptr}, nil
}

// Close stops any active stream and frees the underlying Rust GChatClient handle.
func (c *FFIClient) Close() {
	if c == nil {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.ptr == nil {
		return
	}
	if c.hasStream {
		C.gchat_stop_stream(c.ptr)
		c.streamHandle.Delete()
		c.hasStream = false
	}
	C.gchat_client_free(c.ptr)
	c.ptr = nil
}

// RPCCall invokes /u/0/api/<endpoint>?alt=proto through the Rust FFI client.
func (c *FFIClient) RPCCall(endpoint string, reqProto []byte) ([]byte, error) {
	if c == nil {
		return nil, errors.New("nil gchat ffi client")
	}
	c.mu.Lock()
	ptr := c.ptr
	c.mu.Unlock()
	if ptr == nil {
		return nil, errors.New("closed gchat ffi client")
	}

	cEndpoint := C.CString(endpoint)
	defer C.free(unsafe.Pointer(cEndpoint))

	var reqPtr *C.uint8_t
	if len(reqProto) > 0 {
		reqPtr = (*C.uint8_t)(unsafe.Pointer(&reqProto[0]))
	}
	var respOut C.GChatByteSlice
	var errOut C.GChatByteSlice
	st := C.gchat_rpc_call(
		ptr,
		cEndpoint,
		C.size_t(len(endpoint)),
		reqPtr,
		C.size_t(len(reqProto)),
		&respOut,
		&errOut,
	)
	if st != C.GCHAT_OK {
		return nil, statusError(st, errOut)
	}
	return takeByteSlice(respOut), nil
}

//export goGChatEventCallback
func goGChatEventCallback(userdata C.uintptr_t, eventKind C.int32_t, payloadPtr *C.uint8_t, payloadLen C.size_t) {
	if userdata == 0 {
		return
	}
	h := cgo.Handle(userdata)
	cb, ok := h.Value().(func(int32, []byte))
	if !ok || cb == nil {
		return
	}
	var data []byte
	if payloadPtr != nil && payloadLen > 0 {
		data = C.GoBytes(unsafe.Pointer(payloadPtr), C.int(payloadLen))
	}
	cb(int32(eventKind), data)
}

// StartStream starts the WebChannel stream on the Rust FFI client.
func (c *FFIClient) StartStream(cb func(eventKind int32, payload []byte)) error {
	if c == nil {
		return errors.New("nil gchat ffi client")
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.ptr == nil {
		return errors.New("closed gchat ffi client")
	}
	if c.hasStream {
		C.gchat_stop_stream(c.ptr)
		c.streamHandle.Delete()
		c.hasStream = false
	}
	h := cgo.NewHandle(cb)
	var errOut C.GChatByteSlice
	st := C.call_gchat_start_stream(c.ptr, C.uintptr_t(h), &errOut)
	if st != C.GCHAT_OK {
		h.Delete()
		return statusError(st, errOut)
	}
	c.streamHandle = h
	c.hasStream = true
	return nil
}

// UseManualClock configures the underlying Rust GChatClient to use a deterministic manual clock for tests.
func (c *FFIClient) UseManualClock(fixedJitter float64) {
	if c == nil {
		return
	}
	c.mu.Lock()
	ptr := c.ptr
	c.mu.Unlock()
	if ptr != nil {
		C.gchat_use_manual_clock(ptr, C.double(fixedJitter))
	}
}

// AdvanceManualClock advances the underlying Rust manual clock by delta and returns the remaining active sleeper count.
func (c *FFIClient) AdvanceManualClock(delta time.Duration) int {
	if c == nil {
		return 0
	}
	c.mu.Lock()
	ptr := c.ptr
	c.mu.Unlock()
	if ptr == nil {
		return 0
	}
	return int(C.gchat_advance_manual_clock(ptr, C.uint64_t(delta.Milliseconds())))
}

// AnnotationsToHTML converts a serialized googlechat.Message protobuf into Matrix plain text + HTML.
func AnnotationsToHTML(messageProto []byte) (*ConvertedInboundText, error) {
	var ptr *C.uint8_t
	if len(messageProto) > 0 {
		ptr = (*C.uint8_t)(unsafe.Pointer(&messageProto[0]))
	}
	var renderOut C.GChatByteSlice
	var renderErr C.GChatByteSlice
	st := C.gchat_annotations_to_html(
		ptr,
		C.size_t(len(messageProto)),
		&renderOut,
		&renderErr,
	)
	if st != C.GCHAT_OK {
		return nil, statusError(st, renderErr)
	}
	renderedJSON := takeByteSlice(renderOut)
	var out ConvertedInboundText
	if err := json.Unmarshal(renderedJSON, &out); err != nil {
		return nil, fmt.Errorf("unmarshal annotations_to_html output: %w", err)
	}
	return &out, nil
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

// HTMLToAnnotations converts Matrix HTML (or plain text if formattedBody is empty) into Google Chat plain text and serialized Annotation protobuf slices.
func HTMLToAnnotations(plainBody, formattedBody string, allowMentionAll bool) (plainText string, annotations [][]byte, err error) {
	reqObj := struct {
		PlainBody       string `json:"plain_body,omitempty"`
		FormattedBody   string `json:"formatted_body,omitempty"`
		AllowMentionAll bool   `json:"allow_mention_all"`
	}{
		PlainBody:       plainBody,
		FormattedBody:   formattedBody,
		AllowMentionAll: allowMentionAll,
	}
	inputJSON, err := json.Marshal(reqObj)
	if err != nil {
		return "", nil, fmt.Errorf("marshal html_to_annotations input: %w", err)
	}
	var htmlOut C.GChatByteSlice
	var errOut C.GChatByteSlice
	st := C.gchat_html_to_annotations(
		(*C.uint8_t)(unsafe.Pointer(&inputJSON[0])),
		C.size_t(len(inputJSON)),
		&htmlOut,
		&errOut,
	)
	if st != C.GCHAT_OK {
		return "", nil, statusError(st, errOut)
	}
	encodedJSON := takeByteSlice(htmlOut)
	var parsed struct {
		Text                   string   `json:"text"`
		MessageProtoBase64     string   `json:"message_proto_base64"`
		AnnotationsProtoBase64 []string `json:"annotations_proto_base64"`
	}
	if err := json.Unmarshal(encodedJSON, &parsed); err != nil {
		return "", nil, fmt.Errorf("unmarshal html_to_annotations output: %w", err)
	}
	for _, b64 := range parsed.AnnotationsProtoBase64 {
		raw, err := base64.StdEncoding.DecodeString(b64)
		if err != nil {
			return "", nil, fmt.Errorf("decode annotation base64: %w", err)
		}
		annotations = append(annotations, raw)
	}
	return parsed.Text, annotations, nil
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

	step2, err := AnnotationsToHTML(protoBytes)
	if err != nil {
		return err
	}
	if (step2.HTML != "<strong>Hello</strong> World" && step2.HTML != "<b>Hello</b> World") || step2.AnnotationsCount != 1 {
		return fmt.Errorf("unexpected round-trip annotation output: %+v", step2)
	}
	return nil
}

// ValidateSession validates cookies against /u/0/mole/world and /u/0/api/get_self_user_status.
func ValidateSession(cfg SessionConfig) (*ValidatedSession, error) {
	c, err := NewFFIClient(cfg)
	if err != nil {
		return nil, err
	}
	defer c.Close()

	var selfJSON C.GChatByteSlice
	var valErr C.GChatByteSlice
	st := C.gchat_validate_session(c.ptr, &selfJSON, &valErr)
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
