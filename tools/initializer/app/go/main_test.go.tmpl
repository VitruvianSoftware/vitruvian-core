package main

import (
	"os"
	"strings"
	"testing"
)

func TestRunWritesStartupLine(t *testing.T) {
	f, err := os.CreateTemp(t.TempDir(), "out")
	if err != nil {
		t.Fatalf("CreateTemp: %v", err)
	}
	if err := run(f); err != nil {
		t.Fatalf("run: %v", err)
	}
	b, err := os.ReadFile(f.Name())
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	if !strings.Contains(string(b), "started") {
		t.Errorf("run() wrote %q, want it to contain %q", string(b), "started")
	}
}
