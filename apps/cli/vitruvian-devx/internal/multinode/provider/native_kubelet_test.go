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
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/VitruvianSoftware/vitruvian-devx/internal/multinode/config"
	"gopkg.in/yaml.v3"
)

// decodeWrites finds every "echo <base64> | base64 -d > <path>" in a command and
// returns path -> decoded contents.
func decodeWrites(t *testing.T, cmd string) map[string]string {
	t.Helper()
	re := regexp.MustCompile(`echo ([A-Za-z0-9+/=]+) \| base64 -d > (\S+)`)
	out := map[string]string{}
	for _, m := range re.FindAllStringSubmatch(cmd, -1) {
		b, err := base64.StdEncoding.DecodeString(m[1])
		if err != nil {
			t.Fatalf("bad base64 in command: %v", err)
		}
		out[m[2]] = string(b)
	}
	return out
}

// shellSafe asserts a command survives remote.Runner.RunSudo's "sudo sh -c %q"
// wrapping: no dollar signs, backticks, backslashes or newlines for the login shell
// to reinterpret.
func shellSafe(t *testing.T, cmd string) {
	t.Helper()
	if strings.ContainsAny(cmd, "$`\\\n") {
		t.Errorf("command is not safe inside sudo sh -c %%q (has $, backtick, backslash or newline):\n%s", cmd)
	}
}

func dataDirNode(role string) *NativeProvider {
	return NewNativeProvider(config.NodeConfig{
		Host: "nuc9i5", Kind: "native", Role: role, Pool: "nuc-worker-1", DataDir: "/home/k3s",
	}, &config.Config{})
}

func TestEnsureKubeletBindMount_Agent(t *testing.T) {
	p := dataDirNode("agent")
	var calls []string
	p.run = func(ctx context.Context, cmd string) (string, error) { calls = append(calls, cmd); return "", nil }
	if err := p.ensureKubeletBindMount(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(calls) != 1 {
		t.Fatalf("want one root command, got %d:\n%s", len(calls), strings.Join(calls, "\n"))
	}
	cmd := calls[0]
	shellSafe(t, cmd)

	// The backing directory exists; an old symlink is removed; the mount point is a real dir.
	for _, want := range []string{
		"mkdir -p /home/k3s/kubelet",
		"if [ -L /var/lib/kubelet ]; then rm -f /var/lib/kubelet; fi",
		"mkdir -p /var/lib/kubelet",
	} {
		if !strings.Contains(cmd, want) {
			t.Errorf("missing %q in:\n%s", want, cmd)
		}
	}
	// Order: symlink removal before the mount-point mkdir before enable.
	if strings.Index(cmd, "rm -f /var/lib/kubelet") >= strings.Index(cmd, "mkdir -p /var/lib/kubelet") ||
		strings.Index(cmd, "mkdir -p /var/lib/kubelet") >= strings.Index(cmd, "systemctl enable --now") {
		t.Errorf("steps out of order:\n%s", cmd)
	}
	// Never mount over real data.
	if !strings.Contains(cmd, "mountpoint -q /var/lib/kubelet") || !strings.Contains(cmd, "refusing to mount over it") {
		t.Errorf("must refuse to mount over a non-empty directory:\n%s", cmd)
	}
	// The command ends with reload then enable --now, in that order.
	if !strings.HasSuffix(cmd, "systemctl daemon-reload && systemctl enable --now var-lib-kubelet.mount") {
		t.Errorf("must end with daemon-reload && enable --now var-lib-kubelet.mount:\n%s", cmd)
	}

	files := decodeWrites(t, cmd)
	unit, ok := files["/etc/systemd/system/var-lib-kubelet.mount"]
	if !ok {
		t.Fatalf("mount unit not written; wrote %v", files)
	}
	for _, want := range []string{
		"[Unit]\n", "Before=k3s.service k3s-agent.service\n", "RequiresMountsFor=/home/k3s/kubelet\n",
		"[Mount]\n", "What=/home/k3s/kubelet\n", "Where=/var/lib/kubelet\n", "Type=none\n", "Options=bind\n",
		"[Install]\n", "WantedBy=local-fs.target\n",
	} {
		if !strings.Contains(unit, want) {
			t.Errorf("mount unit missing %q:\n%s", want, unit)
		}
	}
	drop, ok := files["/etc/systemd/system/k3s-agent.service.d/20-devx-kubelet-mount.conf"]
	if !ok {
		t.Fatalf("agent drop-in not written; wrote %v", files)
	}
	if drop != "[Unit]\nRequiresMountsFor=/var/lib/kubelet\n" {
		t.Errorf("drop-in = %q", drop)
	}
}

func TestEnsureKubeletBindMount_ServerUsesK3sUnit(t *testing.T) {
	p := dataDirNode("server")
	var cmd string
	p.run = func(ctx context.Context, c string) (string, error) { cmd = c; return "", nil }
	if err := p.ensureKubeletBindMount(context.Background()); err != nil {
		t.Fatal(err)
	}
	if _, ok := decodeWrites(t, cmd)["/etc/systemd/system/k3s.service.d/20-devx-kubelet-mount.conf"]; !ok {
		t.Errorf("a server needs the drop-in on k3s.service:\n%s", cmd)
	}
	if strings.Contains(cmd, "k3s-agent.service.d") {
		t.Errorf("a server must not get an agent drop-in:\n%s", cmd)
	}
}

func TestEnsureKubeletBindMount_NoDataDirIsNoop(t *testing.T) {
	p, calls := nativeWithRunner(nil) // no DataDir
	if err := p.ensureKubeletBindMount(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(*calls) != 0 {
		t.Errorf("no dataDir must run nothing; got:\n%s", strings.Join(*calls, "\n"))
	}
}

func TestEnsureKubeletBindMount_ErrorNamesTheNode(t *testing.T) {
	p := dataDirNode("agent")
	p.run = func(ctx context.Context, c string) (string, error) { return "", context.DeadlineExceeded }
	err := p.ensureKubeletBindMount(context.Background())
	if err == nil || !strings.Contains(err.Error(), "nuc9i5") {
		t.Errorf("error should name the node, got %v", err)
	}
}

func TestInstallServer_BindMountBeforeInstall(t *testing.T) {
	p := dataDirNode("server")
	var calls []string
	p.run = func(ctx context.Context, cmd string) (string, error) { calls = append(calls, cmd); return "", nil }
	o := JoinOpts{NodeIP: "1.2.3.4", ServerURL: "https://cp:6443", Token: "t", Pool: "p"}
	if err := p.InstallServer(context.Background(), o); err != nil {
		t.Fatal(err)
	}
	mount, install := -1, -1
	for i, c := range calls {
		if strings.Contains(c, "enable --now var-lib-kubelet.mount") && mount < 0 {
			mount = i
		}
		if strings.Contains(c, "get.k3s.io") && install < 0 {
			install = i
		}
	}
	if mount < 0 || install < 0 || mount > install {
		t.Errorf("the bind mount must be set up before k3s is installed (mount=%d install=%d):\n%s", mount, install, strings.Join(calls, "\n"))
	}
	for _, c := range calls {
		if strings.Contains(c, "ln -sfn") || strings.Contains(c, "root-dir") {
			t.Errorf("no symlink and no root-dir any more; got: %s", c)
		}
	}
}

// --- config.yaml edits ---

const nuc9i5ConfigYAML = `# managed by devx
data-dir: /home/k3s
node-ip: 100.97.82.16
kubelet-arg:
  - root-dir=/home/k3s/kubelet
node-label:
  - pool=nuc-worker-1
`

func decodeMap(t *testing.T, s string) map[string]any {
	t.Helper()
	m := map[string]any{}
	if err := yaml.Unmarshal([]byte(s), &m); err != nil {
		t.Fatalf("output is not valid YAML: %v\n%s", err, s)
	}
	return m
}

func TestRemoveRootDirFromConfig_DropsEmptiedKey(t *testing.T) {
	out, changed, err := removeRootDirFromConfig(nuc9i5ConfigYAML)
	if err != nil || !changed {
		t.Fatalf("changed=%v err=%v", changed, err)
	}
	if strings.Contains(out, "root-dir") || strings.Contains(out, "kubelet-arg") {
		t.Errorf("an emptied kubelet-arg must be removed entirely:\n%s", out)
	}
	m := decodeMap(t, out)
	if m["data-dir"] != "/home/k3s" || m["node-ip"] != "100.97.82.16" {
		t.Errorf("other keys must be untouched: %v", m)
	}
	if labels, _ := m["node-label"].([]any); len(labels) != 1 || labels[0] != "pool=nuc-worker-1" {
		t.Errorf("node-label must be untouched: %v", m["node-label"])
	}
	if !strings.Contains(out, "# managed by devx") {
		t.Errorf("comments should survive:\n%s", out)
	}
}

func TestRemoveRootDirFromConfig_KeepsOtherKubeletArgs(t *testing.T) {
	src := `data-dir: /home/k3s
kubelet-arg:
  - max-pods=150
  - root-dir=/home/k3s/kubelet
  - eviction-hard=nodefs.available<5%
tls-san:
  - k8s-api.lab.ipv1337.dev
`
	out, changed, err := removeRootDirFromConfig(src)
	if err != nil || !changed {
		t.Fatalf("changed=%v err=%v", changed, err)
	}
	if strings.Contains(out, "root-dir") {
		t.Errorf("root-dir still present:\n%s", out)
	}
	m := decodeMap(t, out)
	args, _ := m["kubelet-arg"].([]any)
	if len(args) != 2 || args[0] != "max-pods=150" || args[1] != "eviction-hard=nodefs.available<5%" {
		t.Errorf("other kubelet-args must be kept, in order: %v", args)
	}
	if sans, _ := m["tls-san"].([]any); len(sans) != 1 || sans[0] != "k8s-api.lab.ipv1337.dev" {
		t.Errorf("tls-san changed: %v", m["tls-san"])
	}
	if m["data-dir"] != "/home/k3s" {
		t.Errorf("data-dir changed: %v", m["data-dir"])
	}
}

func TestRemoveRootDirFromConfig_FlowAndDashForms(t *testing.T) {
	for name, src := range map[string]string{
		"flow list":      "data-dir: /home/k3s\nkubelet-arg: [root-dir=/home/k3s/kubelet]\n",
		"quoted entry":   "data-dir: /home/k3s\nkubelet-arg:\n- \"root-dir=/home/k3s/kubelet\"\n",
		"leading dashes": "data-dir: /home/k3s\nkubelet-arg:\n- --root-dir=/home/k3s/kubelet\n",
		"bare scalar":    "data-dir: /home/k3s\nkubelet-arg: root-dir=/home/k3s/kubelet\n",
		"append key":     "data-dir: /home/k3s\nkubelet-arg+:\n- root-dir=/home/k3s/kubelet\n",
	} {
		out, changed, err := removeRootDirFromConfig(src)
		if err != nil || !changed {
			t.Errorf("%s: changed=%v err=%v", name, changed, err)
			continue
		}
		if strings.Contains(out, "root-dir") || strings.Contains(out, "kubelet-arg") {
			t.Errorf("%s: should be gone:\n%s", name, out)
		}
		if decodeMap(t, out)["data-dir"] != "/home/k3s" {
			t.Errorf("%s: data-dir lost:\n%s", name, out)
		}
	}
}

func TestRemoveRootDirFromConfig_KeepsTheHeaderCommentWhenTheFirstKeyEmpties(t *testing.T) {
	// The header comment sits on kubelet-arg, the key that disappears. It must stay.
	src := "# managed by devx - do not edit by hand\n# second header line\nkubelet-arg:\n  - root-dir=/home/k3s/kubelet\ndata-dir: /home/k3s # the big volume\nnode-label:\n  - pool=nuc\n"
	out, changed, err := removeRootDirFromConfig(src)
	if err != nil || !changed {
		t.Fatalf("changed=%v err=%v", changed, err)
	}
	want := "# managed by devx - do not edit by hand\n# second header line\ndata-dir: /home/k3s # the big volume\nnode-label:\n  - pool=nuc\n"
	if out != want {
		t.Errorf("only the root-dir lines may go.\ngot:\n%s\nwant:\n%s", out, want)
	}
}

func TestRemoveRootDirFromConfig_ByteForByteOtherwise(t *testing.T) {
	src := "data-dir: /home/k3s   # keep my spacing\n\nkubelet-arg:\n    - max-pods=150\n    - 'root-dir=/home/k3s/kubelet'   # drop me\n    - eviction-hard=nodefs.available<5%\ntoken: \"abc\"\n"
	out, changed, err := removeRootDirFromConfig(src)
	if err != nil || !changed {
		t.Fatalf("changed=%v err=%v", changed, err)
	}
	want := "data-dir: /home/k3s   # keep my spacing\n\nkubelet-arg:\n    - max-pods=150\n    - eviction-hard=nodefs.available<5%\ntoken: \"abc\"\n"
	if out != want {
		t.Errorf("got:\n%s\nwant:\n%s", out, want)
	}
}

func TestRemoveRootDirFromConfig_MixedFlowListIsRewrittenInPlace(t *testing.T) {
	src := "data-dir: /home/k3s\nkubelet-arg: [max-pods=150, root-dir=/home/k3s/kubelet]\n"
	out, changed, err := removeRootDirFromConfig(src)
	if err != nil || !changed {
		t.Fatalf("changed=%v err=%v", changed, err)
	}
	if out != "data-dir: /home/k3s\nkubelet-arg: [max-pods=150]\n" {
		t.Errorf("out = %q", out)
	}
}

func TestRemoveRootDirFromConfig_RefusesShapesItCannotEditSafely(t *testing.T) {
	src := "kubelet-arg: [\n  max-pods=150,\n  root-dir=/home/k3s/kubelet\n]\n"
	if _, _, err := removeRootDirFromConfig(src); !errors.Is(err, errUnsafeEdit) {
		t.Errorf("a multi-line flow list must be refused, got %v", err)
	}
}

func TestRemoveRootDirFromConfig_NoRootDirIsVerbatim(t *testing.T) {
	src := "data-dir: /home/k3s\nkubelet-arg:\n    - max-pods=150\n"
	out, changed, err := removeRootDirFromConfig(src)
	if err != nil || changed || out != src {
		t.Errorf("no root-dir must return the input verbatim: changed=%v err=%v out=%q", changed, err, out)
	}
	if out, changed, _ := removeRootDirFromConfig(""); changed || out != "" {
		t.Errorf("empty config: changed=%v out=%q", changed, out)
	}
	if _, _, err := removeRootDirFromConfig("data-dir: [unterminated"); err == nil {
		t.Error("invalid YAML must be an error, not silently rewritten")
	}
}

func TestRootDirValuesInConfig(t *testing.T) {
	vals, err := rootDirValuesInConfig(nuc9i5ConfigYAML)
	if err != nil || len(vals) != 1 || vals[0] != "/home/k3s/kubelet" {
		t.Errorf("vals=%v err=%v", vals, err)
	}
	if vals, _ := rootDirValuesInConfig("data-dir: /home/k3s\n"); len(vals) != 0 {
		t.Errorf("none expected: %v", vals)
	}
}

// --- systemd ExecStart edits ---

const k3sServerUnit = `[Unit]
Description=Lightweight Kubernetes

[Service]
Type=notify
ExecStart=/usr/local/bin/k3s \
    server \
    '--node-name=nuc9i5' \
    '--data-dir=/home/k3s' \
    '--kubelet-arg=root-dir=/home/k3s/kubelet' \
    '--node-label=pool=nuc' \

[Install]
WantedBy=multi-user.target
`

func TestRemoveRootDirFromUnit_MiddleLine(t *testing.T) {
	out, changed := removeRootDirFromUnit(k3sServerUnit)
	if !changed {
		t.Fatal("expected a change")
	}
	if strings.Contains(out, "root-dir") {
		t.Errorf("root-dir still present:\n%s", out)
	}
	for _, keep := range []string{"'--node-name=nuc9i5' \\", "'--data-dir=/home/k3s' \\", "'--node-label=pool=nuc' \\", "[Install]"} {
		if !strings.Contains(out, keep) {
			t.Errorf("lost %q:\n%s", keep, out)
		}
	}
}

func TestRemoveRootDirFromUnit_LastLineFixesContinuation(t *testing.T) {
	src := "[Service]\nExecStart=/usr/local/bin/k3s \\\n    server \\\n    '--data-dir=/home/k3s' \\\n    '--kubelet-arg=root-dir=/home/k3s/kubelet'\n\n[Install]\nWantedBy=multi-user.target\n"
	out, changed := removeRootDirFromUnit(src)
	if !changed || strings.Contains(out, "root-dir") {
		t.Fatalf("changed=%v:\n%s", changed, out)
	}
	if !strings.Contains(out, "'--data-dir=/home/k3s'\n") {
		t.Errorf("the new last line must not end in a backslash:\n%s", out)
	}
	if strings.Contains(out, "'--data-dir=/home/k3s' \\") {
		t.Errorf("dangling continuation:\n%s", out)
	}
}

func TestRemoveRootDirFromUnit_SeparateArgPairAndInline(t *testing.T) {
	pair := "ExecStart=/usr/local/bin/k3s \\\n    server \\\n    '--kubelet-arg' \\\n    'root-dir=/home/k3s/kubelet' \\\n    '--node-label=pool=nuc' \\\n"
	out, changed := removeRootDirFromUnit(pair)
	if !changed || strings.Contains(out, "root-dir") || strings.Contains(out, "'--kubelet-arg'") || !strings.Contains(out, "--node-label=pool=nuc") {
		t.Errorf("pair form: changed=%v\n%s", changed, out)
	}
	inline := "ExecStart=/usr/local/bin/k3s server --data-dir=/home/k3s --kubelet-arg=root-dir=/home/k3s/kubelet --node-name=x\n"
	out, changed = removeRootDirFromUnit(inline)
	if !changed || out != "ExecStart=/usr/local/bin/k3s server --data-dir=/home/k3s --node-name=x\n" {
		t.Errorf("inline form: changed=%v out=%q", changed, out)
	}
}

func TestRemoveRootDirFromUnit_NoRootDirIsVerbatim(t *testing.T) {
	src := "[Service]\nExecStart=/usr/local/bin/k3s server\n"
	if out, changed := removeRootDirFromUnit(src); changed || out != src {
		t.Errorf("changed=%v out=%q", changed, out)
	}
	if vals := rootDirValuesInUnit(k3sServerUnit); len(vals) != 1 || vals[0] != "/home/k3s/kubelet" {
		t.Errorf("unit values = %v", vals)
	}
	pair := "    '--kubelet-arg' \\\n    'root-dir=/x/kubelet' \\\n"
	if vals := rootDirValuesInUnit(pair); len(vals) != 1 || vals[0] != "/x/kubelet" {
		t.Errorf("pair values = %v", vals)
	}
}

// --- the bind-mount command, run for real ---

// runBindMount runs the real shell command against a temp tree, with stub
// systemctl and mountpoint on PATH. mounted makes the stub mountpoint say yes.
func runBindMount(t *testing.T, root string, mounted bool) (stdout string, err error) {
	t.Helper()
	bin := filepath.Join(root, "bin")
	if err := os.MkdirAll(bin, 0o755); err != nil {
		t.Fatal(err)
	}
	stub := func(name, body string) {
		if err := os.WriteFile(filepath.Join(bin, name), []byte("#!/bin/sh\n"+body), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	stub("systemctl", `echo "$@" >> "$STUB_LOG"`+"\n")
	stub("mountpoint", `[ -e "$STUB_MOUNTED" ]`+"\n")
	mountedFlag := filepath.Join(root, "is-mounted")
	if mounted {
		if err := os.WriteFile(mountedFlag, nil, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	bp := bindPaths{std: filepath.Join(root, "var/lib/kubelet"), systemd: filepath.Join(root, "etc/systemd/system"), mountUnit: "var-lib-kubelet.mount"}
	cmd := exec.Command("sh", "-c", bindMountCmdAt(bp, filepath.Join(root, "data"), "k3s.service"))
	cmd.Env = []string{"PATH=" + bin + ":/usr/bin:/bin", "STUB_LOG=" + filepath.Join(root, "systemctl.log"), "STUB_MOUNTED=" + mountedFlag}
	out, err := cmd.CombinedOutput()
	return string(out), err
}

func TestBindMountCmd_RunsForReal(t *testing.T) {
	if _, err := exec.LookPath("base64"); err != nil {
		t.Skip("no base64 on this host")
	}
	read := func(path string) string {
		b, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		return string(b)
	}
	setup := func(t *testing.T) (root string, bp bindPaths) {
		root, err := os.MkdirTemp("", "bindmount")
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { _ = os.RemoveAll(root) })
		bp = bindPaths{std: filepath.Join(root, "var/lib/kubelet"), systemd: filepath.Join(root, "etc/systemd/system"), mountUnit: "var-lib-kubelet.mount"}
		if err := os.MkdirAll(filepath.Dir(bp.std), 0o755); err != nil {
			t.Fatal(err)
		}
		return
	}

	t.Run("replaces the old symlink and writes the units", func(t *testing.T) {
		root, bp := setup(t)
		backing := filepath.Join(root, "data/kubelet")
		if err := os.MkdirAll(backing, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(backing, "keep-me"), []byte("pod data"), 0o644); err != nil {
			t.Fatal(err)
		}
		if err := os.Symlink(backing, bp.std); err != nil {
			t.Fatal(err)
		}
		if out, err := runBindMount(t, root, false); err != nil {
			t.Fatalf("command failed: %v\n%s", err, out)
		}
		fi, err := os.Lstat(bp.std)
		if err != nil || fi.Mode()&os.ModeSymlink != 0 || !fi.IsDir() {
			t.Errorf("%s must now be a real directory (the mount point): %v %v", bp.std, fi, err)
		}
		if got := read(filepath.Join(backing, "keep-me")); got != "pod data" {
			t.Errorf("the data behind the old symlink must be untouched, got %q", got)
		}
		if got, want := read(filepath.Join(bp.systemd, "var-lib-kubelet.mount")), kubeletMountUnitAt(bp, filepath.Join(root, "data")); got != want {
			t.Errorf("mount unit:\n%s\nwant:\n%s", got, want)
		}
		if got := read(filepath.Join(bp.systemd, "k3s.service.d", kubeletDropInName)); got != kubeletMountDropIn {
			t.Errorf("drop-in = %q", got)
		}
		if got := read(filepath.Join(root, "systemctl.log")); got != "daemon-reload\nenable --now var-lib-kubelet.mount\n" {
			t.Errorf("systemctl calls = %q", got)
		}
	})

	t.Run("accepts an empty directory and is idempotent", func(t *testing.T) {
		root, bp := setup(t)
		if err := os.MkdirAll(bp.std, 0o755); err != nil {
			t.Fatal(err)
		}
		for i := 0; i < 2; i++ {
			if out, err := runBindMount(t, root, false); err != nil {
				t.Fatalf("run %d failed: %v\n%s", i+1, err, out)
			}
		}
		if got := read(filepath.Join(root, "systemctl.log")); got != strings.Repeat("daemon-reload\nenable --now var-lib-kubelet.mount\n", 2) {
			t.Errorf("systemctl calls = %q", got)
		}
	})

	t.Run("refuses to mount over a non-empty directory", func(t *testing.T) {
		root, bp := setup(t)
		if err := os.MkdirAll(bp.std, 0o755); err != nil {
			t.Fatal(err)
		}
		precious := filepath.Join(bp.std, "precious")
		if err := os.WriteFile(precious, []byte("data"), 0o644); err != nil {
			t.Fatal(err)
		}
		out, err := runBindMount(t, root, false)
		if err == nil || !strings.Contains(out, "refusing to mount over it") {
			t.Fatalf("must refuse; err=%v out=%q", err, out)
		}
		if got := read(precious); got != "data" {
			t.Error("the directory's data must be untouched")
		}
		if _, err := os.Stat(filepath.Join(bp.systemd, "var-lib-kubelet.mount")); err == nil {
			t.Error("no unit may be written when refusing")
		}
		if _, err := os.Stat(filepath.Join(root, "systemctl.log")); err == nil {
			t.Error("systemctl must not be called when refusing")
		}
	})

	t.Run("a populated directory that is already the mount is fine", func(t *testing.T) {
		root, bp := setup(t)
		if err := os.MkdirAll(bp.std, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(bp.std, "pods"), nil, 0o644); err != nil {
			t.Fatal(err)
		}
		if out, err := runBindMount(t, root, true); err != nil {
			t.Fatalf("an existing mount must pass: %v\n%s", err, out)
		}
	})
}
