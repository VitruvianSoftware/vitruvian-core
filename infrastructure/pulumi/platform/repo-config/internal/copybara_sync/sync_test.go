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

package copybara_sync

import (
	"sync"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type seen struct {
	typeToken string
	inputs    resource.PropertyMap
}

// Pulumi registers resources concurrently, so the mock serialises its own
// bookkeeping (as internal/site_domain's test does).
type mocks struct {
	got map[string]seen
	mu  *sync.Mutex
}

func (m mocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	m.mu.Lock()
	m.got[args.Name] = seen{typeToken: args.TypeToken, inputs: args.Inputs}
	m.mu.Unlock()
	return args.Name + "_id", args.Inputs, nil
}

func (mocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

// run declares every synced project against the mocks and returns what was
// declared, by resource name. The App credentials are stand-ins: nothing is
// sent anywhere.
func run(t *testing.T) map[string]seen {
	t.Helper()
	t.Setenv("SYNC_APP_ID", "1")
	t.Setenv("SYNC_APP_PRIVATE_KEY", "not-a-real-key")
	got := map[string]seen{}
	if err := pulumi.RunErr(ManageSyncAuth, pulumi.WithMocks("repo-config", "dev", mocks{got, &sync.Mutex{}})); err != nil {
		t.Fatalf("ManageSyncAuth: %v", err)
	}
	return got
}

func text(t *testing.T, got map[string]seen, resourceName, field string) string {
	t.Helper()
	r, ok := got[resourceName]
	if !ok {
		t.Fatalf("no resource %q was declared", resourceName)
	}
	v, ok := r.inputs[resource.PropertyKey(field)]
	if !ok {
		t.Fatalf("%s has no %s", resourceName, field)
	}
	if v.IsSecret() {
		v = v.SecretValue().Element
	}
	if !v.IsString() {
		t.Fatalf("%s.%s is %v, not text", resourceName, field, v)
	}
	return v.StringValue()
}

// The SDK's mirror is a public repository this package makes, with the
// export's write key on it and the key's private half in the monorepo.
func TestTheSDKMirrorIsMadePublicWithItsExportKey(t *testing.T) {
	got := run(t)
	if r := got["vitruvian-sdk"]; r.typeToken != "github:index/repository:Repository" {
		t.Fatalf("vitruvian-sdk is %q, want a github repository", r.typeToken)
	}
	if v := text(t, got, "vitruvian-sdk", "visibility"); v != "public" {
		t.Errorf("visibility is %q, want public: SwiftPM and Homebrew fetch from it with no account", v)
	}
	if v := text(t, got, "vitruvian-sdk-standalone-deploy-key", "repository"); v != "vitruvian-sdk" {
		t.Errorf("the export key is on %q, want vitruvian-sdk", v)
	}
	if v := text(t, got, "vitruvian-sdk-sync-ssh-key-secret", "secretName"); v != "VITRUVIAN_SDK_SYNC_SSH_KEY" {
		t.Errorf("the export secret is %q, want VITRUVIAN_SDK_SYNC_SSH_KEY", v)
	}
	if v := text(t, got, "vitruvian-sdk-sync-ssh-key-secret", "repository"); v != "vitruvian-core" {
		t.Errorf("the export secret is in %q, want vitruvian-core", v)
	}
	if _, ok := got["vitruvian-sdk-mirror-readonly"]; !ok {
		t.Error("the mirror's main is not made read-only")
	}
	if _, ok := got["vitruvian-sdk-dispatch-app-private-key-secret"]; ok {
		t.Error("an export-only mirror must not hold the App's key")
	}
}

// The GitHub tool's mirror is a public repository this package makes, with
// the export's write key on it and the key's private half in the monorepo,
// and no key to the tap: its release is a zip the catalog pins.
func TestTheGitHubToolMirrorIsMadePublicWithItsExportKeyAndNoTapKey(t *testing.T) {
	got := run(t)
	if r := got["vitruvian-tool-github"]; r.typeToken != "github:index/repository:Repository" {
		t.Fatalf("vitruvian-tool-github is %q, want a github repository", r.typeToken)
	}
	if v := text(t, got, "vitruvian-tool-github", "visibility"); v != "public" {
		t.Errorf("visibility is %q, want public: the app downloads the release's zip with no account", v)
	}
	if v := text(t, got, "vitruvian-tool-github-standalone-deploy-key", "repository"); v != "vitruvian-tool-github" {
		t.Errorf("the export key is on %q, want vitruvian-tool-github", v)
	}
	if v := text(t, got, "vitruvian-tool-github-sync-ssh-key-secret", "secretName"); v != "VITRUVIAN_TOOL_GITHUB_SYNC_SSH_KEY" {
		t.Errorf("the export secret is %q, want VITRUVIAN_TOOL_GITHUB_SYNC_SSH_KEY", v)
	}
	if _, ok := got["vitruvian-tool-github-mirror-readonly"]; !ok {
		t.Error("the mirror's main is not made read-only")
	}
	if _, ok := got["vitruvian-tool-github-dispatch-app-private-key-secret"]; ok {
		t.Error("an export-only mirror must not hold the App's key")
	}
	if _, ok := got["vitruvian-tool-github-homebrew-tap-key"]; ok {
		t.Error("the GitHub tool's mirror must hold no key to the tap: it publishes a zip, not a formula")
	}
}

// The mirror's release.yml writes its formula with a key that can write the
// tap and nothing else.
func TestTheSDKMirrorHoldsAWriteKeyToTheTapOnly(t *testing.T) {
	got := run(t)
	if r := got["vitruvian-sdk-homebrew-tap-key"]; r.typeToken != "tls:index/privateKey:PrivateKey" {
		t.Fatalf("vitruvian-sdk-homebrew-tap-key is %q, want a tls private key", r.typeToken)
	}
	if v := text(t, got, "vitruvian-sdk-homebrew-tap-deploy-key", "repository"); v != "homebrew-tap" {
		t.Errorf("the tap key is on %q, want homebrew-tap", v)
	}
	if r := got["vitruvian-sdk-homebrew-tap-deploy-key"]; r.inputs["readOnly"].BoolValue() {
		t.Error("the tap key is read-only: the release could not push the formula")
	}
	if v := text(t, got, "vitruvian-sdk-homebrew-tap-key-secret", "repository"); v != "vitruvian-sdk" {
		t.Errorf("the tap key's private half is in %q, want vitruvian-sdk", v)
	}
	if v := text(t, got, "vitruvian-sdk-homebrew-tap-key-secret", "secretName"); v != "HOMEBREW_TAP_DEPLOY_KEY" {
		t.Errorf("the tap key's secret is %q, want HOMEBREW_TAP_DEPLOY_KEY", v)
	}
}

// A key to the tap goes only to a one-way mirror: its workflows reach it
// only through the monorepo's export, so nothing outside review can use it.
func TestOnlyOneWayMirrorsHoldATapKey(t *testing.T) {
	got := run(t)
	for _, p := range syncedProjects {
		_, declared := got[p.Name+"-homebrew-tap-key-secret"]
		if declared != p.HomebrewTapKey {
			t.Errorf("%s: tap key declared %v, HomebrewTapKey %v", p.Name, declared, p.HomebrewTapKey)
		}
		if p.HomebrewTapKey && !p.OneWay {
			t.Errorf("%s holds a tap key but is not a one-way mirror", p.Name)
		}
	}
}
