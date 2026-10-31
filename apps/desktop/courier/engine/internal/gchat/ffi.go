// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

package gchat

/*
#include "gchat.h"
#include <stdlib.h>
*/
import "C"

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"unsafe"
)

// ScopedCookie represents a single domain-scoped cookie for Google Chat.
type ScopedCookie struct {
	Name   string `json:"name"`
	Value  string `json:"value"`
	Domain string `json:"domain"`
	Path   string `json:"path"`
}

// SessionConfig is serialized to JSON for gchat_validate_session and gchat_client_new.
type SessionConfig struct {
	Cookies              []ScopedCookie    `json:"cookies,omitempty"`
	CookieMap            map[string]string `json:"cookie_map,omitempty"`
	UserAgent            string            `json:"user_agent,omitempty"`
	BaseURL              string            `json:"base_url,omitempty"`
	AllowLoopbackForTest bool              `json:"allow_loopback_for_test,omitempty"`
}

// ValidatedSession is returned by gchat_validate_session.
type ValidatedSession struct {
	GaiaID    string `json:"gaia_id"`
	Name      string `json:"name"`
	Email     string `json:"email"`
	AvatarURL string `json:"avatar_url"`
}

// LinkCheck verifies that libgchat_ffi.a is linked and callable via cgo.
func LinkCheck() error {
	emptyCfg := C.CString("{}")
	defer C.free(unsafe.Pointer(emptyCfg))

	var errPtr *C.char
	resPtr := C.gchat_validate_session(emptyCfg, &errPtr)
	if resPtr != nil {
		C.gchat_string_free(resPtr)
		return errors.New("expected gchat_validate_session(\"{}\") to return an error")
	}
	if errPtr == nil {
		return errors.New("expected gchat_validate_session(\"{}\") to populate err_out")
	}
	errMsg := C.GoString(errPtr)
	C.gchat_string_free(errPtr)
	if !strings.Contains(errMsg, "no cookies provided") {
		return fmt.Errorf("unexpected error from gchat_validate_session: %s", errMsg)
	}
	return nil
}

// ValidateSession validates cookies against /u/0/mole/world and /u/0/api/get_self_user_status.
func ValidateSession(cfg SessionConfig) (*ValidatedSession, error) {
	raw, err := json.Marshal(cfg)
	if err != nil {
		return nil, fmt.Errorf("marshal session config: %w", err)
	}
	cJSON := C.CString(string(raw))
	defer C.free(unsafe.Pointer(cJSON))

	var errPtr *C.char
	resPtr := C.gchat_validate_session(cJSON, &errPtr)
	if errPtr != nil {
		errMsg := C.GoString(errPtr)
		C.gchat_string_free(errPtr)
		if resPtr != nil {
			C.gchat_string_free(resPtr)
		}
		return nil, errors.New(errMsg)
	}
	if resPtr == nil {
		return nil, errors.New("gchat_validate_session returned nil without error")
	}
	resJSON := C.GoString(resPtr)
	C.gchat_string_free(resPtr)

	var out ValidatedSession
	if err := json.Unmarshal([]byte(resJSON), &out); err != nil {
		return nil, fmt.Errorf("unmarshal validated session: %w", err)
	}
	return &out, nil
}
