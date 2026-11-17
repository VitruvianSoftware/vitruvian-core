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

package filters

import (
	"slices"
	"strings"
	"testing"

	"github.com/VitruvianSoftware/vitruvian-core/infrastructure/pulumi/platform/sentry/internal/config"
)

func TestDesiredForProjects(t *testing.T) {
	got := DesiredForProjects([]config.ProjectConfig{
		{Slug: "vitruviansoftware-dev"},
		{Slug: "vitruvian-devx"},
	})
	if !slices.Contains(got["vitruviansoftware-dev"], "browser-extensions") {
		t.Errorf("expected browser-extensions for web project, got %v", got["vitruviansoftware-dev"])
	}
	if !slices.Contains(got["vitruvian-devx"], "web-crawlers") || slices.Contains(got["vitruvian-devx"], "browser-extensions") {
		t.Errorf("unexpected filters for CLI project: %v", got["vitruvian-devx"])
	}
}

func TestScriptDoesNotLeakToken(t *testing.T) {
	if strings.Contains(script, "set -x") || strings.Contains(script, "echo \"$token") {
		t.Error("script must never print the token")
	}
}
