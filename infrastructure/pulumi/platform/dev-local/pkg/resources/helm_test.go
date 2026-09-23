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

package resources

import (
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// A secret config value must reach the Helm values as the same Output: the
// old default branch stringified anything it didn't recognise, which would
// have turned the Argo CD admin hash into "{0xc000...}" and dropped its
// secret marking.
func TestConvertToPulumiValuePassesInputsThrough(t *testing.T) {
	secret := pulumi.ToSecret(pulumi.String("$2a$10$hash")).(pulumi.StringOutput)
	got := convertToPulumiValue(map[string]interface{}{"argocdServerAdminPassword": secret})
	m, ok := got.(pulumi.Map)
	if !ok {
		t.Fatalf("got %T, want pulumi.Map", got)
	}
	if _, ok := m["argocdServerAdminPassword"].(pulumi.StringOutput); !ok {
		t.Fatalf("secret became %T, want the original pulumi.StringOutput", m["argocdServerAdminPassword"])
	}
	if _, ok := convertToPulumiValue("plain").(pulumi.String); !ok {
		t.Fatal("plain strings must still become pulumi.String")
	}
}
