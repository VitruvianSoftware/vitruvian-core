package cloud_dns

import "testing"

func TestGetZoneName(t *testing.T) {
	if GetZoneName() != "vitruvian-zone" {
		t.Fail()
	}
}
