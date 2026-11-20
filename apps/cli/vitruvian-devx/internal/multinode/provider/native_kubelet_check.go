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

package provider

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"
)

// Read-side helpers and the checks `relocate-kubelet` runs against the cluster:
// node state, control-plane membership and etcd health (so a control-plane node is
// never taken down while quorum is at risk), and the NFS check that proves the
// kubelet change fixed what it was meant to fix.

// Names of the throwaway objects the NFS check creates. They are fixed so a run
// that was interrupted can be cleaned up by the next one, and so an operator can
// find them. Everything lives in one dedicated namespace and is deleted afterwards.
const (
	checkNamespace    = "devx-kubelet-check"
	checkPVC          = "kubelet-check-pvc"
	checkPod          = "kubelet-check"
	checkStorageClass = "nfs"
	checkImage        = "docker.io/library/busybox:1.37"
	checkToken        = "devx-kubelet-check-ok"
	// The csi-driver-nfs node plugin (a DaemonSet, label app=csi-nfs-node) and the
	// driver name it registers in each node's CSINode.
	csiNFSNodeSelector = "app=csi-nfs-node"
	csiNFSDriver       = "nfs.csi.k8s.io"
)

const readyColumns = `READY:.status.conditions[?(@.type=="Ready")].status`

// kubeNodeInfo is what the API says about one node.
type kubeNodeInfo struct {
	exists, ready, cordoned bool
}

func nodeStateCmd(host string) string {
	return "k3s kubectl get node " + host + " --no-headers -o 'custom-columns=NAME:.metadata.name," + readyColumns + ",CORDONED:.spec.unschedulable'"
}

func membersCmd(label string) string {
	return "k3s kubectl get nodes -l node-role.kubernetes.io/" + label + " --no-headers -o 'custom-columns=NAME:.metadata.name," + readyColumns + "'"
}

const etcdReadyCmd = "k3s kubectl get --raw /readyz/etcd"

func (p *NativeProvider) kubeNode(ctx context.Context, o RelocateOptions) (kubeNodeInfo, error) {
	out, err := o.Control(ctx, nodeStateCmd(p.spec.Host))
	if err != nil {
		if strings.Contains(err.Error(), "NotFound") || strings.Contains(out, "NotFound") {
			return kubeNodeInfo{}, nil
		}
		return kubeNodeInfo{}, fmt.Errorf("asking %s about node %s: %w", o.ControlHost, p.spec.Host, err)
	}
	f := strings.Fields(out)
	if len(f) < 2 {
		return kubeNodeInfo{}, nil
	}
	return kubeNodeInfo{exists: true, ready: f[1] == "True", cordoned: len(f) >= 3 && f[2] == "true"}, nil
}

// controlPlaneMembers lists the cluster's control-plane and etcd nodes from their
// role labels (not from the devx config, which can drift) with their Ready state.
func (p *NativeProvider) controlPlaneMembers(ctx context.Context, o RelocateOptions) (map[string]bool, error) {
	members := map[string]bool{}
	for _, label := range []string{"control-plane", "etcd"} {
		out, err := o.Control(ctx, membersCmd(label))
		if err != nil {
			return nil, fmt.Errorf("asking %s for the %s nodes: %w", o.ControlHost, label, err)
		}
		for _, l := range strings.Split(out, "\n") {
			if f := strings.Fields(l); len(f) >= 2 {
				// A node listed by either label that is not Ready counts as not Ready.
				if prev, seen := members[f[0]]; seen {
					members[f[0]] = prev && f[1] == "True"
				} else {
					members[f[0]] = f[1] == "True"
				}
			}
		}
	}
	return members, nil
}

// checkQuorum makes sure that stopping this node cannot cost the cluster its
// control plane: every other control-plane node (by label) is Ready, a majority
// would remain, and etcd answers healthy through another server. Agents are
// exempt. A single-server cluster has no quorum to protect (it is simply down
// while the node restarts) and passes the membership checks.
func (p *NativeProvider) checkQuorum(ctx context.Context, o RelocateOptions) error {
	if p.spec.Role != "server" {
		return nil
	}
	members, err := p.controlPlaneMembers(ctx, o)
	if err != nil {
		return err
	}
	var others []string
	for name := range members {
		if name != p.spec.Host {
			others = append(others, name)
		}
	}
	sort.Strings(others)
	for _, name := range others {
		if !members[name] {
			return fmt.Errorf("%w: control-plane node %q is not Ready; taking %s down as well could break etcd quorum", ErrQuorumRisk, name, p.spec.Host)
		}
	}
	total := len(others) + 1
	if total > 1 && len(others) < total/2+1 {
		return fmt.Errorf("%w: the cluster has %d control-plane nodes and stopping %s would leave %d, short of a majority", ErrQuorumRisk, total, p.spec.Host, len(others))
	}
	out, err := o.Control(ctx, etcdReadyCmd)
	if err != nil || strings.TrimSpace(out) != "ok" {
		return fmt.Errorf("%w: %s says etcd is not healthy (%q, err=%v)", ErrEtcdUnhealthy, o.ControlHost, strings.TrimSpace(out), err)
	}
	return nil
}

// ErrEtcdUnhealthy: etcd did not report healthy, so a control-plane node must not
// be stopped.
var ErrEtcdUnhealthy = errors.New("etcd is not healthy")

// --- the NFS check ---

func checkManifest(host string) string {
	return "apiVersion: v1\nkind: Namespace\nmetadata:\n  name: " + checkNamespace + "\n---\n" +
		"apiVersion: v1\nkind: PersistentVolumeClaim\nmetadata:\n  name: " + checkPVC + "\n  namespace: " + checkNamespace + "\n" +
		"spec:\n  accessModes: [ReadWriteMany]\n  storageClassName: " + checkStorageClass + "\n  resources:\n    requests:\n      storage: 10Mi\n---\n" +
		"apiVersion: v1\nkind: Pod\nmetadata:\n  name: " + checkPod + "\n  namespace: " + checkNamespace + "\n" +
		"spec:\n  nodeName: " + host + "\n  restartPolicy: Never\n  tolerations:\n  - operator: Exists\n  containers:\n  - name: check\n    image: " + checkImage + "\n" +
		"    command: [\"sh\", \"-c\", \"echo " + checkToken + " > /data/probe && cat /data/probe\"]\n" +
		"    volumeMounts:\n    - name: data\n      mountPath: /data\n  volumes:\n  - name: data\n    persistentVolumeClaim:\n      claimName: " + checkPVC + "\n"
}

func (p *NativeProvider) nfsCheckCmds() (cleanup []string, apply, wait, logs string) {
	ns := " --namespace " + checkNamespace
	cleanup = []string{
		"k3s kubectl delete pod " + checkPod + ns + " --ignore-not-found --wait=true --timeout=120s",
		"k3s kubectl delete pvc " + checkPVC + ns + " --ignore-not-found --wait=true --timeout=120s",
		"k3s kubectl delete namespace " + checkNamespace + " --ignore-not-found --wait=true --timeout=120s",
	}
	apply = "echo " + base64.StdEncoding.EncodeToString([]byte(checkManifest(p.spec.Host))) + " | base64 -d | k3s kubectl apply -f -"
	wait = "k3s kubectl wait" + ns + " --for=jsonpath='{.status.phase}'=Succeeded pod/" + checkPod + " --timeout=180s"
	logs = "k3s kubectl logs" + ns + " " + checkPod
	return
}

// runNFSCheck runs a short pod pinned to this node that mounts a throwaway NFS
// PVC, writes a file and reads it back, then deletes the pod and PVC. The pod
// names the node directly, so it runs even though the node is still cordoned.
func (p *NativeProvider) runNFSCheck(ctx context.Context, o RelocateOptions) error {
	cleanup, apply, wait, logs := p.nfsCheckCmds()
	clean := func(c context.Context) error {
		var first error
		for _, cmd := range cleanup {
			if _, err := o.Control(c, cmd); err != nil && first == nil {
				first = err
			}
		}
		return first
	}
	// Remove leftovers from an interrupted earlier run, and always clean up after.
	if err := clean(ctx); err != nil {
		return fmt.Errorf("removing an earlier check from namespace %s: %w", checkNamespace, err)
	}
	defer func() {
		cctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
		defer cancel()
		if err := clean(cctx); err != nil {
			fmt.Fprintf(o.Out, "  WARNING: could not delete the check objects in namespace %s: %v\n", checkNamespace, err)
		}
	}()
	if _, err := o.Control(ctx, apply); err != nil {
		return fmt.Errorf("creating the check pod and PVC: %w", err)
	}
	if _, err := o.Control(ctx, wait); err != nil {
		desc, _ := o.Control(ctx, "k3s kubectl describe pod "+checkPod+" --namespace "+checkNamespace+" | tail -n 25")
		return fmt.Errorf("the check pod did not finish: %w\n%s", err, strings.TrimSpace(desc))
	}
	out, err := o.Control(ctx, logs)
	if err != nil {
		return fmt.Errorf("reading the check pod's output: %w", err)
	}
	if !strings.Contains(out, checkToken) {
		return fmt.Errorf("the check pod ran but did not read back what it wrote (got %q)", strings.TrimSpace(out))
	}
	return nil
}
