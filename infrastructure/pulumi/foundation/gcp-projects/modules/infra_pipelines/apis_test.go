/*
Copyright (c) 2026 VitruvianSoftware

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

package infra_pipelines

import "testing"

// The shared infra-pipeline project hosts the CROSS-ENVIRONMENT singletons of
// every stage-5 app: the Artifact Registry the image is built once into, the
// build identity that pushes it, and the account-level credentials for external
// SaaS dependencies. An API this project's tenants rely on but which is absent
// from ActivateApis fails LATE — not at project creation, but months later when
// some app's stack first tries to use it, as a 403 "<API> has not been used in
// project <id> before or it is disabled" in the middle of an apply.
//
// That is not hypothetical: declaring Secret Manager containers for tabula's
// Neon/Upstash management credentials failed exactly that way, because
// secretmanager was never in this list. The per-env oss floating projects have
// it (they hold each app's runtime secrets); this project never did.
//
// Each entry below is paired with the concrete capability that needs it, so a
// future edit has to argue with a reason rather than delete an opaque string.
func TestActivateApisCoversStage5Needs(t *testing.T) {
	required := map[string]string{
		"artifactregistry.googleapis.com":     "build-once/promote-by-digest: the shared registry the app image is pushed to",
		"iamcredentials.googleapis.com":       "a WIF-federated CI job mints an access token by impersonating the per-app build SA homed here",
		"secretmanager.googleapis.com":        "account-level management credentials for apps' external SaaS deps (e.g. Neon/Upstash), which are cross-env and so belong here rather than in a per-env project",
		"iam.googleapis.com":                  "the per-app build service accounts themselves",
		"cloudresourcemanager.googleapis.com": "project-level IAM the pipeline identities are granted",
	}

	have := make(map[string]bool, len(infraPipelineActivateApis))
	for _, api := range infraPipelineActivateApis {
		if have[api] {
			t.Errorf("%s is listed twice", api)
		}
		have[api] = true
	}

	for api, why := range required {
		if !have[api] {
			t.Errorf("ActivateApis is missing %s\n  needed for: %s", api, why)
		}
	}
}
