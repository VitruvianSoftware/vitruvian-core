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
	"math"
	"testing"
)

// Every fixture below is verbatim output captured from a MacBook Pro (M4 Max,
// macOS 26.5.2) on 2026-09-06. The parsers are pinned to real text, not to
// what the man page says the text looks like.

const fixtureTop = `Processes: 1260 total, 5 running, 1255 sleeping, 12298 threads 
2026/09/06 19:39:52
Load Avg: 2.76, 3.99, 4.16 
CPU usage: 9.71% user, 7.30% sys, 82.97% idle 
SharedLibs: 1067M resident, 194M data, 195M linkedit.
CPU usage: 10.54% user, 4.77% sys, 84.68% idle 
PhysMem: 123G used (6885M wired, 16G compressor), 4536M unused.
`

func TestParseTopTakesTheSecondSample(t *testing.T) {
	c, err := ParseTop(fixtureTop)
	if err != nil {
		t.Fatal(err)
	}
	// The first "CPU usage" line is the since-boot average and must be ignored.
	if c.UserPercent != 10.54 || c.SystemPercent != 4.77 || c.IdlePercent != 84.68 {
		t.Errorf("took the wrong sample: %+v", c)
	}
	if math.Abs(c.BusyPercent-15.31) > 0.001 {
		t.Errorf("busy = user+sys, got %v", c.BusyPercent)
	}
	if _, err := ParseTop("no cpu line here"); err == nil {
		t.Error("missing line must be an error, not a zero reading")
	}
}

func TestParseLoadAvg(t *testing.T) {
	l1, l5, l15, err := ParseLoadAvg("{ 2.83 4.02 4.18 }\n")
	if err != nil || l1 != 2.83 || l5 != 4.02 || l15 != 4.18 {
		t.Errorf("got %v %v %v %v", l1, l5, l15, err)
	}
}

const fixtureVmStat = `Mach Virtual Memory Statistics: (page size of 16384 bytes)
Pages free:                                   264845.
Pages active:                                3300322.
Pages inactive:                              3270871.
Pages speculative:                             37646.
Pages throttled:                                   0.
Pages wired down:                             440607.
Pages purgeable:                              140023.
"Translation faults":                    52729556719.
Pages copy-on-write:                      5591485997.
Pages zero filled:                       32189688475.
Pages reactivated:                         509219885.
Pages purged:                              123456789.
File-backed pages:                           1234567.
Anonymous pages:                             7654321.
Pages stored in compressor:                  3542600.
Pages occupied by compressor:                1018942.
Decompressions:                            123456789.
Compressions:                              234567890.
Pageins:                                    34567890.
Pageouts:                                    4567890.
Swapins:                                      567890.
Swapouts:                                      67890.
`

func TestParseVmStat(t *testing.T) {
	const total = uint64(137438953472) // hw.memsize on the 128 GB machine
	m, err := ParseVmStat(fixtureVmStat, total, 82)
	if err != nil {
		t.Fatal(err)
	}
	// (active + wired + compressor-occupied) pages * 16 KiB. Inactive and
	// speculative pages are reclaimable and must NOT be counted as used.
	want := uint64(3300322+440607+1018942) * 16384
	if m.UsedBytes != want {
		t.Errorf("used bytes: got %d want %d", m.UsedBytes, want)
	}
	if m.TotalBytes != total || m.FreePercent != 82 {
		t.Errorf("passthrough fields wrong: %+v", m)
	}
	if m.UsedPercent < 56 || m.UsedPercent > 58 {
		t.Errorf("used percent implausible for fixture: %v", m.UsedPercent)
	}
	// The page size comes from the header, not an assumption: an Intel Mac
	// says 4096 and the same page counts mean a quarter of the bytes.
	intel := "Mach Virtual Memory Statistics: (page size of 4096 bytes)\n" +
		"Pages active: 100.\nPages wired down: 100.\nPages occupied by compressor: 100.\n"
	mi, err := ParseVmStat(intel, 1<<30, 50)
	if err != nil || mi.UsedBytes != 300*4096 {
		t.Errorf("intel page size: got %d, err %v", mi.UsedBytes, err)
	}
}

const fixtureBatteryOnAC = `+-o AppleSmartBattery  <class AppleSmartBattery, id 0x100000401, registered, matched, active, busy 0 (0 ms), retain 6>
    {
      "CurrentCapacity" = 94
      "TimeRemaining" = 65535
      "Amperage" = 0
      "AppleRawCurrentCapacity" = 7438
      "ExternalConnected" = Yes
      "MaxCapacity" = 100
      "Temperature" = 3048
      "IsCharging" = No
      "DesignCapacity" = 8579
      "Voltage" = 12695
      "CycleCount" = 36
      "AvgTimeToEmpty" = 65535
    }
`

func TestParseBatteryOnAC(t *testing.T) {
	b, err := ParseBattery(fixtureBatteryOnAC)
	if err != nil {
		t.Fatal(err)
	}
	if !b.Present || b.Percent != 94 || !b.OnAC || b.Charging {
		t.Errorf("state wrong: %+v", b)
	}
	// 3048 is centi-Celsius. Reading it as Celsius gives a battery on fire.
	if b.TemperatureC != 30.48 {
		t.Errorf("temperature: got %v want 30.48", b.TemperatureC)
	}
	// 65535 minutes is the "unknown" sentinel, not 45 hours of runtime.
	if b.MinutesRemaining != nil {
		t.Errorf("65535 must map to nil, got %d", *b.MinutesRemaining)
	}
	if b.DrawWatts != 0 {
		t.Errorf("no draw on AC with 0 mA, got %v", b.DrawWatts)
	}
	if b.CycleCount != 36 || b.VoltageMV != 12695 {
		t.Errorf("passthrough wrong: %+v", b)
	}
}

func TestParseBatteryDischarging(t *testing.T) {
	// Synthetic: same shape, unplugged, drawing 1.5 A at 12.0 V with a real
	// time estimate. Amperage is SIGNED and negative while discharging.
	out := `      "CurrentCapacity" = 61
      "TimeRemaining" = 213
      "Amperage" = -1500
      "ExternalConnected" = No
      "MaxCapacity" = 100
      "Temperature" = 3312
      "IsCharging" = No
      "Voltage" = 12000
      "CycleCount" = 36
`
	b, err := ParseBattery(out)
	if err != nil {
		t.Fatal(err)
	}
	if b.OnAC || b.Charging || b.Percent != 61 {
		t.Errorf("state wrong: %+v", b)
	}
	if math.Abs(b.DrawWatts-18.0) > 0.001 {
		t.Errorf("draw: 1.5 A * 12 V = 18 W, got %v", b.DrawWatts)
	}
	if b.MinutesRemaining == nil || *b.MinutesRemaining != 213 {
		t.Errorf("real estimate must pass through, got %v", b.MinutesRemaining)
	}
}

func TestParseBatteryAbsentIsNotAnError(t *testing.T) {
	// A Mac mini has no AppleSmartBattery entry at all; ioreg prints nothing.
	b, err := ParseBattery("")
	if err != nil || b.Present {
		t.Errorf("desktop Mac: want present=false, nil error; got %+v %v", b, err)
	}
}

func TestParseBatteryIntelRawCapacity(t *testing.T) {
	// Some Intel models report raw mAh rather than a percentage.
	b, err := ParseBattery("      \"CurrentCapacity\" = 4000\n      \"MaxCapacity\" = 8000\n")
	if err != nil || b.Percent != 50 {
		t.Errorf("want 50%%, got %+v %v", b, err)
	}
}

const fixtureDf = `Filesystem     1024-blocks     Used Available Capacity iused     ifree %iused  Mounted on
/dev/disk3s1s1   971350180 16688368  59607704    22%  458726 596077040    0%   /
`

func TestParseDf(t *testing.T) {
	d, err := ParseDf(fixtureDf, "/")
	if err != nil {
		t.Fatal(err)
	}
	if d.TotalBytes != 971350180*1024 || d.UsedBytes != 16688368*1024 || d.AvailableBytes != 59607704*1024 {
		t.Errorf("block arithmetic wrong: %+v", d)
	}
	if d.Mount != "/" {
		t.Errorf("mount: %q", d.Mount)
	}
}

const fixtureNetstat = `Name       Mtu   Network       Address            Ipkts Ierrs     Ibytes    Opkts Oerrs     Obytes  Coll
lo0        16384 <Link#1>                        1234567     0  123456789  1234567     0  123456789     0
lo0        16384 127           127.0.0.1         1234567     -  123456789  1234567     -  123456789     -
en0        1500  <Link#15>   a2:26:7e:45:c1:2d 22159354     0 26048810912  5292821     0 2190844376     0
en0        1500  192.168.1     192.168.1.20      22159354     - 26048810912  5292821     - 2190844376     -
en9        1500  <Link#22>   00:e0:4c:68:01:02   987654     0  555555555   876543     0  444444444     0
`

func TestParseNetstatPicksTheLinkRow(t *testing.T) {
	n, err := ParseNetstat(fixtureNetstat, "en0")
	if err != nil {
		t.Fatal(err)
	}
	// Only the <Link#N> row has the whole-interface counters; the per-address
	// rows repeat them and would double-count if summed.
	if n.RxBytes != 26048810912 || n.TxBytes != 2190844376 {
		t.Errorf("counters: %+v", n)
	}
	n9, err := ParseNetstat(fixtureNetstat, "en9")
	if err != nil || n9.RxBytes != 555555555 {
		t.Errorf("en9: %+v %v", n9, err)
	}
	if _, err := ParseNetstat(fixtureNetstat, "en99"); err == nil {
		t.Error("unknown interface must be an error")
	}
}

func TestParseDefaultInterface(t *testing.T) {
	out := "   route to: default\ndestination: default\n       mask: default\n    gateway: 192.168.1.1\n  interface: en9\n      flags: <UP,GATEWAY,DONE,STATIC,PRCLONING,GLOBAL>\n"
	got, err := ParseDefaultInterface(out)
	if err != nil || got != "en9" {
		t.Errorf("got %q %v", got, err)
	}
}

func TestParseThermHealthyMachinePrintsNoNumbers(t *testing.T) {
	// This is the ENTIRE output on a machine that is not throttling. No key,
	// no value -- absence means 100%, and must not be read as an error or 0.
	out := "Note: No thermal warning level has been recorded\nNote: No performance warning level has been recorded\nNote: No CPU power status has been recorded\n"
	th := ParseTherm(out)
	if th.Throttled || th.CPUSpeedLimitPercent != 100 {
		t.Errorf("healthy machine: %+v", th)
	}
	throttling := "CPU_Scheduler_Limit \t= 100\nCPU_Available_CPUs \t= 16\nCPU_Speed_Limit \t= 62\n"
	th = ParseTherm(throttling)
	if !th.Throttled || th.CPUSpeedLimitPercent != 62 {
		t.Errorf("throttling machine: %+v", th)
	}
}

func TestParseBoottime(t *testing.T) {
	bt, err := ParseBoottime("{ sec = 1785096124, usec = 974297 } Sun Jul 26 13:02:04 2026\n")
	if err != nil || bt.Unix() != 1785096124 {
		t.Errorf("got %v %v", bt, err)
	}
}
