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

package cluster

import (
	"bytes"
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/VitruvianSoftware/vitruvian-devx/internal/multinode/config"
	"github.com/VitruvianSoftware/vitruvian-devx/internal/multinode/provider"
)

func relocateCfg() *config.Config {
	return &config.Config{Nodes: []config.NodeConfig{
		{Host: "nuc9", Role: "server", Kind: "native"},
		{Host: "nuc10", Role: "server", Kind: "native"},
		{Host: "nuc9i5", Role: "server", Kind: "native", DataDir: "/home/k3s"},
		{Host: "nuc-w", Role: "agent", Kind: "native", DataDir: "/home/k3s"},
		{Host: "mac1", Role: "agent", VM: config.VMConfig{CPUs: 2, Memory: "4GiB", Disk: "20GiB"}},
	}}
}

func TestPickControlNode_PrefersInitServerThatIsNotTheTarget(t *testing.T) {
	cfg := relocateCfg()
	ctl, others := pickControlNode(cfg, "nuc9i5")
	if ctl.Host != "nuc9" {
		t.Errorf("control = %s, want the init server nuc9", ctl.Host)
	}
	if strings.Join(others, ",") != "nuc9,nuc10" {
		t.Errorf("other servers = %v", others)
	}
	// Targeting the init server itself must not run kubectl on it.
	ctl, others = pickControlNode(cfg, "nuc9")
	if ctl.Host != "nuc10" || strings.Join(others, ",") != "nuc10,nuc9i5" {
		t.Errorf("target nuc9: control=%s others=%v", ctl.Host, others)
	}
	// An agent target: kubectl on the init server, and no server is "other than" it.
	ctl, _ = pickControlNode(cfg, "nuc-w")
	if ctl.Host != "nuc9" {
		t.Errorf("agent target: control=%s", ctl.Host)
	}
}

func TestPickControlNode_SingleServerClusterUsesTheTarget(t *testing.T) {
	cfg := &config.Config{Nodes: []config.NodeConfig{{Host: "only", Role: "server", Kind: "native", DataDir: "/d"}}}
	ctl, others := pickControlNode(cfg, "only")
	if ctl.Host != "only" || len(others) != 0 {
		t.Errorf("control=%s others=%v", ctl.Host, others)
	}
}

func TestRelocateKubelet_RefusesBeforeTouchingAnything(t *testing.T) {
	cfg := relocateCfg()
	ctx := context.Background()
	var out bytes.Buffer

	err := RelocateKubelet(ctx, cfg, "ghost", RelocateKubeletOptions{Out: &out})
	if err == nil || !strings.Contains(err.Error(), "not found in config") {
		t.Errorf("unknown node: %v", err)
	}
	err = RelocateKubelet(ctx, cfg, "mac1", RelocateKubeletOptions{Out: &out})
	if !errors.Is(err, provider.ErrNotNative) {
		t.Errorf("lima node must be refused as non-native: %v", err)
	}
	// A native node without dataDir is refused before any ssh call (the inspection
	// would otherwise try to reach the host).
	err = RelocateKubelet(ctx, cfg, "nuc9", RelocateKubeletOptions{Out: &out})
	if !errors.Is(err, provider.ErrRelocateNoDataDir) {
		t.Errorf("no dataDir must be refused: %v", err)
	}
	if out.Len() != 0 {
		t.Errorf("a refusal prints nothing but the error; got %q", out.String())
	}
}
