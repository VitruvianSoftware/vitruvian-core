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

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestShimArgsPutsStrictFlagsLastAndDropsKeyHeaders(t *testing.T) {
	startup := []string{"--bazelrc=/main/user.bazelrc"}
	strict := []string{"--config=remote", "--spawn_strategy=remote"}
	got, cmd, targets := shimArgs([]string{
		"test", "--config=remote", "--remote_header=x-buildbuddy-api-key=SECRET",
		"--bes_header=x-buildbuddy-api-key=SECRET", "--spawn_strategy=local", "//a:t", "//b/...",
	}, startup, strict)
	want := []string{"--bazelrc=/main/user.bazelrc", "test", "--config=remote", "--spawn_strategy=local", "//a:t", "//b/...", "--spawn_strategy=remote"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("args:\n got %q\nwant %q", got, want)
	}
	if cmd != "test" || !reflect.DeepEqual(targets, []string{"//a:t", "//b/..."}) {
		t.Fatalf("command %q targets %q", cmd, targets)
	}
	for _, a := range got {
		if strings.Contains(a, "SECRET") {
			t.Fatalf("a key header survived: %q", a)
		}
	}
}

func TestShimArgsAddsRemoteConfigWhenMissing(t *testing.T) {
	got, _, _ := shimArgs([]string{"test", "//a:t"}, nil, []string{"--config=remote", "--S"})
	want := []string{"test", "//a:t", "--config=remote", "--S"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestShimArgsKeepsTargetsAfterDashesLast(t *testing.T) {
	got, _, targets := shimArgs([]string{"build", "--keep_going", "--", "-//a:excluded", "//b:x"}, nil, []string{"--S"})
	want := []string{"build", "--keep_going", "--S", "--", "-//a:excluded", "//b:x"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %q want %q", got, want)
	}
	if !reflect.DeepEqual(targets, []string{"-//a:excluded", "//b:x"}) {
		t.Fatalf("targets %q", targets)
	}
}

func TestShimArgsLeavesQueryAlone(t *testing.T) {
	got, cmd, _ := shimArgs([]string{"query", "attr(tags, pipeline, //...)", "--output=label"}, []string{"--bazelrc=x"}, []string{"--S"})
	want := []string{"--bazelrc=x", "query", "attr(tags, pipeline, //...)", "--output=label"}
	if cmd != "query" || !reflect.DeepEqual(got, want) {
		t.Fatalf("got %q (%s)", got, cmd)
	}
}

func TestShimArgsKeepsCallerStartupOptions(t *testing.T) {
	got, cmd, _ := shimArgs([]string{"--nohome_rc", "test", "//a:t"}, []string{"--bazelrc=x"}, []string{"--S"})
	want := []string{"--bazelrc=x", "--nohome_rc", "test", "//a:t", "--S"}
	if cmd != "test" || !reflect.DeepEqual(got, want) {
		t.Fatalf("got %q", got)
	}
}

func TestScanLineReadsLinkAndSummary(t *testing.T) {
	var inv invocation
	for _, l := range []string{
		"INFO: Invocation ID: 5a8aa3be",
		"\x1b[32mINFO: \x1b[0mStreaming build results to: https://app.buildbuddy.io/invocation/5a8aa3be-9a5d\r",
		"INFO: 12 processes: 3 remote cache hit, 5 internal, 4 remote.",
	} {
		scanLine(l, &inv)
	}
	if inv.URL != "https://app.buildbuddy.io/invocation/5a8aa3be-9a5d" {
		t.Fatalf("url %q", inv.URL)
	}
	if !inv.SawSummary || inv.Processes != "3 remote cache hit, 5 internal, 4 remote" {
		t.Fatalf("summary %v %q", inv.SawSummary, inv.Processes)
	}

	var zero invocation
	scanLine("INFO: 0 processes.", &zero)
	if !zero.SawSummary || zero.Processes != "" {
		t.Fatalf("zero summary %v %q", zero.SawSummary, zero.Processes)
	}
}

func TestCheckInvocation(t *testing.T) {
	ok := invocation{Lane: "build-test", Command: "test", URL: "https://app.buildbuddy.io/invocation/x", SawSummary: true}
	cases := []struct {
		name    string
		mut     func(*invocation)
		wantErr string
	}{
		{"remote only", func(i *invocation) { i.Processes = "2 remote, 6 internal, 1 remote cache hit" }, ""},
		{"nothing ran", func(i *invocation) { i.Processes = "" }, ""},
		{"build steps already in this output base", func(i *invocation) { i.Processes = "4 action cache hit, 1 remote" }, ""},
		{"ran on the Mac", func(i *invocation) { i.Processes = "1 darwin-sandbox, 2 remote" }, "on this machine"},
		{"local strategy", func(i *invocation) { i.Processes = "1 local" }, "on this machine"},
		{"persistent worker", func(i *invocation) { i.Processes = "3 worker" }, "on this machine"},
		{"laptop disk cache", func(i *invocation) { i.Processes = "1 disk cache hit" }, "on this machine"},
		{"failed", func(i *invocation) { i.Exit = 3 }, "failed with exit code 3"},
		{"no link", func(i *invocation) { i.URL = "" }, "no BuildBuddy link"},
		{"no summary", func(i *invocation) { i.SawSummary = false }, "did not report"},
		{"no test targets", func(i *invocation) { i.Exit, i.SawSummary = 4, false }, ""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			inv := ok
			c.mut(&inv)
			err := checkInvocation(inv)
			if c.wantErr == "" && err != nil {
				t.Fatalf("unexpected refusal: %v", err)
			}
			if c.wantErr != "" && (err == nil || !strings.Contains(err.Error(), c.wantErr)) {
				t.Fatalf("want refusal containing %q, got %v", c.wantErr, err)
			}
		})
	}
}

func TestReadInvocationsRoundTrip(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "log.jsonl")
	if invs, err := readInvocations(path); err != nil || invs != nil {
		t.Fatalf("missing log: %v %v", invs, err)
	}
	if err := os.WriteFile(path, []byte(`{"lane":"a","command":"test","targets":["//x"],"exit":0}`+"\n"+`{"lane":"b","command":"build"}`+"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	invs, err := readInvocations(path)
	if err != nil || len(invs) != 2 || invs[0].Targets[0] != "//x" || invs[1].Lane != "b" {
		t.Fatalf("got %+v %v", invs, err)
	}
	if err := os.WriteFile(path, []byte("{not json"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := readInvocations(path); err == nil {
		t.Fatal("a corrupt log must not read as an empty one")
	}
}
