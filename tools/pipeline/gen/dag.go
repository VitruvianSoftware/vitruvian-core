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
	"fmt"
	"sort"
)

// DAG manages dependency resolution and topological sort for pipeline units.
type DAG struct {
	Units    map[string]Unit
	AdjList  map[string][]string // unit -> dependents (downstream)
	InDegree map[string]int      // unit -> number of unsatisfied dependencies (upstream)
}

// BuildDAG constructs a DAG graph and validates that all dependency edges are satisfied and cycle-free.
func BuildDAG(units []Unit) (*DAG, error) {
	dag := &DAG{
		Units:    make(map[string]Unit, len(units)),
		AdjList:  make(map[string][]string),
		InDegree: make(map[string]int),
	}

	for _, u := range units {
		dag.Units[u.Name] = u
		dag.InDegree[u.Name] = 0
	}

	// Validate all dependencies exist and build adjacency
	for _, u := range units {
		for _, dep := range u.DependsOn {
			if _, exists := dag.Units[dep]; !exists {
				return nil, fmt.Errorf("unit %q depends on non-existent unit %q", u.Name, dep)
			}
			dag.AdjList[dep] = append(dag.AdjList[dep], u.Name)
			dag.InDegree[u.Name]++
		}
	}

	// Verify cycle-free via Topological Sort
	if _, err := dag.TopologicalOrder(); err != nil {
		return nil, err
	}

	return dag, nil
}

// TopologicalOrder returns units in topological dependency order with deterministic alphabetical tie-breaking.
func (d *DAG) TopologicalOrder() ([]Unit, error) {
	inDegree := make(map[string]int, len(d.Units))
	for k, v := range d.InDegree {
		inDegree[k] = v
	}

	var queue []string
	for name, deg := range inDegree {
		if deg == 0 {
			queue = append(queue, name)
		}
	}
	sort.Strings(queue)

	var ordered []Unit
	visitedCount := 0

	for len(queue) > 0 {
		curr := queue[0]
		queue = queue[1:]
		ordered = append(ordered, d.Units[curr])
		visitedCount++

		for _, neighbor := range d.AdjList[curr] {
			inDegree[neighbor]--
			if inDegree[neighbor] == 0 {
				queue = append(queue, neighbor)
			}
		}
		sort.Strings(queue)
	}

	if visitedCount != len(d.Units) {
		return nil, fmt.Errorf("cyclic dependency detected among pipeline units")
	}

	return ordered, nil
}
