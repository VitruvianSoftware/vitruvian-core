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

import "testing"

func TestClusterAttributeCondition(t *testing.T) {
	t.Run("one subject", func(t *testing.T) {
		got := clusterAttributeCondition([]string{"system:serviceaccount:backstage:backstage"})
		want := `assertion.sub == "system:serviceaccount:backstage:backstage"`
		if got != want {
			t.Fatalf("got %q, want %q", got, want)
		}
	})

	t.Run("several subjects are OR-ed", func(t *testing.T) {
		got := clusterAttributeCondition([]string{
			"system:serviceaccount:backstage:backstage",
			"system:serviceaccount:grafana:grafana",
		})
		want := `assertion.sub == "system:serviceaccount:backstage:backstage" || ` +
			`assertion.sub == "system:serviceaccount:grafana:grafana"`
		if got != want {
			t.Fatalf("got %q, want %q", got, want)
		}
	})

	// The whole point of %q: a quote in the subject must not close the CEL
	// string literal and let the rest be parsed as an expression. If this ever
	// regresses to plain concatenation, the result below becomes a condition
	// that is TRUE for every subject.
	t.Run("a quote in the subject cannot escape the literal", func(t *testing.T) {
		got := clusterAttributeCondition([]string{`a" || true || "b`})
		want := `assertion.sub == "a\" || true || \"b"`
		if got != want {
			t.Fatalf("got %q, want %q", got, want)
		}
	})

	// An empty list must not yield an always-true (or empty) condition. The
	// caller refuses to build the provider at all in that case; this pins the
	// helper's own behaviour so the two cannot drift into both permitting it.
	t.Run("no subjects yields an empty condition, never a permissive one", func(t *testing.T) {
		if got := clusterAttributeCondition(nil); got != "" {
			t.Fatalf("got %q, want empty", got)
		}
	})
}

func TestSanitizeSubject(t *testing.T) {
	// Colons and slashes are not valid in a Pulumi URN component, and the
	// subject is the only thing distinguishing these bindings from each other --
	// so two different subjects must not sanitize to the same name.
	a := sanitizeSubject("system:serviceaccount:backstage:backstage")
	b := sanitizeSubject("system:serviceaccount:grafana:grafana")
	if a == b {
		t.Fatalf("distinct subjects collided: %q", a)
	}
	if want := "system-serviceaccount-backstage-backstage"; a != want {
		t.Fatalf("got %q, want %q", a, want)
	}
}
