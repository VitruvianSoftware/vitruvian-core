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

package main

import (
	"reflect"
	"testing"
)

func TestClientSpecsDefault(t *testing.T) {
	specs, err := clientSpecs("")
	if err != nil {
		t.Fatal(err)
	}
	if len(specs) != 2 {
		t.Fatalf("want connector and claude only, got %d clients", len(specs))
	}
	conn, claude := specs[0], specs[1]
	if conn.Key != "connector" || conn.AppType != "OIDC_APP_TYPE_NATIVE" || len(conn.RedirectURIs) != 0 {
		t.Errorf("connector spec wrong: %+v", conn)
	}
	if !reflect.DeepEqual(conn.GrantTypes, []string{"OIDC_GRANT_TYPE_DEVICE_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"}) {
		t.Errorf("connector must use the device flow: %v", conn.GrantTypes)
	}
	if claude.Key != "claude" || !reflect.DeepEqual(claude.RedirectURIs, []string{claudeCallback}) {
		t.Errorf("claude spec wrong: %+v", claude)
	}
	for _, s := range specs {
		for _, g := range s.GrantTypes {
			if g == "OIDC_GRANT_TYPE_IMPLICIT" {
				t.Errorf("%s: implicit grant must never be enabled", s.Key)
			}
		}
	}
}

func TestClientSpecsChatGPT(t *testing.T) {
	specs, err := clientSpecs(" https://chatgpt.com/connector/oauth/abc123 ,https://chatgpt.com/connector_platform_oauth_redirect")
	if err != nil {
		t.Fatal(err)
	}
	if len(specs) != 3 || specs[2].Key != "chatgpt" {
		t.Fatalf("want a chatgpt client third, got %+v", specs)
	}
	want := []string{"https://chatgpt.com/connector/oauth/abc123", "https://chatgpt.com/connector_platform_oauth_redirect"}
	if !reflect.DeepEqual(specs[2].RedirectURIs, want) {
		t.Errorf("got %v want %v", specs[2].RedirectURIs, want)
	}
}

func TestParseRedirectURIsRefusesWrongTargets(t *testing.T) {
	bad := []string{
		"http://chatgpt.com/connector/oauth/x",        // not https
		"https://chatgpt.com.evil.example/oauth",      // wrong host
		"https://evil.example/?r=https://chatgpt.com", // wrong host, query
		"https://chatgpt.com/connector/oauth/x?y=1",   // query
		"https://chatgpt.com/connector/oauth/x#frag",  // fragment
		"not a url at all",
	}
	for _, raw := range bad {
		if _, err := parseRedirectURIs(raw, "chatgpt.com"); err == nil {
			t.Errorf("%q: want refusal, got none", raw)
		}
	}
	if got, err := parseRedirectURIs(" , ", "chatgpt.com"); err != nil || len(got) != 0 {
		t.Errorf("separators only: want empty and no error, got %v %v", got, err)
	}
}

func TestParseBoolIsStrict(t *testing.T) {
	if _, err := parseBool("yes", "projectRoleCheck"); err == nil {
		t.Error(`"yes" must be refused, not read as false`)
	}
	if v, err := parseBool("true", "projectRoleCheck"); err != nil || !v {
		t.Errorf("true: got %v %v", v, err)
	}
	if v, err := parseBool("", "projectRoleCheck"); err != nil || v {
		t.Errorf("empty: got %v %v", v, err)
	}
}

func TestResolveGrantUserIDs(t *testing.T) {
	if _, err := resolveGrantUserIDs(true, " , ", "relay-user"); err == nil {
		t.Error("role check on with no real grant must be refused")
	}
	got, err := resolveGrantUserIDs(true, " 378818267051722263 ", "relay-user")
	if err != nil || !reflect.DeepEqual(got, []string{"378818267051722263"}) {
		t.Errorf("got %v %v", got, err)
	}
	if got, err := resolveGrantUserIDs(false, "", "relay-user"); err != nil || len(got) != 0 {
		t.Errorf("check off, no grants: got %v %v", got, err)
	}
}
