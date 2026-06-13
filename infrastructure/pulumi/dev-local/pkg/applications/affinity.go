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

package applications

// hostnameAntiAffinity renders a hard (required) podAntiAffinity stanza as a
// chart-values map, forcing pods that match the given labels onto distinct
// nodes. Multi-replica workloads without it can co-locate by scheduler chance,
// turning a single node loss into a full outage
// (docs/infrastructure/resilience-catalog.md).
func hostnameAntiAffinity(matchLabels map[string]interface{}) map[string]interface{} {
	return map[string]interface{}{
		"podAntiAffinity": map[string]interface{}{
			"requiredDuringSchedulingIgnoredDuringExecution": []interface{}{
				map[string]interface{}{
					"labelSelector": map[string]interface{}{
						"matchLabels": matchLabels,
					},
					"topologyKey": "kubernetes.io/hostname",
				},
			},
		},
	}
}
