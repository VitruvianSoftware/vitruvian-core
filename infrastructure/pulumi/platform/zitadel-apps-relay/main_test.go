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
	specs, err := clientSpecs("", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(specs) != 5 {
		t.Fatalf("want connector, claude, their two -v2 siblings and the dashboard, got %d clients", len(specs))
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
	specs, err := clientSpecs(" https://chatgpt.com/connector/oauth/abc123 ,https://chatgpt.com/connector_platform_oauth_redirect", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(specs) != 7 || specs[2].Key != "chatgpt" {
		t.Fatalf("want a chatgpt client third, got %+v", specs)
	}
	want := []string{"https://chatgpt.com/connector/oauth/abc123", "https://chatgpt.com/connector_platform_oauth_redirect"}
	if !reflect.DeepEqual(specs[2].RedirectURIs, want) {
		t.Errorf("got %v want %v", specs[2].RedirectURIs, want)
	}
}

func TestClientSpecsGemini(t *testing.T) {
	cb := "https://oauth-redirect.googleusercontent.com/r/user_bound_custom-mcp-b3b5dc02c05b1a90254344dc"
	specs, err := clientSpecs("", " "+cb+" ")
	if err != nil {
		t.Fatal(err)
	}
	if len(specs) != 7 || specs[2].Key != "gemini" {
		t.Fatalf("want a gemini client third, got %+v", specs)
	}
	g := specs[2]
	if !reflect.DeepEqual(g.RedirectURIs, []string{cb}) {
		t.Errorf("got %v want %v", g.RedirectURIs, []string{cb})
	}
	// Gemini's connector form sends a client secret; the others must stay public.
	if g.AuthMethod != authPost {
		t.Errorf("gemini must be confidential (POST), got %s", g.AuthMethod)
	}
	for _, s := range specs[:2] {
		if s.AuthMethod != authNone {
			t.Errorf("%s must stay public, got %s", s.Key, s.AuthMethod)
		}
	}
	if _, err := clientSpecs("", "https://chatgpt.com/connector/oauth/x"); err == nil {
		t.Error("a gemini callback on another host must be refused")
	}
}

func TestGeminiCallbackPathIsPinned(t *testing.T) {
	bad := []string{
		"https://oauth-redirect.googleusercontent.com/",                                       // no path
		"https://oauth-redirect.googleusercontent.com/r/",                                     // another redirector entry
		"https://oauth-redirect.googleusercontent.com/r/someone-elses-app",                    // another Google client
		"https://oauth-redirect.googleusercontent.com/r/user_bound_custom-mcp-",               // prefix only, no id
		"https://oauth-redirect.googleusercontent.com/r/user_bound_custom-mcp-x/../evil",      // path traversal
		"https://oauth-redirect.googleusercontent.com/r/user_bound_custom-mcp-x%2F..%2Fevil",  // encoded traversal
		"https://oauth-redirect.googleusercontent.com/r/user_bound_custom-mcp-x/y",            // extra segment
		`https://oauth-redirect.googleusercontent.com/r/user_bound_custom-mcp-x\..\..\other`,  // backslash walk
		"https://oauth-redirect.googleusercontent.com/r/user_bound_custom-mcp-x%5C..%5Cother", // encoded backslash
		"https://oauth-redirect.googleusercontent.com/r/user_bound_custom-mcp-..",             // dot segment id
		"https://oauth-redirect.googleusercontent.com/r/user_bound_custom-mcp-abc?",           // empty query
		"https://oauth-redirect.googleusercontent.com/r/user_bound_custom-mcp-abc#",           // empty fragment
		"HTTPS://oauth-redirect.googleusercontent.com/r/user_bound_custom-mcp-abc",            // upper-case scheme
	}
	for _, raw := range bad {
		if _, err := clientSpecs("", raw); err == nil {
			t.Errorf("%q: want refusal, got none", raw)
		}
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
		"https://chatgpt.com/",                                   // right host, wrong path
		"https://chatgpt.com/share/abc",                          // right host, wrong path
		"https://user@chatgpt.com/connector/oauth/x",             // userinfo
		"https://chatgpt.com/connectorevil",                      // look-alike of /connector
		"https://chatgpt.com/connector/oauth/",                   // prefix only, no id
		"https://chatgpt.com/connector/oauth/a/b",                // extra segment
		"https://chatgpt.com/connector/oauth/abc?",               // empty query
		"https://chatgpt.com/connector/oauth/abc#",               // empty fragment
		"HTTPS://chatgpt.com/connector/oauth/abc",                // upper-case scheme
		"https://chatgpt.com/connector/oauth/..",                 // dot-dot id
		"https://chatgpt.com/connector/oauth/.",                  // dot id
		`https://chatgpt.com/connector/oauth/x\..\..\share`,      // backslash walk
		"https://chatgpt.com/connector_platform_oauth_redirectx", // not the exact path
	}
	for _, raw := range bad {
		if _, err := parseRedirectURIs(raw, chatgptCallbackHost, chatgptCallbackPaths); err == nil {
			t.Errorf("%q: want refusal, got none", raw)
		}
	}
	if got, err := parseRedirectURIs(" , ", chatgptCallbackHost, chatgptCallbackPaths); err != nil || len(got) != 0 {
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

func TestEmptyPathRuleMatchesNothing(t *testing.T) {
	for _, p := range []string{"/abc", "abc", "/"} {
		if (pathRule{}).matches(p) {
			t.Errorf("empty rule matched %q", p)
		}
	}
}

func TestDashboardRedirectIsPinned(t *testing.T) {
	const want = "https://relay.vitruviansoftware.dev/auth/callback"
	if dashboardCallback != want {
		t.Fatalf("dashboard callback is %q, want %q", dashboardCallback, want)
	}
	// The one allowed callback passes the same check every other client uses.
	got, err := parseRedirectURIs(dashboardCallback, relayHost, dashboardCallbackPaths)
	if err != nil || !reflect.DeepEqual(got, []string{want}) {
		t.Fatalf("the pinned callback must pass: got %v %v", got, err)
	}
	// Anything else, even on the relay's own host, must be refused.
	bad := []string{
		"http://relay.vitruviansoftware.dev/auth/callback",               // not https
		"https://relay.vitruviansoftware.dev/",                           // the post-logout page, not a callback
		"https://relay.vitruviansoftware.dev/auth/callback/x",            // extra segment
		"https://relay.vitruviansoftware.dev/auth/callbackx",             // look-alike path
		"https://relay.vitruviansoftware.dev/auth/callback?next=/admin",  // query
		"https://relay.vitruviansoftware.dev/auth/callback#",             // empty fragment
		"https://relay.vitruviansoftware.dev/mcp",                        // another relay path
		"https://relay-spike.ipv1337.dev/auth/callback",                  // the old spike host
		"https://relay.vitruviansoftware.dev.evil.example/auth/callback", // look-alike host
		"HTTPS://relay.vitruviansoftware.dev/auth/callback",              // upper-case scheme
		`https://relay.vitruviansoftware.dev/auth/callback\..\evil`,      // backslash walk
	}
	for _, raw := range bad {
		if _, err := parseRedirectURIs(raw, relayHost, dashboardCallbackPaths); err == nil {
			t.Errorf("%q: want refusal, got none", raw)
		}
	}

	// The dashboard client uses exactly that callback and nothing wider.
	specs, err := clientSpecs("", "")
	if err != nil {
		t.Fatal(err)
	}
	var d *clientSpec
	for i := range specs {
		if specs[i].Key == "dashboard" {
			d = &specs[i]
		}
	}
	if d == nil {
		t.Fatal("no dashboard client")
	}
	if !reflect.DeepEqual(d.RedirectURIs, []string{want}) {
		t.Errorf("dashboard redirects: got %v", d.RedirectURIs)
	}
	if !reflect.DeepEqual(d.PostLogoutURIs, []string{"https://relay.vitruviansoftware.dev/"}) {
		t.Errorf("dashboard post-logout: got %v", d.PostLogoutURIs)
	}
	if d.AppType != "OIDC_APP_TYPE_WEB" || d.AuthMethod != authNone {
		t.Errorf("dashboard must be a public web client with PKCE: %+v", d)
	}
	if !reflect.DeepEqual(d.GrantTypes, []string{"OIDC_GRANT_TYPE_AUTHORIZATION_CODE"}) {
		t.Errorf("dashboard must use the authorization code grant only: %v", d.GrantTypes)
	}
	if !d.AccessTokenRoleAssertion {
		t.Error("dashboard access tokens must carry the role claim the relay checks")
	}
}

func TestRoleClaimNamesTheProject(t *testing.T) {
	if got, want := roleClaim("378818267051999999"), "urn:zitadel:iam:org:project:378818267051999999:roles"; got != want {
		t.Errorf("got %q want %q", got, want)
	}
}

func TestInviteUserIDsRefuseDuplicates(t *testing.T) {
	james := []string{"1"}
	if _, err := resolveInviteUserIDs(james, "2, 1"); err == nil {
		t.Error("an id in both grantUserIds and inviteUserIds must be refused")
	}
	if _, err := resolveInviteUserIDs(james, "2,3, 2"); err == nil {
		t.Error("an id twice in inviteUserIds must be refused")
	}
	if _, err := resolveGrantUserIDs(true, "1, 1", "relay-user"); err == nil {
		t.Error("an id twice in grantUserIds must be refused")
	}
	got, err := resolveInviteUserIDs(james, " 2 , 3 ")
	if err != nil || !reflect.DeepEqual(got, []string{"2", "3"}) {
		t.Errorf("got %v %v", got, err)
	}
	if got, err := resolveInviteUserIDs(james, ""); err != nil || len(got) != 0 {
		t.Errorf("empty: got %v %v", got, err)
	}
}

func TestInviteUserIDsMayBeEmpty(t *testing.T) {
	// No invitees yet is a normal state: only James holds the role.
	if got, err := resolveGrantUserIDs(false, "", "relay-user"); err != nil || len(got) != 0 {
		t.Errorf("got %v %v", got, err)
	}
	got, err := resolveGrantUserIDs(false, " 1, 2 ,,3", "relay-user")
	if err != nil || !reflect.DeepEqual(got, []string{"1", "2", "3"}) {
		t.Errorf("got %v %v", got, err)
	}
}

// The live clients can't be changed to assert roles without being replaced, so
// each has a -v2 sibling that does. Old ones must stay exactly as they were.
func TestRoleAssertingSiblings(t *testing.T) {
	cb := "https://oauth-redirect.googleusercontent.com/r/user_bound_custom-mcp-abc"
	specs, err := clientSpecs("https://chatgpt.com/connector/oauth/abc", cb)
	if err != nil {
		t.Fatal(err)
	}
	byKey := map[string]clientSpec{}
	for _, sp := range specs {
		if _, dup := byKey[sp.Key]; dup {
			t.Fatalf("duplicate client key %q", sp.Key)
		}
		byKey[sp.Key] = sp
	}
	for _, base := range []string{"connector", "claude", "chatgpt", "gemini"} {
		old, ok := byKey[base]
		if !ok {
			t.Fatalf("missing live client %q", base)
		}
		v2, ok := byKey[base+"-v2"]
		if !ok {
			t.Fatalf("missing role-asserting sibling %q", base+"-v2")
		}
		if old.AccessTokenRoleAssertion {
			t.Errorf("%s: the live client must stay as it is (role assertion off)", base)
		}
		if len(old.PostLogoutURIs) != 0 {
			t.Errorf("%s: the live client must have no post-logout URIs, got %v", base, old.PostLogoutURIs)
		}
		if old.ExportKey != base || v2.ExportKey != base+"V2" {
			t.Errorf("%s: export keys %q / %q", base, old.ExportKey, v2.ExportKey)
		}
		if !v2.AccessTokenRoleAssertion {
			t.Errorf("%s-v2 must assert roles in access tokens", base)
		}
		if v2.AppType != old.AppType || v2.AuthMethod != old.AuthMethod ||
			!reflect.DeepEqual(v2.GrantTypes, old.GrantTypes) ||
			!reflect.DeepEqual(v2.RedirectURIs, old.RedirectURIs) ||
			!reflect.DeepEqual(v2.PostLogoutURIs, old.PostLogoutURIs) {
			t.Errorf("%s-v2 differs from %s beyond role assertion:\n old %+v\n v2  %+v", base, base, old, v2)
		}
	}
	if !byKey["dashboard"].AccessTokenRoleAssertion {
		t.Error("dashboard must assert roles")
	}
	// Every client except the old four asserts roles; the old four do not.
	for _, sp := range specs {
		isOld := sp.Key == "connector" || sp.Key == "claude" || sp.Key == "chatgpt" || sp.Key == "gemini"
		if sp.AccessTokenRoleAssertion == isOld {
			t.Errorf("%s: roleAssertion=%v is wrong", sp.Key, sp.AccessTokenRoleAssertion)
		}
	}
}
