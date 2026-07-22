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

func TestAppBuildReaderGrantsParsing(t *testing.T) {
	got := appBuildReaderGrants("oauth-user-inspector=prj-c-bu1-infra-pipeline-4b48/us-west1/oauth-user-inspector")
	if len(got) != 1 {
		t.Fatalf("want 1 grant, got %d", len(got))
	}
	g := got[0]
	if g.App != "oauth-user-inspector" || g.RepositoryProject != "prj-c-bu1-infra-pipeline-4b48" ||
		g.Region != "us-west1" || g.RepositoryID != "oauth-user-inspector" {
		t.Errorf("bad parse: %+v", g)
	}
	if len(appBuildReaderGrants("")) != 0 {
		t.Error("empty input must yield no grants")
	}
	if len(appBuildReaderGrants("malformed")) != 0 {
		t.Error("entry without = must be skipped")
	}
	if len(appBuildReaderGrants("a=too/few")) != 0 {
		t.Error("entry without 3 path parts must be skipped")
	}
}
