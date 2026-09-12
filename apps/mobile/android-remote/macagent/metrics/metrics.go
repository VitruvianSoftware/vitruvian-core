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

// Package metrics turns the text that macOS command-line tools print into
// numbers.
//
// Every function here is a PURE parser: string in, struct out, no exec, no
// I/O. That split is the point. The commands themselves only run on a Mac,
// but a parser that takes a string can be pinned by a plain Go test on the
// Linux CI runner -- against fixtures captured from a real machine -- and
// that is where the bugs in this kind of code actually live: a column that
// shifted, a unit that was centi-Celsius all along, a sentinel value that
// means "unknown" and was read as 65535 minutes.
//
// Nothing here needs root. What macOS will not hand an unprivileged process
// -- SoC temperature, fan speed, GPU and Neural Engine load, package power --
// is reported as absent (see Snapshot.Unavailable), never estimated.
package metrics

import (
	"bufio"
	"errors"
	"fmt"
	"math"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// Snapshot is one reading of the machine, as served by GET /v1/metrics.
type Snapshot struct {
	SampledAt time.Time `json:"sampled_at"`
	CPU       CPU       `json:"cpu"`
	Memory    Memory    `json:"memory"`
	Battery   Battery   `json:"battery"`
	Disk      Disk      `json:"disk"`
	Network   Network   `json:"network"`
	Thermal   Thermal   `json:"thermal"`
	// UptimeSeconds since kern.boottime.
	UptimeSeconds int64 `json:"uptime_seconds"`
	// Unavailable names every field a client might expect that this agent
	// cannot read without root, with the reason. Explicit rather than merely
	// omitted, so a dashboard can say "not available" instead of showing a
	// blank -- or worse, a stale or invented number.
	Unavailable map[string]string `json:"unavailable"`
}

// Host is the slow-changing description served by GET /v1/host.
type Host struct {
	Hostname     string `json:"hostname"`
	Model        string `json:"model"`
	Chip         string `json:"chip"`
	Cores        int    `json:"cores"`
	MemoryBytes  uint64 `json:"memory_bytes"`
	OSVersion    string `json:"os_version"`
	AgentVersion string `json:"agent_version"`
	// MACAddress is en0's hardware address, which is what a Wake-on-LAN
	// magic packet has to name. Empty when the machine has no en0.
	MACAddress string `json:"mac_address"`
	// WakeOnLAN is the `womp` setting from pmset: whether a magic packet
	// will actually wake this Mac. False means the phone must not offer the
	// button -- sending a packet nothing acts on looks identical to a
	// machine that is simply slow to come back.
	WakeOnLAN bool `json:"wake_on_lan"`
}

type CPU struct {
	// Ready is false until top has produced its first real sample, which
	// takes a few seconds after start. Before that every percentage below is
	// zero, and a client must be able to tell "not yet" from "idle".
	Ready         bool    `json:"ready"`
	UserPercent   float64 `json:"user_percent"`
	SystemPercent float64 `json:"system_percent"`
	IdlePercent   float64 `json:"idle_percent"`
	// BusyPercent is user + system: the one number a gauge wants.
	BusyPercent float64 `json:"busy_percent"`
	Load1       float64 `json:"load_1"`
	Load5       float64 `json:"load_5"`
	Load15      float64 `json:"load_15"`
	Cores       int     `json:"cores"`
}

type Memory struct {
	TotalBytes uint64 `json:"total_bytes"`
	// UsedBytes is what Activity Monitor calls "Memory Used": active + wired +
	// the pages the compressor currently occupies. Inactive and speculative
	// pages are reclaimable and are deliberately not counted.
	UsedBytes   uint64  `json:"used_bytes"`
	UsedPercent float64 `json:"used_percent"`
	// FreePercent is the kernel's own figure (kern.memorystatus_level), the
	// number `memory_pressure` prints and the pressure graph is derived from.
	// It is NOT 100 - UsedPercent: the kernel counts compressible and
	// reclaimable memory differently from a simple used/total ratio, and its
	// number is the one that decides when apps get memory warnings.
	FreePercent int `json:"free_percent"`
}

type Battery struct {
	Present  bool `json:"present"`
	Percent  int  `json:"percent"`
	Charging bool `json:"charging"`
	OnAC     bool `json:"on_ac"`
	// TemperatureC is the battery pack's own sensor -- the ONE temperature an
	// unprivileged process can read on Apple Silicon. It is not the SoC.
	TemperatureC float64 `json:"temperature_c"`
	VoltageMV    int     `json:"voltage_mv"`
	// AmperageMA is negative while discharging, zero on AC and not charging.
	AmperageMA int `json:"amperage_ma"`
	// DrawWatts is |amperage| * voltage: the battery's own discharge rate, so
	// it is only meaningful off AC. On AC it reads 0, which is the truth about
	// the battery and says nothing about what the machine is pulling from the
	// wall -- that needs powermetrics, which needs root.
	DrawWatts  float64 `json:"draw_watts"`
	CycleCount int     `json:"cycle_count"`
	// MinutesRemaining is nil when macOS reports the 65535 "unknown" sentinel,
	// which it does on AC and for a while after any transition.
	MinutesRemaining *int `json:"minutes_remaining"`
}

type Disk struct {
	Mount          string  `json:"mount"`
	TotalBytes     uint64  `json:"total_bytes"`
	UsedBytes      uint64  `json:"used_bytes"`
	AvailableBytes uint64  `json:"available_bytes"`
	UsedPercent    float64 `json:"used_percent"`
}

type Network struct {
	Interface string `json:"interface"`
	RxBytes   uint64 `json:"rx_bytes"`
	TxBytes   uint64 `json:"tx_bytes"`
	// Rates are computed by the sampler from two readings; zero on the first.
	RxBytesPerSec float64 `json:"rx_bytes_per_sec"`
	TxBytesPerSec float64 `json:"tx_bytes_per_sec"`
}

type Thermal struct {
	// Throttled is true when pmset reports any CPU limit below 100%.
	Throttled bool `json:"throttled"`
	// CPUSpeedLimitPercent is 100 when the machine is not throttling. pmset
	// only prints the key while a limit is in effect; its absence means 100.
	CPUSpeedLimitPercent int `json:"cpu_speed_limit_percent"`
}

// --- parsers -------------------------------------------------------------

var topCPU = regexp.MustCompile(`CPU usage:\s+([\d.]+)% user,\s+([\d.]+)% sys,\s+([\d.]+)% idle`)

// ParseTop reads the CPU line from `top -l 2 -n 0 -s 1`.
//
// It takes the LAST match. top's first sample is the average since boot,
// which is why the sampler asks for two: only the second reflects the
// last second. A parser that took the first line would report a number that
// barely moves and is wrong by tens of percent on a busy machine.
func ParseTop(out string) (CPU, error) {
	m := topCPU.FindAllStringSubmatch(out, -1)
	if len(m) == 0 {
		return CPU{}, errors.New("top: no 'CPU usage' line")
	}
	last := m[len(m)-1]
	user, _ := strconv.ParseFloat(last[1], 64)
	sys, _ := strconv.ParseFloat(last[2], 64)
	idle, _ := strconv.ParseFloat(last[3], 64)
	return CPU{
		Ready:         true,
		UserPercent:   user,
		SystemPercent: sys,
		IdlePercent:   idle,
		// Rounded: two float64 percentages summed print as 20.259999999999998,
		// and a JSON reader should not have to know why.
		BusyPercent: math.Round((user+sys)*100) / 100,
	}, nil
}

// ParseLoadAvg reads `sysctl -n vm.loadavg`: "{ 2.83 4.02 4.18 }".
func ParseLoadAvg(out string) (l1, l5, l15 float64, err error) {
	f := strings.Fields(strings.Trim(strings.TrimSpace(out), "{}"))
	if len(f) < 3 {
		return 0, 0, 0, fmt.Errorf("loadavg: want 3 fields in %q", out)
	}
	l1, _ = strconv.ParseFloat(f[0], 64)
	l5, _ = strconv.ParseFloat(f[1], 64)
	l15, _ = strconv.ParseFloat(f[2], 64)
	return l1, l5, l15, nil
}

var vmPageSize = regexp.MustCompile(`page size of (\d+) bytes`)

// ParseVmStat turns `vm_stat` output into a Memory, given hw.memsize and the
// kernel's free percentage (kern.memorystatus_level).
//
// vm_stat reports pages, and the page size is in its header line -- 16 KiB
// on Apple Silicon, 4 KiB on Intel -- so it is read rather than assumed.
// Counts end in a trailing '.', which is stripped.
func ParseVmStat(out string, totalBytes uint64, freePercent int) (Memory, error) {
	ps := vmPageSize.FindStringSubmatch(out)
	if ps == nil {
		return Memory{}, errors.New("vm_stat: no page size header")
	}
	pageSize, _ := strconv.ParseUint(ps[1], 10, 64)

	pages := map[string]uint64{}
	sc := bufio.NewScanner(strings.NewReader(out))
	for sc.Scan() {
		k, v, ok := strings.Cut(sc.Text(), ":")
		if !ok {
			continue
		}
		n, err := strconv.ParseUint(strings.TrimSuffix(strings.TrimSpace(v), "."), 10, 64)
		if err != nil {
			continue
		}
		pages[strings.TrimSpace(k)] = n
	}
	for _, need := range []string{"Pages active", "Pages wired down", "Pages occupied by compressor"} {
		if _, ok := pages[need]; !ok {
			return Memory{}, fmt.Errorf("vm_stat: missing %q", need)
		}
	}
	used := (pages["Pages active"] + pages["Pages wired down"] + pages["Pages occupied by compressor"]) * pageSize
	m := Memory{TotalBytes: totalBytes, UsedBytes: used, FreePercent: freePercent}
	if totalBytes > 0 {
		m.UsedPercent = float64(used) / float64(totalBytes) * 100
	}
	return m, nil
}

// unknownMinutes is what AppleSmartBattery reports for TimeRemaining when it
// has no estimate. Reading it as a real duration gives "45 hours remaining".
const unknownMinutes = 65535

// ParseBattery reads `ioreg -r -c AppleSmartBattery -d 1`.
//
// The registry prints `"Key" = Value` one per line. The units are the trap:
// Temperature is centi-Celsius (3048 is 30.48 C), Voltage is millivolts,
// Amperage is milliamps and signed, TimeRemaining is minutes with 65535
// meaning unknown. None of that is documented next to the values.
func ParseBattery(out string) (Battery, error) {
	kv := map[string]string{}
	sc := bufio.NewScanner(strings.NewReader(out))
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if !strings.HasPrefix(line, `"`) {
			continue
		}
		k, v, ok := strings.Cut(line, " = ")
		if !ok {
			continue
		}
		kv[strings.Trim(k, `"`)] = strings.TrimSpace(v)
	}
	if _, ok := kv["CurrentCapacity"]; !ok {
		// No battery at all -- a Mac mini or Studio. Not an error.
		return Battery{Present: false}, nil
	}
	num := func(k string) int { n, _ := strconv.Atoi(kv[k]); return n }
	yes := func(k string) bool { return kv[k] == "Yes" }

	b := Battery{
		Present:      true,
		Percent:      num("CurrentCapacity"),
		Charging:     yes("IsCharging"),
		OnAC:         yes("ExternalConnected"),
		TemperatureC: float64(num("Temperature")) / 100,
		VoltageMV:    num("Voltage"),
		AmperageMA:   num("Amperage"),
		CycleCount:   num("CycleCount"),
	}
	// MaxCapacity is 100 on Apple Silicon (CurrentCapacity is already a
	// percentage) but a raw mAh figure on some Intel models. Normalise.
	if mc := num("MaxCapacity"); mc > 0 && mc != 100 {
		b.Percent = b.Percent * 100 / mc
	}
	if b.AmperageMA < 0 {
		b.DrawWatts = float64(-b.AmperageMA) * float64(b.VoltageMV) / 1e6
	}
	if tr := num("TimeRemaining"); tr != unknownMinutes && kv["TimeRemaining"] != "" {
		b.MinutesRemaining = &tr
	}
	return b, nil
}

// ParseDf reads `df -k <mount>`: the last line is the filesystem, in 1 KiB
// blocks. Only the first four columns are stable across macOS versions; the
// inode columns after them are not used.
func ParseDf(out string, mount string) (Disk, error) {
	lines := strings.Split(strings.TrimSpace(out), "\n")
	if len(lines) < 2 {
		return Disk{}, errors.New("df: no data line")
	}
	f := strings.Fields(lines[len(lines)-1])
	if len(f) < 4 {
		return Disk{}, fmt.Errorf("df: want >=4 columns in %q", lines[len(lines)-1])
	}
	const kib = 1024
	total, _ := strconv.ParseUint(f[1], 10, 64)
	used, _ := strconv.ParseUint(f[2], 10, 64)
	avail, _ := strconv.ParseUint(f[3], 10, 64)
	d := Disk{Mount: mount, TotalBytes: total * kib, UsedBytes: used * kib, AvailableBytes: avail * kib}
	if total > 0 {
		d.UsedPercent = float64(used) / float64(total) * 100
	}
	return d, nil
}

// ParseNetstat finds the link-level row for iface in `netstat -ib`.
//
// Each interface appears several times -- once per address family -- and
// only the `<Link#N>` row carries the byte counters for the whole interface.
// Columns: Name Mtu Network Address Ipkts Ierrs Ibytes Opkts Oerrs Obytes.
func ParseNetstat(out string, iface string) (Network, error) {
	sc := bufio.NewScanner(strings.NewReader(out))
	for sc.Scan() {
		f := strings.Fields(sc.Text())
		if len(f) < 10 || f[0] != iface || !strings.HasPrefix(f[2], "<Link") {
			continue
		}
		rx, _ := strconv.ParseUint(f[6], 10, 64)
		tx, _ := strconv.ParseUint(f[9], 10, 64)
		return Network{Interface: iface, RxBytes: rx, TxBytes: tx}, nil
	}
	return Network{}, fmt.Errorf("netstat: no link row for %q", iface)
}

// ParseDefaultInterface reads `route -n get default` for the interface name.
func ParseDefaultInterface(out string) (string, error) {
	sc := bufio.NewScanner(strings.NewReader(out))
	for sc.Scan() {
		k, v, ok := strings.Cut(strings.TrimSpace(sc.Text()), ":")
		if ok && strings.TrimSpace(k) == "interface" {
			return strings.TrimSpace(v), nil
		}
	}
	return "", errors.New("route: no interface line")
}

// ParseTherm reads `pmset -g therm`.
//
// A machine that is not throttling prints only "Note: ..." lines and no
// numbers at all, so absence of CPU_Speed_Limit means 100%, not an error.
func ParseTherm(out string) Thermal {
	t := Thermal{CPUSpeedLimitPercent: 100}
	sc := bufio.NewScanner(strings.NewReader(out))
	for sc.Scan() {
		k, v, ok := strings.Cut(strings.TrimSpace(sc.Text()), "=")
		if !ok {
			continue
		}
		if strings.TrimSpace(k) == "CPU_Speed_Limit" {
			if n, err := strconv.Atoi(strings.TrimSpace(v)); err == nil {
				t.CPUSpeedLimitPercent = n
			}
		}
	}
	t.Throttled = t.CPUSpeedLimitPercent < 100
	return t
}

var bootSec = regexp.MustCompile(`sec\s*=\s*(\d+)`)

// ParseBoottime reads `sysctl -n kern.boottime`:
// "{ sec = 1785096124, usec = 974297 } Sun Jul 26 13:02:04 2026".
func ParseBoottime(out string) (time.Time, error) {
	m := bootSec.FindStringSubmatch(out)
	if m == nil {
		return time.Time{}, fmt.Errorf("boottime: no sec field in %q", out)
	}
	sec, _ := strconv.ParseInt(m[1], 10, 64)
	return time.Unix(sec, 0), nil
}
