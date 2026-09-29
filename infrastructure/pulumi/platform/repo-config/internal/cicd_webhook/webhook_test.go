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

package cicd_webhook

import (
	"strings"
	"testing"

	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// The webhook must stay narrow: one repo, two event types, JSON, TLS on,
// pointed at the CI collector's public path (spec §3.4).
func TestArgs(t *testing.T) {
	a := Args(pulumi.String("s3cret"))

	if got := a.Repository.(pulumi.String); got != "vitruvian-core" {
		t.Fatalf("Repository = %q, want vitruvian-core", got)
	}
	events := a.Events.(pulumi.StringArray)
	if len(events) != 2 || events[0] != pulumi.String("workflow_job") || events[1] != pulumi.String("workflow_run") {
		t.Fatalf("Events = %v, want [workflow_job workflow_run]", events)
	}
	if a.Active.(pulumi.Bool) != true {
		t.Fatal("webhook must be active")
	}
	c := a.Configuration.(*github.RepositoryWebhookConfigurationArgs)
	if c.Url.(pulumi.String) != "https://github-otel.ipv1337.dev/events" {
		t.Fatalf("Url = %q", c.Url)
	}
	if c.ContentType.(pulumi.String) != "json" {
		t.Fatalf("ContentType = %q, want json", c.ContentType)
	}
	if c.InsecureSsl.(pulumi.Bool) != false {
		t.Fatal("InsecureSsl must be false")
	}
	if c.Secret == nil {
		t.Fatal("Secret must be set")
	}
}

type mocks struct{ created *[]string }

func (m mocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	*m.created = append(*m.created, args.TypeToken)
	return args.Name + "_id", args.Inputs, nil
}

func (mocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}

func runManage(t *testing.T) ([]string, error) {
	t.Helper()
	var created []string
	err := pulumi.RunErr(Manage, pulumi.WithMocks("repo-config", "dev", mocks{&created}))
	return created, err
}

// A run without the secret must FAIL, not skip: an undeclared resource is a
// Pulumi delete, so skipping would remove the live webhook on the next `up`.
func TestManage_FailsWithoutSecret(t *testing.T) {
	t.Setenv(secretEnv, "")
	created, err := runManage(t)
	if err == nil {
		t.Fatal("Manage without the secret must return an error, got nil")
	}
	if !strings.Contains(err.Error(), secretEnv) {
		t.Fatalf("error should name %s so the operator knows what to set, got: %v", secretEnv, err)
	}
	if len(created) != 0 {
		t.Fatalf("no resource may be declared without the secret, got %v", created)
	}
}

func TestManage_DeclaresWebhookWithSecret(t *testing.T) {
	t.Setenv(secretEnv, "s3cret")
	created, err := runManage(t)
	if err != nil {
		t.Fatalf("Manage: %v", err)
	}
	if len(created) != 1 || created[0] != "github:index/repositoryWebhook:RepositoryWebhook" {
		t.Fatalf("want exactly one RepositoryWebhook, got %v", created)
	}
}
