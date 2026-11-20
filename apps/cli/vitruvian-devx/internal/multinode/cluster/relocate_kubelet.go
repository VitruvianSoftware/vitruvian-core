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
	"context"
	"fmt"
	"io"
	"time"

	"github.com/VitruvianSoftware/vitruvian-devx/internal/multinode/config"
	"github.com/VitruvianSoftware/vitruvian-devx/internal/multinode/provider"
)

// RelocateKubeletOptions configures RelocateKubelet.
type RelocateKubeletOptions struct {
	// Apply runs the plan; false only inspects and prints it.
	Apply        bool
	DrainTimeout time.Duration
	ReadyTimeout time.Duration
	Out          io.Writer
}

// pickControlNode chooses the node whose kubectl drives the switch: the init
// server if it is not the target, else any other server, else the target itself
// (a single-server cluster, whose API is briefly unavailable while it restarts).
// Which nodes make up the control plane is not taken from here: the command asks
// the cluster, by role label, right before it stops the node.
func pickControlNode(cfg *config.Config, target string) config.NodeConfig {
	servers := cfg.ServerNodes()
	for _, s := range servers {
		if s.Host != target {
			return s
		}
	}
	for _, n := range cfg.Nodes {
		if n.Host == target {
			return n
		}
	}
	return config.NodeConfig{}
}

// RelocateKubelet switches an existing native node with a custom dataDir from a
// relocated kubelet root-dir (<dataDir>/kubelet) to the standard /var/lib/kubelet,
// which becomes a bind mount of that directory. See
// provider.NativeProvider.RelocateKubelet for the steps. Without opts.Apply it
// only inspects the node and prints the plan.
func RelocateKubelet(ctx context.Context, cfg *config.Config, hostName string, opts RelocateKubeletOptions) error {
	var target *config.NodeConfig
	for i := range cfg.Nodes {
		if cfg.Nodes[i].Host == hostName {
			target = &cfg.Nodes[i]
			break
		}
	}
	if target == nil {
		return fmt.Errorf("node %q not found in config", hostName)
	}
	if target.GetKind() != "native" {
		return fmt.Errorf("[%s] %w (kind is %q); Lima nodes keep their kubelet inside the VM", hostName, provider.ErrNotNative, target.GetKind())
	}
	control := pickControlNode(cfg, hostName)
	if control.Host == "" {
		return fmt.Errorf("[%s] no control-plane node in the config to run kubectl on", hostName)
	}

	if opts.Apply {
		lock, err := acquireClusterLock()
		if err != nil {
			return err
		}
		defer lock.release()
	}

	return provider.NewNativeProvider(*target, cfg).RelocateKubelet(ctx, provider.RelocateOptions{
		Apply:        opts.Apply,
		Control:      provider.ControlRunner(control),
		ControlHost:  control.Host,
		DrainTimeout: opts.DrainTimeout,
		ReadyTimeout: opts.ReadyTimeout,
		Out:          opts.Out,
		Command:      "devx cluster relocate-kubelet --host " + hostName,
	})
}
