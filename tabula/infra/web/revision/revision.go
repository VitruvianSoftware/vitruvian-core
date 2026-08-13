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

// Package revision derives tabula-web's Cloud Run revision name from an image
// digest and the rendered service environment.
package revision

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"sort"
	"strings"
)

const digestMarker = "@sha256:"

// ShortDigest extracts the 8-hex revision-name fragment from an image digest ref.
func ShortDigest(imageDigest string) (string, error) {
	i := strings.LastIndex(imageDigest, digestMarker)
	if i < 0 || len(imageDigest) < i+len(digestMarker)+8 {
		return "", fmt.Errorf("imageDigest %q is not a digest ref (want <image>@sha256:<hex>)", imageDigest)
	}
	return imageDigest[i+len(digestMarker) : i+len(digestMarker)+8], nil
}

// Name derives the Cloud Run revision name from the image digest AND the rendered environment.
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
	configHash := hex.EncodeToString(h.Sum(nil))[:6]

	return fmt.Sprintf("%s-%s-%s", serviceName, shortDigest, configHash)
}
