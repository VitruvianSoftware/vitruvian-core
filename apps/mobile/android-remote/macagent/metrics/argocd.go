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
	"fmt"
	"sort"
	"time"
)

// The v1.2 ArgoCD reader: `kubectl get applications -A -o json`, which is
// two megabytes on the lab cluster and eight fields per app once the
// resource inventory is dropped. Dropping it here rather than on the phone
// is the point -- the phone is on a phone network.

// ArgoApp is one row of GET /v1/argocd.
type ArgoApp struct {
	Name       string    `json:"name"`
	Namespace  string    `json:"namespace"`
	Project    string    `json:"project"`
	Sync       string    `json:"sync"`
	Health     string    `json:"health"`
	Revision   string    `json:"revision"`
	LastSynced time.Time `json:"last_synced"`
	Message    string    `json:"message"`
}

// ArgoApps is the body of GET /v1/argocd.
type ArgoApps struct {
	Available bool      `json:"available"`
	Reason    string    `json:"reason"`
	Apps      []ArgoApp `json:"apps"`
}

// ParseArgoApps reads the Application list.
//
// Sorted by name so a phone diffing two polls sees only real changes:
// kubectl's own order is the API server's, which is stable in practice and
// not promised.
func ParseArgoApps(out string) ([]ArgoApp, error) {
	var list struct {
		Items []struct {
			Metadata struct {
				Name      string `json:"name"`
				Namespace string `json:"namespace"`
			} `json:"metadata"`
			Spec struct {
				Project string `json:"project"`
			} `json:"spec"`
			Status struct {
				Sync struct {
					Status   string `json:"status"`
					Revision string `json:"revision"`
				} `json:"sync"`
				Health struct {
					Status string `json:"status"`
				} `json:"health"`
				ReconciledAt   string `json:"reconciledAt"`
				OperationState struct {
					Message    string `json:"message"`
					FinishedAt string `json:"finishedAt"`
				} `json:"operationState"`
			} `json:"status"`
		} `json:"items"`
	}
	if err := json.Unmarshal([]byte(out), &list); err != nil {
		return nil, fmt.Errorf("kubectl get applications: %w", err)
	}
	apps := make([]ArgoApp, 0, len(list.Items))
	for _, it := range list.Items {
		a := ArgoApp{
			Name:      it.Metadata.Name,
			Namespace: it.Metadata.Namespace,
			Project:   it.Spec.Project,
			Sync:      it.Status.Sync.Status,
			Health:    it.Status.Health.Status,
			Revision:  shortRevision(it.Status.Sync.Revision),
			Message:   it.Status.OperationState.Message,
		}
		// The end of the last sync operation is what "last synced" means. An
		// app ArgoCD has only ever reconciled -- adopted, never synced by an
		// operation -- has no finishedAt, and reconciledAt is the nearest
		// true thing rather than a zero that renders as 1970.
		ts := it.Status.OperationState.FinishedAt
		if ts == "" {
			ts = it.Status.ReconciledAt
		}
		if t, err := time.Parse(time.RFC3339, ts); err == nil {
			a.LastSynced = t
		}
		apps = append(apps, a)
	}
	sort.Slice(apps, func(i, j int) bool { return apps[i].Name < apps[j].Name })
	return apps, nil
}

// shortRevision is the first eight characters of a git SHA. Not every
// revision IS a SHA: a Helm source records a chart version like "0.23.2",
// which is shorter than eight and must come back whole rather than panic on
// the slice.
func shortRevision(rev string) string {
	if len(rev) <= 8 {
		return rev
	}
	return rev[:8]
}
