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
	"fmt"
	"strings"

	"github.com/VitruvianSoftware/vitruvian-devx/internal/multinode/util"
)

// The kubelet stays at the standard /var/lib/kubelet on every native node.
//
// A node with a custom dataDir keeps its bulk storage (k3s data-dir, pod volumes,
// ephemeral storage) on that volume, but the kubelet root-dir is NOT moved there.
// The kubelet hands CSI drivers absolute paths under its root-dir (for example an
// NFS NodePublishVolume target_path), and CSI node plugins such as csi-driver-nfs
// mount only the standard /var/lib/kubelet. A relocated root-dir therefore makes
// every such volume unusable on that node. Instead /var/lib/kubelet is a bind
// mount of <dataDir>/kubelet: the kubelet sees the standard path, the bytes live
// on the big volume, and the node still reports that volume's size.
const (
	kubeletStdPath       = "/var/lib/kubelet"
	kubeletMountUnitName = "var-lib-kubelet.mount" // systemd name for kubeletStdPath
	kubeletMountUnitPath = "/etc/systemd/system/" + kubeletMountUnitName
	kubeletDropInName    = "20-devx-kubelet-mount.conf"
)

// kubeletBackingDir is where a dataDir node keeps the kubelet's files.
func kubeletBackingDir(dataDir string) string {
	return strings.TrimRight(dataDir, "/") + "/kubelet"
}

// k3sUnitFor returns the k3s systemd unit for a role.
func k3sUnitFor(role string) string {
	if role == "server" {
		return "k3s.service"
	}
	return "k3s-agent.service"
}

// kubeletMountUnit renders the systemd mount unit that bind-mounts the backing
// directory at /var/lib/kubelet. It is ordered before both k3s units so the
// kubelet never starts against the bare mount point.
func kubeletMountUnit(dataDir string) string {
	return "[Unit]\n" +
		"Description=devx: bind " + kubeletBackingDir(dataDir) + " at " + kubeletStdPath + "\n" +
		"Before=k3s.service k3s-agent.service\n\n" +
		"[Mount]\n" +
		"What=" + kubeletBackingDir(dataDir) + "\n" +
		"Where=" + kubeletStdPath + "\n" +
		"Type=none\n" +
		"Options=bind\n\n" +
		"[Install]\n" +
		"WantedBy=local-fs.target\n"
}

// kubeletMountDropIn is the drop-in that makes a k3s unit require the bind mount,
// so k3s never starts (and the kubelet never writes) before it is mounted.
const kubeletMountDropIn = "[Unit]\nRequiresMountsFor=" + kubeletStdPath + "\n"

// kubeletBindMountCmd renders the one root command that converges a node onto the
// bind mount. It avoids `$`, backticks and newlines so it survives the
// `sudo sh -c %q` wrapping used by remote.Runner.RunSudo unchanged; file contents
// travel base64-encoded.
func kubeletBindMountCmd(dataDir, unit string) string {
	root := kubeletBackingDir(dataDir)
	dropDir := "/etc/systemd/system/" + unit + ".d"
	dropIn := dropDir + "/" + kubeletDropInName
	return strings.Join([]string{
		"mkdir -p " + root,
		// An older devx pointed /var/lib/kubelet at the backing dir with a symlink.
		"if [ -L " + kubeletStdPath + " ]; then rm -f " + kubeletStdPath + "; fi",
		"mkdir -p " + kubeletStdPath,
		// Never mount over real data: a non-empty directory that is not already a mount.
		"if ! mountpoint -q " + kubeletStdPath + " && find " + kubeletStdPath + " -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then " +
			"echo '" + kubeletStdPath + " is a non-empty directory and not a mount; refusing to mount over it' >&2; exit 1; fi",
		"echo " + util.Base64Encode(kubeletMountUnit(dataDir)) + " | base64 -d > " + kubeletMountUnitPath,
		"mkdir -p " + dropDir,
		"echo " + util.Base64Encode(kubeletMountDropIn) + " | base64 -d > " + dropIn,
		"systemctl daemon-reload",
		"systemctl enable --now " + kubeletMountUnitName,
	}, " && ")
}

// ensureKubeletBindMount makes /var/lib/kubelet a bind mount of <dataDir>/kubelet,
// persistent across reboots (a systemd mount unit ordered before k3s, plus a k3s
// drop-in requiring it). Idempotent: replaces the symlink an older devx created,
// and re-asserts the units on every call. No-op without a dataDir.
func (p *NativeProvider) ensureKubeletBindMount(ctx context.Context) error {
	if p.spec.DataDir == "" {
		return nil
	}
	if _, err := p.run(ctx, kubeletBindMountCmd(p.spec.DataDir, k3sUnitFor(p.spec.Role))); err != nil {
		return fmt.Errorf("[%s] bind-mounting %s at %s: %w", p.spec.Host, kubeletBackingDir(p.spec.DataDir), kubeletStdPath, err)
	}
	return nil
}
