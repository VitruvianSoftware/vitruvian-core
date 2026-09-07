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

package metrics

import (
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// This file holds the v1.1 parsers: the ones that describe what is RUNNING
// on the machine rather than how hard it is working. Same rule as
// metrics.go -- string in, struct out, no exec, no I/O -- so every one of
// them is pinned by a fixture captured from a real Mac and runs on Linux CI.
//
// One shape recurs: an optional source (Lima, Docker, kubectl) is either
// available with a list, or unavailable with a reason. Never an empty list,
// because "no VMs" and "limactl is not installed" look identical on a phone
// and only one of them is worth reacting to.

// Process is one row of GET /v1/processes.
type Process struct {
	Name        string  `json:"name"`
	CPUPercent  float64 `json:"cpu_percent"`
	MemoryBytes uint64  `json:"memory_bytes"`
}

// Processes is the body of GET /v1/processes.
type Processes struct {
	SampledAt time.Time `json:"sampled_at"`
	Processes []Process `json:"processes"`
}

// VM is one row of GET /v1/vms.
type VM struct {
	Name        string `json:"name"`
	Status      string `json:"status"`
	VMType      string `json:"vm_type"`
	CPUs        int    `json:"cpus"`
	MemoryBytes uint64 `json:"memory_bytes"`
	DiskBytes   uint64 `json:"disk_bytes"`
	Arch        string `json:"arch"`
}

// VMs is the body of GET /v1/vms.
type VMs struct {
	Available bool   `json:"available"`
	Reason    string `json:"reason"`
	VMs       []VM   `json:"vms"`
}

// Container is one row of GET /v1/containers.
type Container struct {
	Name   string `json:"name"`
	Image  string `json:"image"`
	Status string `json:"status"`
}

// Containers is the body of GET /v1/containers. Runtime names which tool
// answered, so a client can say "podman" when Docker Desktop is not the one
// running things.
type Containers struct {
	Available  bool        `json:"available"`
	Reason     string      `json:"reason"`
	Runtime    string      `json:"runtime"`
	Containers []Container `json:"containers"`
}

// Node is one row of GET /v1/k8s.
type Node struct {
	Name    string   `json:"name"`
	Ready   bool     `json:"ready"`
	Version string   `json:"version"`
	Roles   []string `json:"roles"`
}

// K8s is the body of GET /v1/k8s.
type K8s struct {
	Available bool   `json:"available"`
	Reason    string `json:"reason"`
	Context   string `json:"context"`
	Nodes     []Node `json:"nodes"`
}

// Audio is the body of GET /v1/audio and the reply to POST /v1/audio.
type Audio struct {
	VolumePercent int  `json:"volume_percent"`
	Muted         bool `json:"muted"`
}

// Session is one Claude Code project seen recently on this machine.
type Session struct {
	Project    string    `json:"project"`
	LastActive time.Time `json:"last_active"`
	Path       string    `json:"path"`
}

// Sessions is the body of GET /v1/sessions.
type Sessions struct {
	Sessions []Session `json:"sessions"`
	// RunningProcesses counts live `claude` processes, which is a different
	// question from "which projects have recent transcripts": a session can
	// have written its last line an hour ago and still be sitting at a
	// prompt, and a transcript can be fresh with nothing running.
	RunningProcesses int `json:"running_processes"`
}

// --- parsers -------------------------------------------------------------

// psRow matches one line of `ps -Aceo pcpu,rss,comm -r`:
//
//	12.9 5638688 com.apple.Virtualization.VirtualMachine
//
// The command name is the whole remainder of the line, not a field: `-c`
// prints the executable name, and plenty of them contain spaces ("Google
// Chrome Helper (Renderer)"). Splitting on whitespace truncates those to
// "Google".
var psRow = regexp.MustCompile(`^\s*([\d.]+)\s+(\d+)\s+(\S.*?)\s*$`)

// ParseProcesses reads `ps -Aceo pcpu,rss,comm -r` and keeps the first limit
// rows (limit <= 0 keeps all).
//
// `-r` already sorts by CPU descending, so "top N" is the head of the list
// and the parser does not re-sort. RSS is in KiB -- ps documents that
// nowhere -- and is converted here so the API only ever speaks bytes.
func ParseProcesses(out string, limit int) ([]Process, error) {
	var got []Process
	for _, line := range strings.Split(out, "\n") {
		if strings.Contains(line, "%CPU") {
			// The header. Skipped by content rather than by position so a
			// stray leading blank line cannot eat the first real row.
			continue
		}
		m := psRow.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		cpu, err := strconv.ParseFloat(m[1], 64)
		if err != nil {
			continue
		}
		rssKiB, err := strconv.ParseUint(m[2], 10, 64)
		if err != nil {
			continue
		}
		got = append(got, Process{Name: m[3], CPUPercent: cpu, MemoryBytes: rssKiB * 1024})
		if limit > 0 && len(got) == limit {
			break
		}
	}
	if got == nil {
		return nil, errors.New("ps: no process rows")
	}
	return got, nil
}

// ParseLimaList reads `limactl list --json`.
//
// It is NOT a JSON array: limactl prints one complete object per line, and
// each of those objects carries the instance's entire resolved config --
// several kilobytes of images, mounts and provisioning scripts nobody asked
// for. Decoding line by line into a struct with seven fields drops the rest.
func ParseLimaList(out string) ([]VM, error) {
	vms := []VM{}
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		var raw struct {
			Name   string `json:"name"`
			Status string `json:"status"`
			VMType string `json:"vmType"`
			CPUs   int    `json:"cpus"`
			Memory uint64 `json:"memory"`
			Disk   uint64 `json:"disk"`
			Arch   string `json:"arch"`
		}
		if err := json.Unmarshal([]byte(line), &raw); err != nil {
			return nil, fmt.Errorf("limactl: %w", err)
		}
		vms = append(vms, VM{
			Name:        raw.Name,
			Status:      raw.Status,
			VMType:      raw.VMType,
			CPUs:        raw.CPUs,
			MemoryBytes: raw.Memory,
			DiskBytes:   raw.Disk,
			Arch:        raw.Arch,
		})
	}
	return vms, nil
}

// ParseDockerPS reads `docker ps --format '{{json .}}'`: one object per line.
//
// Names in this format is a comma-separated string, not the array the Docker
// API returns. The first entry is the one docker itself prints.
func ParseDockerPS(out string) ([]Container, error) {
	cs := []Container{}
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		var raw struct {
			Names  string `json:"Names"`
			Image  string `json:"Image"`
			Status string `json:"Status"`
		}
		if err := json.Unmarshal([]byte(line), &raw); err != nil {
			return nil, fmt.Errorf("docker: %w", err)
		}
		name, _, _ := strings.Cut(raw.Names, ",")
		cs = append(cs, Container{Name: name, Image: raw.Image, Status: raw.Status})
	}
	return cs, nil
}

// ParsePodmanPS reads `podman ps --format json`, which -- unlike docker's
// per-line objects -- is one JSON array whose Names field is a real array of
// strings. An empty list prints "[]".
func ParsePodmanPS(out string) ([]Container, error) {
	out = strings.TrimSpace(out)
	if out == "" {
		return []Container{}, nil
	}
	var raw []struct {
		Names  []string `json:"Names"`
		Image  string   `json:"Image"`
		Status string   `json:"Status"`
	}
	if err := json.Unmarshal([]byte(out), &raw); err != nil {
		return nil, fmt.Errorf("podman: %w", err)
	}
	cs := make([]Container, 0, len(raw))
	for _, r := range raw {
		name := ""
		if len(r.Names) > 0 {
			name = r.Names[0]
		}
		cs = append(cs, Container{Name: name, Image: r.Image, Status: r.Status})
	}
	return cs, nil
}

// nodeRolePrefix is how Kubernetes labels a node's role. There is no field
// for it: the roles are whichever labels carry this prefix, and a node with
// none is a plain worker.
const nodeRolePrefix = "node-role.kubernetes.io/"

// ParseKubectlNodes reads `kubectl get nodes -o json`.
//
// Ready is the Ready condition being "True" -- NOT the absence of a problem.
// A node whose kubelet has stopped reporting has Ready="Unknown", which is
// exactly the state worth showing and the one an `!= "False"` test paints
// green.
func ParseKubectlNodes(out string) ([]Node, error) {
	var list struct {
		Items []struct {
			Metadata struct {
				Name   string            `json:"name"`
				Labels map[string]string `json:"labels"`
			} `json:"metadata"`
			Status struct {
				Conditions []struct {
					Type   string `json:"type"`
					Status string `json:"status"`
				} `json:"conditions"`
				NodeInfo struct {
					KubeletVersion string `json:"kubeletVersion"`
				} `json:"nodeInfo"`
			} `json:"status"`
		} `json:"items"`
	}
	if err := json.Unmarshal([]byte(out), &list); err != nil {
		return nil, fmt.Errorf("kubectl: %w", err)
	}
	nodes := make([]Node, 0, len(list.Items))
	for _, it := range list.Items {
		n := Node{Name: it.Metadata.Name, Version: it.Status.NodeInfo.KubeletVersion, Roles: []string{}}
		for _, c := range it.Status.Conditions {
			if c.Type == "Ready" {
				n.Ready = c.Status == "True"
			}
		}
		for k := range it.Metadata.Labels {
			if r, ok := strings.CutPrefix(k, nodeRolePrefix); ok && r != "" {
				n.Roles = append(n.Roles, r)
			}
		}
		sortStrings(n.Roles)
		nodes = append(nodes, n)
	}
	return nodes, nil
}

// sortStrings keeps role order stable across map iterations, which Go
// deliberately randomises. Without it a two-role node's JSON changes on
// every poll and a client diffing the response sees churn that is not there.
func sortStrings(s []string) {
	for i := 1; i < len(s); i++ {
		for j := i; j > 0 && s[j] < s[j-1]; j-- {
			s[j], s[j-1] = s[j-1], s[j]
		}
	}
}

var volumeSetting = regexp.MustCompile(`output volume:(\d+).*output muted:(true|false)`)

// ParseVolumeSettings reads `osascript -e 'get volume settings'`:
//
//	output volume:31, input volume:86, alert volume:50, output muted:false
//
// Output volume is the one a phone slider means; input and alert are
// deliberately dropped. A Mac whose output device reports no volume at all
// prints "output volume:missing value", which fails the digit match and is
// an error here rather than a confident 0%.
func ParseVolumeSettings(out string) (Audio, error) {
	m := volumeSetting.FindStringSubmatch(out)
	if m == nil {
		return Audio{}, fmt.Errorf("volume: unreadable settings %q", strings.TrimSpace(out))
	}
	v, _ := strconv.Atoi(m[1])
	return Audio{VolumePercent: v, Muted: m[2] == "true"}, nil
}

var etherLine = regexp.MustCompile(`(?m)^\s*ether\s+([0-9a-fA-F:]{17})\s*$`)

// ParseEther pulls the hardware address out of `ifconfig en0`. It is the
// address a Wake-on-LAN magic packet has to name, and en0 is the wired or
// primary Wi-Fi port on every Mac that has one.
func ParseEther(out string) (string, error) {
	m := etherLine.FindStringSubmatch(out)
	if m == nil {
		return "", errors.New("ifconfig: no ether line")
	}
	return strings.ToLower(m[1]), nil
}

var wompLine = regexp.MustCompile(`(?m)^\s*womp\s+(\d+)\s*$`)

// ParseWomp reads the `womp` setting out of `pmset -g`: "Wake On Magic
// Packet". 0 means a magic packet will not wake this Mac, so the phone must
// not offer the button. Machines that cannot do it at all print no womp
// line, which is also false.
func ParseWomp(out string) bool {
	m := wompLine.FindStringSubmatch(out)
	return m != nil && m[1] != "0"
}

// CountProcessesNamed counts the lines of `ps -Axo comm=` whose basename is
// name.
//
// Without `-c`, ps prints argv[0] in full -- an absolute path for anything
// launched normally -- so a substring match on "claude" also counts
// `claude-code-helper`, a `tail` of a claude log, and the shell that has
// "claude" in its working directory. Matching the basename exactly is the
// difference between "two sessions running" and "nine".
func CountProcessesNamed(out, name string) int {
	n := 0
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		// path/filepath is deliberately not imported here: this parses text
		// from a Mac, and must give the same answer on a Linux CI runner.
		if i := strings.LastIndex(line, "/"); i >= 0 {
			line = line[i+1:]
		}
		if line == name {
			n++
		}
	}
	return n
}

// ProjectFromDirName turns a Claude Code project directory name back into
// the path it encodes: `-Users-james-Workspace-foo` -> `Users/james/Workspace/foo`.
//
// The encoding is lossy -- a directory whose real name contains a hyphen is
// indistinguishable from a path separator -- so this is a display label, not
// a path to open. The API calls it "project" for that reason.
func ProjectFromDirName(dir string) string {
	return strings.ReplaceAll(strings.TrimPrefix(dir, "-"), "-", "/")
}

// CwdFromTranscript pulls the working directory out of the head of a Claude
// Code transcript. Each line is a JSON object and the early ones carry
// "cwd":"/abs/path". It is the truthful source for the project path: the
// directory NAME under ~/.claude/projects is a lossy encoding that turns
// every "/" into "-" and cannot be reversed when the path itself contains
// hyphens or dot-directories (".claude/worktrees/new-android-app-setup" came
// back as "/claude/worktrees/new/android/app/setup").
//
// Only the first occurrence is used and only within the given head, so a
// multi-megabyte transcript is never read in full.
func CwdFromTranscript(head string) string {
	const key = `"cwd":"`
	i := strings.Index(head, key)
	if i < 0 {
		return ""
	}
	rest := head[i+len(key):]
	j := strings.IndexByte(rest, '"')
	if j < 0 {
		return ""
	}
	return rest[:j]
}
