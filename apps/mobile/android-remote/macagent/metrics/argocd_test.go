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
	"os"
	"testing"
)

// testdata/argocd-apps.json is two apps out of the 52 on the lab cluster,
// captured 2026-09-07 with
//
//	kubectl --kubeconfig ~/.kube/cluster.yaml --context default \
//	  get applications -A -o json
//
// and cut to the fields this parser reads. The full response is 2 MB, nearly
// all of it the per-app resource inventory, which is exactly what the agent
// drops before anything reaches a phone network.

func TestParseArgoAppsOnRealApplications(t *testing.T) {
	b, err := os.ReadFile("testdata/argocd-apps.json")
	if err != nil {
		t.Fatal(err)
	}
	apps, err := ParseArgoApps(string(b))
	if err != nil {
		t.Fatal(err)
	}
	if len(apps) != 2 {
		t.Fatalf("got %d apps: %+v", len(apps), apps)
	}
	a := apps[0]
	if a.Name != "alertmanager-ntfy-bridge" || a.Namespace != "argocd" || a.Project != "platform-project" {
		t.Errorf("identity: %+v", a)
	}
	if a.Sync != "Synced" || a.Health != "Healthy" {
		t.Errorf("status: %+v", a)
	}
	if a.Revision != "8da57d77" {
		t.Errorf("revision = %q, want the first 8 chars of the SHA", a.Revision)
	}
	if a.Message != "successfully synced (all tasks run)" {
		t.Errorf("message = %q", a.Message)
	}
	if a.LastSynced.IsZero() {
		t.Error("last_synced did not parse")
	}
	// A Helm source records a chart VERSION as its revision, which is
	// shorter than eight characters. Slicing it blind panics; this pins that
	// it comes back whole.
	if apps[1].Revision != "0.23.2" {
		t.Errorf("short revision was mangled: %q", apps[1].Revision)
	}
}

func TestParseArgoAppsEdges(t *testing.T) {
	// No Applications at all -- a cluster without ArgoCD installed answers
	// with an empty list, which is zero apps rather than a failure.
	apps, err := ParseArgoApps(`{"apiVersion":"v1","kind":"List","items":[]}`)
	if err != nil || len(apps) != 0 {
		t.Errorf("empty list: %v %v", apps, err)
	}
	// An app ArgoCD has reconciled but never run a sync operation on has no
	// operationState.finishedAt. reconciledAt is the nearest true thing; a
	// zero time renders on the phone as 1970.
	one := `{"items":[{"metadata":{"name":"adopted","namespace":"argocd"},"spec":{"project":"default"},
	  "status":{"sync":{"status":"OutOfSync","revision":"abcdef1234567890"},"health":{"status":"Degraded"},
	  "reconciledAt":"2026-09-07T20:10:11Z"}}]}`
	apps, err = ParseArgoApps(one)
	if err != nil || len(apps) != 1 {
		t.Fatalf("%v %v", apps, err)
	}
	if apps[0].LastSynced.IsZero() {
		t.Error("with no finishedAt, last_synced must fall back to reconciledAt")
	}
	if apps[0].Sync != "OutOfSync" || apps[0].Health != "Degraded" {
		t.Errorf("an unhealthy app: %+v", apps[0])
	}
	// kubectl's own error text is not JSON; it must be an error rather than
	// an empty list that reads as "nothing deployed".
	if _, err := ParseArgoApps(`error: the server doesn't have a resource type "applications"`); err == nil {
		t.Error("a kubectl error must not parse as zero apps")
	}
}

func TestParseArgoAppsSortsByName(t *testing.T) {
	// kubectl's order is the API server's and is not promised. Without a
	// sort, a phone diffing two polls sees churn that is not there.
	raw := `{"items":[
	  {"metadata":{"name":"zebra","namespace":"argocd"},"spec":{},"status":{}},
	  {"metadata":{"name":"alpha","namespace":"argocd"},"spec":{},"status":{}}]}`
	apps, err := ParseArgoApps(raw)
	if err != nil {
		t.Fatal(err)
	}
	if apps[0].Name != "alpha" || apps[1].Name != "zebra" {
		t.Errorf("not sorted: %+v", apps)
	}
}
