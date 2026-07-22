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
