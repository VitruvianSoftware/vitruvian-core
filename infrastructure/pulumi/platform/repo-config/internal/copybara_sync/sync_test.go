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
	"slices"
	"sync"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

type seen struct {
	typeToken     string
	inputs        resource.PropertyMap
	importID      string
	protect       bool
	ignoreChanges []string
}

// Pulumi registers resources concurrently, so the mock serialises its own
// bookkeeping (as internal/site_domain's test does).
type mocks struct {
	got map[string]seen
	mu  *sync.Mutex
}

func (m mocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	s := seen{typeToken: args.TypeToken, inputs: args.Inputs}
	if rpc := args.RegisterRPC; rpc != nil {
		s.importID = rpc.GetImportId()
		s.protect = rpc.GetProtect()
		s.ignoreChanges = rpc.GetIgnoreChanges()
	}
	m.mu.Lock()
	m.got[args.Name] = s
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

// The shipped apps' mirrors (the Vitruvian app, Courier, HomeSpeaker,
// Vitruvian Remote and the Desk Companion firmware) are public repositories
// this package makes, each with the export's write key on it, the key's
// private half in the monorepo, a read-only main, and no App key or tap key:
// they are source mirrors that release nothing.
func TestTheShippedAppMirrorsAreMadePublicWithTheirExportKeys(t *testing.T) {
	got := run(t)
	for _, mirror := range []struct{ repo, secret string }{
		{"vitruvian", "VITRUVIAN_SYNC_SSH_KEY"},
		{"courier", "COURIER_SYNC_SSH_KEY"},
		{"home-speaker", "HOME_SPEAKER_SYNC_SSH_KEY"},
		{"vitruvian-remote", "VITRUVIAN_REMOTE_SYNC_SSH_KEY"},
		{"esp32-desk-companion", "ESP32_DESK_COMPANION_SYNC_SSH_KEY"},
	} {
		t.Run(mirror.repo, func(t *testing.T) {
			if r := got[mirror.repo]; r.typeToken != "github:index/repository:Repository" {
				t.Fatalf("%s is %q, want a github repository", mirror.repo, r.typeToken)
			}
			if v := text(t, got, mirror.repo, "visibility"); v != "public" {
				t.Errorf("visibility is %q, want public: the mirror is the app's published source", v)
			}
			if v := text(t, got, mirror.repo+"-standalone-deploy-key", "repository"); v != mirror.repo {
				t.Errorf("the export key is on %q, want %s", v, mirror.repo)
			}
			if v := text(t, got, mirror.repo+"-sync-ssh-key-secret", "secretName"); v != mirror.secret {
				t.Errorf("the export secret is %q, want %s", v, mirror.secret)
			}
			if v := text(t, got, mirror.repo+"-sync-ssh-key-secret", "repository"); v != "vitruvian-core" {
				t.Errorf("the export secret is in %q, want vitruvian-core", v)
			}
			if _, ok := got[mirror.repo+"-mirror-readonly"]; !ok {
				t.Error("the mirror's main is not made read-only")
			}
			if _, ok := got[mirror.repo+"-dispatch-app-private-key-secret"]; ok {
				t.Error("an export-only mirror must not hold the App's key")
			}
			if _, ok := got[mirror.repo+"-homebrew-tap-key"]; ok {
				t.Error("a source mirror must hold no key to the tap")
			}
		})
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

func flag(t *testing.T, got map[string]seen, resourceName, field string) bool {
	t.Helper()
	r, ok := got[resourceName]
	if !ok {
		t.Fatalf("no resource %q was declared", resourceName)
	}
	v, ok := r.inputs[resource.PropertyKey(field)]
	if !ok {
		t.Fatalf("%s has no %s", resourceName, field)
	}
	if !v.IsBool() {
		t.Fatalf("%s.%s is %v, not bool", resourceName, field, v)
	}
	return v.BoolValue()
}

// The nexus-agent mirror is imported into Pulumi state with its exact live
// GitHub settings and protected against replacement so the follow-up PR can
// rename it to vitruvian-code in place without losing releases, stars or tags.
func TestNexusAgentMirrorIsAdoptedProtectedWithLiveSettings(t *testing.T) {
	got := run(t)
	r, ok := got["nexus-agent"]
	if !ok {
		t.Fatal("nexus-agent repository resource was not declared")
	}
	if r.typeToken != "github:index/repository:Repository" {
		t.Fatalf("nexus-agent is %q, want github:index/repository:Repository", r.typeToken)
	}
	if r.importID != "nexus-agent" {
		t.Errorf("nexus-agent importID = %q, want %q", r.importID, "nexus-agent")
	}
	if !r.protect {
		t.Error("nexus-agent must be protected so a later rename cannot replace or delete it")
	}
	for _, mutable := range []string{"name", "description", "topics"} {
		if slices.Contains(r.ignoreChanges, mutable) {
			t.Errorf("nexus-agent ignoreChanges contains %q; PR 2 must be able to update it in place", mutable)
		}
	}
	if _, hasAutoInit := r.inputs["autoInit"]; hasAutoInit {
		t.Error("nexus-agent must not set autoInit on an imported repository")
	}
	if v := text(t, got, "nexus-agent", "name"); v != "nexus-agent" {
		t.Errorf("name = %q, want nexus-agent (rename belongs to PR 2)", v)
	}
	if v := text(t, got, "nexus-agent", "visibility"); v != "public" {
		t.Errorf("visibility = %q, want public", v)
	}
	if v := text(t, got, "nexus-agent", "squashMergeCommitTitle"); v != "COMMIT_OR_PR_TITLE" {
		t.Errorf("squashMergeCommitTitle = %q, want COMMIT_OR_PR_TITLE", v)
	}
	if v := text(t, got, "nexus-agent", "squashMergeCommitMessage"); v != "COMMIT_MESSAGES" {
		t.Errorf("squashMergeCommitMessage = %q, want COMMIT_MESSAGES", v)
	}
	for _, want := range []struct {
		field string
		val   bool
	}{
		{"deleteBranchOnMerge", true},
		{"hasIssues", true},
		{"hasProjects", true},
		{"hasWiki", false},
		{"hasDiscussions", false},
		{"allowSquashMerge", true},
		{"allowMergeCommit", false},
		{"allowRebaseMerge", false},
		{"allowAutoMerge", false},
		{"allowUpdateBranch", false},
		{"allowForking", true},
		{"isTemplate", false},
		{"archived", false},
		{"webCommitSignoffRequired", false},
	} {
		if gotVal := flag(t, got, "nexus-agent", want.field); gotVal != want.val {
			t.Errorf("nexus-agent.%s = %v, want %v", want.field, gotVal, want.val)
		}
	}
	topicsVal, ok := r.inputs["topics"]
	if !ok || !topicsVal.IsArray() {
		t.Fatalf("nexus-agent.topics = %v, want array", topicsVal)
	}
	var topics []string
	for _, elem := range topicsVal.ArrayValue() {
		topics = append(topics, elem.StringValue())
	}
	wantTopics := []string{"ai-agent", "cli", "gemini", "llm", "macos", "menubar-app", "ollama", "telegram-bot"}
	if !slices.Equal(topics, wantTopics) {
		t.Errorf("nexus-agent.topics = %v, want %v", topics, wantTopics)
	}

	// Existing sync auth resources stay untouched on nexus-agent in PR 1.
	if v := text(t, got, "nexus-agent-standalone-deploy-key", "repository"); v != "nexus-agent" {
		t.Errorf("deploy key repository = %q, want nexus-agent", v)
	}
	if v := text(t, got, "nexus-agent-sync-ssh-key-secret", "secretName"); v != "NEXUS_AGENT_SYNC_SSH_KEY" {
		t.Errorf("sync ssh secret = %q, want NEXUS_AGENT_SYNC_SSH_KEY", v)
	}
	if v := text(t, got, "nexus-agent-dispatch-app-id-secret", "secretName"); v != "NEXUS_AGENT_DISPATCH_APP_ID" {
		t.Errorf("dispatch app id secret = %q, want NEXUS_AGENT_DISPATCH_APP_ID", v)
	}
	if _, ok := got["nexus-agent-mirror-readonly"]; ok {
		t.Error("nexus-agent is two-way today and must not declare one-way branch protection in PR 1")
	}
}

func TestRepositoryDeclarationMatchesCreateOrAdoptMode(t *testing.T) {
	got := run(t)
	for _, p := range syncedProjects {
		if p.CreateRepo && p.Adopt != nil {
			t.Fatalf("%s sets both CreateRepo and Adopt", p.Name)
		}
		r, declared := got[p.StandaloneRepo]
		switch {
		case p.CreateRepo:
			if !declared || r.typeToken != "github:index/repository:Repository" {
				t.Errorf("%s: CreateRepo=true must declare github:index/repository:Repository", p.Name)
			}
			if r.importID != "" {
				t.Errorf("%s: CreateRepo=true must not set importID (%q)", p.Name, r.importID)
			}
		case p.Adopt != nil:
			if !declared || r.typeToken != "github:index/repository:Repository" {
				t.Errorf("%s: Adopt!=nil must declare github:index/repository:Repository", p.Name)
			}
			if r.importID != p.StandaloneRepo {
				t.Errorf("%s: importID = %q, want %q", p.Name, r.importID, p.StandaloneRepo)
			}
			if !r.protect {
				t.Errorf("%s: adopted repository must be protected", p.Name)
			}
		default:
			if declared && r.typeToken == "github:index/repository:Repository" {
				t.Errorf("%s: declared unexpected Repository resource without CreateRepo or Adopt", p.Name)
			}
		}
	}
}
