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

// Package revision derives tabula's Cloud Run revision name from an image
// digest and the rendered service environment.
//
// It is deliberately its ONE home for that logic. The app stack (../main.go)
// names the revision it deploys with Name(); the deploy preflight
// (../cmd/revname) recomputes the SAME name to decide whether the live service
// already serves the desired state. If those two ever computed the name
// differently, the preflight would either never skip (harmless) or skip a real
// deploy (an outage-class under-trigger) — so they must share this code, not
// reimplement it.
package revision

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"sort"
	"strings"
)

// SecretPrefix namespaces tabula's Secret Manager reads so co-tenant OSS apps
// in a shared project cannot collide, and is injected as SECRET_PREFIX so the
// running container reads its own secrets. It is part of the rendered env, so
// changing it changes the revision hash.
const SecretPrefix = "TABULA_"

const digestMarker = "@sha256:"

// ShortDigest extracts the 8-hex revision-name fragment from an image digest
// ref (`<image>@sha256:<hex>`). A digest is not itself a legal Cloud Run
// revision-name component, so the short prefix stands in for it.
func ShortDigest(imageDigest string) (string, error) {
	i := strings.LastIndex(imageDigest, digestMarker)
	if i < 0 || len(imageDigest) < i+len(digestMarker)+8 {
		return "", fmt.Errorf("imageDigest %q is not a digest ref (want <image>@sha256:<hex>)", imageDigest)
	}
	return imageDigest[i+len(digestMarker) : i+len(digestMarker)+8], nil
}

// EnvMap builds the plain (non-secret) environment for the service.
//
// apiURL and postMessageOrigin are both PUBLIC values (a URL and a
// chrome-extension:// origin), and both are load-bearing for the extension
// login flow. Empty means ABSENT rather than empty-string, so an unconfigured
// env is a missing key instead of an empty one — and hashes differently.
func EnvMap(project, apiURL, postMessageOrigin string) map[string]string {
	env := map[string]string{
		"NODE_ENV":             "production",
		"GOOGLE_CLOUD_PROJECT": project,
		"SECRET_PREFIX":        SecretPrefix,
	}
	if apiURL != "" {
		env["API_URL"] = apiURL
	}
	if postMessageOrigin != "" {
		env["AUTH_POSTMESSAGE_ORIGIN"] = postMessageOrigin
	}
	return env
}

// Name derives the Cloud Run revision name from the image digest AND the
// rendered environment.
//
// A revision is immutable and its name identifies image + config TOGETHER. The
// digest alone is not enough: build-once/promote-by-digest means one image is
// deployed to three envs, and any config change to that image produces
// different revision CONTENT under an identical name, which the API rejects:
//
//	Error 409: Revision named 'tabula-api-development-1c144786' with different
//	configuration already exists.
//
// Hashing the env in keeps the name deterministic — the deploy runs `pulumi up`
// twice (deploy, then promote) and must address the SAME revision both times,
// as must a rerun after a transient failure — while still changing whenever the
// content does. Keys are sorted so Go's randomized map iteration cannot make the
// name unstable, and the separators are bytes that cannot occur in an env name,
// so {AB=C} and {A=BC} cannot collide.
func Name(serviceName, shortDigest string, env map[string]string) string {
	keys := make([]string, 0, len(env))
	for k := range env {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	h := sha256.New()
	for _, k := range keys {
		h.Write([]byte(k))
		h.Write([]byte{0})
		h.Write([]byte(env[k]))
		h.Write([]byte{0})
	}
	// 6 hex chars: this only has to distinguish the handful of configs a single
	// image is ever deployed with, and the name has a 63-char budget it shares
	// with the service-name prefix.
	configHash := hex.EncodeToString(h.Sum(nil))[:6]

	return fmt.Sprintf("%s-%s-%s", serviceName, shortDigest, configHash)
}
