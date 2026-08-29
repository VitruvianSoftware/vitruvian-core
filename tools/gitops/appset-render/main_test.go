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

// The #414 regression, verbatim in shape: the prometheus values block is a Go
// raw-string passthrough so that literal Prometheus templating ({{ $labels }})
// survives goTemplate. A stray backtick INSIDE that block closes the raw string
// early and the whole appset stops rendering.
func TestStrayBacktickIsCaught(t *testing.T) {
	src := "spec:\n  template:\n    values: |\n      {{`\n      annotations:\n        summary: pod `oops` restarting\n      `}}\n"
	err := checkSource("prometheus", src)
	if err == nil {
		t.Fatal("a stray backtick inside the raw-string passthrough must fail to parse (#414)")
	}
	if got := classify(err); got == "" {
		t.Fatal("classify returned no guidance")
	}
}

// The same block WITHOUT the stray backtick is the correct form and must pass,
// or the gate would forbid the very pattern the repo requires.
func TestValidRawStringPassthroughPasses(t *testing.T) {
	src := "spec:\n  template:\n    values: |\n      {{`\n      annotations:\n        summary: {{ $labels.namespace }} restarting\n      `}}\n"
	if err := checkSource("prometheus", src); err != nil {
		t.Fatalf("valid raw-string passthrough must parse, got: %v", err)
	}
}

// The other documented hazard (CONTRIBUTING.md:419): literal {{ }} that was
// never wrapped, so goTemplate tries to evaluate Prometheus' own variables.
func TestUnwrappedLiteralBracesAreCaught(t *testing.T) {
	src := "spec:\n  template:\n    values: |\n      summary: {{ $labels.namespace }}\n"
	if err := checkSource("prometheus", src); err == nil {
		t.Fatal("an unwrapped literal {{ $labels }} must fail to parse")
	}
}

// The generator params every appset here templates must keep working.
func TestGeneratorParamsParse(t *testing.T) {
	src := "spec:\n  template:\n    spec:\n      destination:\n        server: '{{.server}}'\n        name: '{{.name}}'\n"
	if err := checkSource("clusters", src); err != nil {
		t.Fatalf("clusters-generator params must parse, got: %v", err)
	}
}

// sprig is available to the real controller, so a live appset using it must not
// be reported as broken here. Without the stub FuncMap this is a false positive
// on a required gate -- worse than having no gate.
func TestSprigFunctionsResolve(t *testing.T) {
	for _, fn := range []string{
		"{{ .values | nindent 12 }}",
		"{{ .name | quote }}",
		"{{ .cfg | toYaml | indent 4 }}",
		"{{ default \"x\" .missing }}",
	} {
		if err := checkSource("sprig", "spec:\n  template:\n    v: "+fn+"\n"); err != nil {
			t.Errorf("sprig expression %q must parse, got: %v", fn, err)
		}
	}
}

// An unclosed action is a plain syntax error and must be fatal.
func TestUnclosedActionIsCaught(t *testing.T) {
	if err := checkSource("broken", "spec:\n  template:\n    v: {{ .server \n"); err == nil {
		t.Fatal("an unclosed {{ action must fail to parse")
	}
}

// classify must map each documented hazard to its own guidance, so the CI log
// tells an operator what to DO, not merely that a template failed.
func TestClassifyDistinguishesHazards(t *testing.T) {
	backtick := checkSource("b", "v: |\n  {{`\n  a `x`\n  `}}\n")
	if backtick == nil {
		t.Fatal("setup: expected a backtick parse error")
	}
	if got := classify(backtick); !contains(got, "#414") {
		t.Errorf("backtick guidance should cite #414, got: %s", got)
	}

	braces := checkSource("c", "v: {{ $labels.ns }}\n")
	if braces == nil {
		t.Fatal("setup: expected an undefined-variable parse error")
	}
	if got := classify(braces); !contains(got, "raw-string passthrough") {
		t.Errorf("literal-brace guidance should suggest the passthrough, got: %s", got)
	}
}

func contains(hay, needle string) bool {
	return len(hay) >= len(needle) && func() bool {
		for i := 0; i+len(needle) <= len(hay); i++ {
			if hay[i:i+len(needle)] == needle {
				return true
			}
		}
		return false
	}()
}
