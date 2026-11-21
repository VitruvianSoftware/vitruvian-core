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
//
// Why installScript passes only --data-dir and no root-dir: k3s (checked at
// v1.35.3+k3s1) sets the kubelet's root-dir only when running rootless
// (pkg/agent/config/config.go: `if envInfo.Rootless { ...AgentConfig.RootDir =
// <dataDir>/agent/kubelet }`) and passes it to the kubelet only when non-empty
// (pkg/daemons/agent/agent_linux.go: `if cfg.RootDir != "" { argsMap["root-dir"] =
// cfg.RootDir }`). So with --data-dir alone the kubelet keeps its own default,
// /var/lib/kubelet. relocate-kubelet's final NFS check is the live backstop for
// this assumption.
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

// bindPaths are the host paths the bind-mount command works on. Production uses
// stdBindPaths; a test points them at a temp directory to run the real shell.
type bindPaths struct {
	std       string // the mount point, /var/lib/kubelet
	systemd   string // where unit files go, /etc/systemd/system
	mountUnit string // the mount unit's name, var-lib-kubelet.mount
}

var stdBindPaths = bindPaths{std: kubeletStdPath, systemd: "/etc/systemd/system", mountUnit: kubeletMountUnitName}

// kubeletMountUnitAt renders the systemd mount unit that bind-mounts the backing
// directory at bp.std (/var/lib/kubelet). It is ordered before both k3s units so the
// kubelet never starts against the bare mount point, and it requires the volume
// that holds the backing directory (/home, say) to be mounted first.
func kubeletMountUnitAt(bp bindPaths, dataDir string) string {
	return "[Unit]\n" +
		"Description=devx: bind " + kubeletBackingDir(dataDir) + " at " + bp.std + "\n" +
		"RequiresMountsFor=" + kubeletBackingDir(dataDir) + "\n" +
		"Before=k3s.service k3s-agent.service\n\n" +
		"[Mount]\n" +
		"What=" + kubeletBackingDir(dataDir) + "\n" +
		"Where=" + bp.std + "\n" +
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
	return bindMountCmdAt(stdBindPaths, dataDir, unit)
}

func bindMountCmdAt(bp bindPaths, dataDir, unit string) string {
	root := kubeletBackingDir(dataDir)
	dropDir := bp.systemd + "/" + unit + ".d"
	dropIn := dropDir + "/" + kubeletDropInName
	unitPath := bp.systemd + "/" + bp.mountUnit
	return strings.Join([]string{
		"mkdir -p " + root,
		// An older devx pointed /var/lib/kubelet at the backing dir with a symlink.
		"if [ -L " + bp.std + " ]; then rm -f " + bp.std + "; fi",
		"mkdir -p " + bp.std,
		// Never mount over real data: a non-empty directory that is not already a mount.
		"if ! mountpoint -q " + bp.std + " && find " + bp.std + " -mindepth 1 -maxdepth 1 | grep -q .; then " +
			"echo '" + bp.std + " is a non-empty directory and not a mount; refusing to mount over it' >&2; exit 1; fi",
		"mkdir -p " + bp.systemd,
		"echo " + util.Base64Encode(kubeletMountUnitAt(bp, dataDir)) + " | base64 -d > " + unitPath,
		"mkdir -p " + dropDir,
		"echo " + util.Base64Encode(kubeletMountDropIn) + " | base64 -d > " + dropIn,
		"systemctl daemon-reload",
		"systemctl enable --now " + bp.mountUnit,
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
