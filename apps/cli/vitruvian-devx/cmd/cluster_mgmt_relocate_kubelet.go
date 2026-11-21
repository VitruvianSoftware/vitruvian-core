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

package cmd

import (
	"errors"
	"fmt"
	"time"

	"github.com/spf13/cobra"

	"github.com/VitruvianSoftware/vitruvian-devx/internal/multinode/cluster"
	"github.com/VitruvianSoftware/vitruvian-devx/internal/multinode/config"
	"github.com/VitruvianSoftware/vitruvian-devx/internal/multinode/provider"
)

func newClusterRelocateKubeletCmd(configFile *string) *cobra.Command {
	var (
		host         string
		apply        bool
		drainTimeout time.Duration
		readyTimeout time.Duration
		timeout      time.Duration
	)

	cmd := &cobra.Command{
		Use:   "relocate-kubelet --host <node>",
		Short: "One-time switch of a native node's kubelet back to /var/lib/kubelet",
		Long: `relocate-kubelet fixes a native node that was set up with an older devx and has
a custom dataDir. That setup moved the kubelet to <dataDir>/kubelet, which breaks
every CSI volume (NFS, for one) on the node: the CSI node plugin only mounts the
standard /var/lib/kubelet and never sees the paths the kubelet hands it.

The fix keeps the files where they are. The kubelet goes back to the standard
/var/lib/kubelet, which becomes a bind mount of <dataDir>/kubelet (a systemd
mount unit, ordered before k3s), so pod volumes and ephemeral storage stay on the
big volume and the node still reports that volume's size.

By default it is a dry run: it makes read-only checks over ssh and prints each
step with the exact command it would run, the pods the drain would evict, and a
diff of the config change. Pass --apply to do it: cordon and drain the node, take
an etcd snapshot (control-plane nodes), re-check quorum and etcd health, stop k3s,
remove the root-dir argument from /etc/rancher/k3s/config.yaml (and the systemd
ExecStart if it is there), set up the bind mount, start k3s, wait for Ready, check
that the mount is shared and the NFS CSI node plugin is up, run a short pod pinned
to the node that mounts a throwaway NFS volume, and only then uncordon. If a step
fails it says what state the node is in and how to recover; a node that is down or
failed a check stays cordoned on purpose, and the message says so.

It is safe to re-run: if an earlier run stopped half way (after the config edit,
inside the mount step, or after the mount with k3s down), running it again picks up
where the node is. It refuses when the node has no dataDir, when its kubelet is not
at <dataDir>/kubelet, when /var/lib/kubelet is a populated directory or any other
unexpected thing, when the nfs storage class could let the check delete a shared
folder, and when it is already switched and healthy. All of that is checked before
anything is changed. The command only uncordons a node it cordoned itself. For a
control-plane node it also refuses unless every other control-plane node (found by
label, not from the config) is Ready, a majority would remain, and another
server's etcd answers ready (this shows a quorum is reachable, not that every
member is in sync).
Run it on one node at a time. New nodes need none of this: devx now installs them
with the bind mount from the start.`,
		Args: cobra.NoArgs,
		RunE: func(c *cobra.Command, _ []string) error {
			if host == "" {
				return fmt.Errorf("--host is required")
			}
			cfg, err := config.Load(*configFile)
			if err != nil {
				return fmt.Errorf("loading config: %w", err)
			}
			ctx := contextWithSignal(c.Context(), timeout)
			err = cluster.RelocateKubelet(ctx, cfg, host, cluster.RelocateKubeletOptions{
				// The global --dry-run always wins over --apply.
				Apply:        apply && !DryRun,
				DrainTimeout: drainTimeout,
				ReadyTimeout: readyTimeout,
				Out:          c.OutOrStdout(),
			})
			if errors.Is(err, provider.ErrKubeletAlreadyRelocated) {
				// Idempotent: a node that is already switched is a success.
				_, _ = fmt.Fprintln(c.OutOrStdout(), err)
				_, _ = fmt.Fprintln(c.OutOrStdout(), "Nothing to do.")
				return nil
			}
			return err
		},
	}

	cmd.Flags().StringVar(&host, "host", "", "name of the node (host in the cluster config) to switch")
	cmd.Flags().BoolVar(&apply, "apply", false, "make the change (default: dry run that only prints the plan)")
	cmd.Flags().DurationVar(&drainTimeout, "drain-timeout", 5*time.Minute, "how long to wait for the node to drain")
	cmd.Flags().DurationVar(&readyTimeout, "ready-timeout", 5*time.Minute, "how long to wait for the node to be Ready again")
	cmd.Flags().DurationVar(&timeout, "timeout", 30*time.Minute, "maximum time for the entire operation")

	return cmd
}
