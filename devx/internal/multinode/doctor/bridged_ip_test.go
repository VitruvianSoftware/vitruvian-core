package doctor

import "testing"

// isBridgedIP must reject Lima's user-mode (slirp) 192.168.5.0/24 — that's the
// fallback GetBridgedIP returns when no real socket_vmnet bridge (lima0) exists.
func TestIsBridgedIP(t *testing.T) {
	cases := map[string]bool{
		"192.168.86.58":  true, // real LAN bridge (socket_vmnet)
		"192.168.86.200": true,
		"10.4.0.7":       true,  // any non-user-mode address
		"192.168.5.15":   false, // Lima user-mode (slirp) — NOT a bridge
		"192.168.5.2":    false,
		"":               false,
	}
	for ip, want := range cases {
		if got := isBridgedIP(ip); got != want {
			t.Errorf("isBridgedIP(%q) = %v, want %v", ip, got, want)
		}
	}
}
