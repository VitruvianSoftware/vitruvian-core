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

package main

import (
	"context"
	"log"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/VitruvianSoftware/vitruvian-core/mobile/android/remote/macagent/metrics"
)

// This file is the ONLY place the agent executes anything.
//
// Every command has a fixed name and fixed arguments. Nothing from the
// network reaches an argv, there is no shell, and there is no code path that
// runs a command a request asked for. That is the whole security posture of
// this slice: a process that can read the machine and cannot change it, so
// the worst a reachable attacker gets is the same numbers Activity Monitor
// shows.

// cmdTimeout bounds the fast commands; anything past it is a wedged tool,
// not a slow one. top gets its own, longer bound: two samples take ~4 s at
// normal priority and 14-17 s if the process is ever demoted to background
// QoS, and a timeout that kills it produces a CPU that is never ready.
const (
	cmdTimeout = 10 * time.Second
	topTimeout = 30 * time.Second
)

func run(ctx context.Context, name string, args ...string) (string, error) {
	return runWithin(ctx, cmdTimeout, name, args...)
}

func runWithin(ctx context.Context, limit time.Duration, name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, limit)
	defer cancel()
	out, err := exec.CommandContext(ctx, name, args...).Output()
	return string(out), err
}

// Sampler keeps the latest reading and refreshes it in the background.
//
// Serving from a cache rather than sampling per request matters for one
// reason: a real CPU figure needs two top samples a second apart, which is
// far too slow to do inside an HTTP handler, and doing it per request would
// also let a client with a tight poll loop turn the agent into a CPU load of
// its own.
type Sampler struct {
	mu   sync.RWMutex
	snap metrics.Snapshot
	host metrics.Host

	interval time.Duration
	// The previous network counters, for the rate calculation.
	prevNet metrics.Network
	prevAt  time.Time
}

func NewSampler(interval time.Duration) *Sampler {
	return &Sampler{interval: interval}
}

func (s *Sampler) Snapshot() metrics.Snapshot {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.snap
}

func (s *Sampler) Host() metrics.Host {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.host
}

// Run blocks until ctx is cancelled. Two loops: the fast commands on the
// configured interval, and top on its own, because top paces itself and a
// single loop would either stall the fast readings behind it or fire top
// more often than it can answer.
func (s *Sampler) Run(ctx context.Context) {
	s.readHost(ctx)
	go s.cpuLoop(ctx)
	s.fastLoop(ctx)
}

func (s *Sampler) cpuLoop(ctx context.Context) {
	for ctx.Err() == nil {
		// -l 2: the first sample is the since-boot average; only the second
		// reflects the last second. -n 0: no process list. -s 1: one second
		// between samples.
		out, err := runWithin(ctx, topTimeout, "top", "-l", "2", "-n", "0", "-s", "1")
		if err != nil {
			log.Printf("top: %v", err)
			sleep(ctx, s.interval)
			continue
		}
		cpu, err := metrics.ParseTop(out)
		if err != nil {
			log.Printf("top: %v", err)
			sleep(ctx, s.interval)
			continue
		}
		s.mu.Lock()
		cpu.Load1, cpu.Load5, cpu.Load15 = s.snap.CPU.Load1, s.snap.CPU.Load5, s.snap.CPU.Load15
		cpu.Cores = s.host.Cores
		s.snap.CPU = cpu
		s.mu.Unlock()
	}
}

func (s *Sampler) fastLoop(ctx context.Context) {
	for ctx.Err() == nil {
		s.readFast(ctx)
		sleep(ctx, s.interval)
	}
}

func (s *Sampler) readFast(ctx context.Context) {
	now := time.Now()
	var next metrics.Snapshot

	freePct := 0
	if out, err := run(ctx, "sysctl", "-n", "kern.memorystatus_level"); err == nil {
		freePct, _ = strconv.Atoi(strings.TrimSpace(out))
	}
	if out, err := run(ctx, "vm_stat"); err == nil {
		if m, err := metrics.ParseVmStat(out, s.host.MemoryBytes, freePct); err == nil {
			next.Memory = m
		} else {
			log.Printf("vm_stat: %v", err)
		}
	}
	if out, err := run(ctx, "ioreg", "-r", "-c", "AppleSmartBattery", "-d", "1"); err == nil {
		next.Battery, _ = metrics.ParseBattery(out)
	}
	if out, err := run(ctx, "df", "-k", "/"); err == nil {
		if d, err := metrics.ParseDf(out, "/"); err == nil {
			next.Disk = d
		}
	}
	if out, err := run(ctx, "pmset", "-g", "therm"); err == nil {
		next.Thermal = metrics.ParseTherm(out)
	}
	if out, err := run(ctx, "sysctl", "-n", "kern.boottime"); err == nil {
		if bt, err := metrics.ParseBoottime(out); err == nil {
			next.UptimeSeconds = int64(now.Sub(bt).Seconds())
		}
	}
	iface := ""
	if out, err := run(ctx, "route", "-n", "get", "default"); err == nil {
		iface, _ = metrics.ParseDefaultInterface(out)
	}
	if iface != "" {
		// -n is load-bearing: without it netstat reverse-resolves every
		// address and takes ~5 s on a normal machine, which turned this
		// 2 s loop into a 7 s one and made every reading look stale. The
		// <Link#N> rows the parser uses carry no names anyway.
		if out, err := run(ctx, "netstat", "-ibn"); err == nil {
			if n, err := metrics.ParseNetstat(out, iface); err == nil {
				// Rate from the previous reading of the SAME interface. A
				// route flap to a different interface resets the baseline
				// rather than reporting a wild negative delta.
				if s.prevNet.Interface == iface && !s.prevAt.IsZero() {
					dt := now.Sub(s.prevAt).Seconds()
					if dt > 0 && n.RxBytes >= s.prevNet.RxBytes && n.TxBytes >= s.prevNet.TxBytes {
						n.RxBytesPerSec = float64(n.RxBytes-s.prevNet.RxBytes) / dt
						n.TxBytesPerSec = float64(n.TxBytes-s.prevNet.TxBytes) / dt
					}
				}
				s.prevNet, s.prevAt = n, now
				next.Network = n
			}
		}
	}

	// Stamped AFTER the commands, not before: the age a client sees must be
	// the age of the numbers, not the age of the moment we started asking.
	next.SampledAt = time.Now()
	next.Unavailable = unavailable

	s.mu.Lock()
	// CPU is owned by cpuLoop; carry the last reading across rather than
	// zeroing it every fast tick. Load averages are refreshed here.
	next.CPU = s.snap.CPU
	next.CPU.Load1, next.CPU.Load5, next.CPU.Load15 = s.parseLoad(ctx)
	s.snap = next
	s.mu.Unlock()
}

func (s *Sampler) parseLoad(ctx context.Context) (float64, float64, float64) {
	out, err := run(ctx, "sysctl", "-n", "vm.loadavg")
	if err != nil {
		return s.snap.CPU.Load1, s.snap.CPU.Load5, s.snap.CPU.Load15
	}
	l1, l5, l15, err := metrics.ParseLoadAvg(out)
	if err != nil {
		return s.snap.CPU.Load1, s.snap.CPU.Load5, s.snap.CPU.Load15
	}
	return l1, l5, l15
}

func (s *Sampler) readHost(ctx context.Context) {
	h := metrics.Host{AgentVersion: version}
	get := func(key string) string {
		out, err := run(ctx, "sysctl", "-n", key)
		if err != nil {
			return ""
		}
		return strings.TrimSpace(out)
	}
	h.Model = get("hw.model")
	h.Chip = get("machdep.cpu.brand_string")
	h.Cores, _ = strconv.Atoi(get("hw.ncpu"))
	h.MemoryBytes, _ = strconv.ParseUint(get("hw.memsize"), 10, 64)
	if out, err := run(ctx, "sw_vers", "-productVersion"); err == nil {
		h.OSVersion = strings.TrimSpace(out)
	}
	if out, err := run(ctx, "hostname", "-s"); err == nil {
		h.Hostname = strings.TrimSpace(out)
	}
	s.mu.Lock()
	s.host = h
	s.mu.Unlock()
}

// unavailable is the honest list. Each of these needs root (powermetrics) or
// an SMC reader that ships with neither macOS nor this agent. They are named
// so a client can render "not available" rather than a blank or a guess.
var unavailable = map[string]string{
	"soc_temperature_c": "needs root (powermetrics) or an SMC reader; the battery sensor is in battery.temperature_c",
	"fan_rpm":           "needs an SMC reader",
	"gpu_percent":       "needs root (powermetrics)",
	"ane_percent":       "needs root (powermetrics)",
	"soc_power_watts":   "needs root (powermetrics); ops/macos-power-agent pushes this to Prometheus",
}

func sleep(ctx context.Context, d time.Duration) {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
	case <-t.C:
	}
}
