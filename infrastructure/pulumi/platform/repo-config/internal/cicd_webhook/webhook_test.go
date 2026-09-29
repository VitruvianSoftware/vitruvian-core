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
	"testing"

	"github.com/pulumi/pulumi-github/sdk/v6/go/github"
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
