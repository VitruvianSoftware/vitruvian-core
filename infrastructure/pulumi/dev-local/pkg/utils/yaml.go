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

package utils

import (
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

// LoadHelmValues loads values from a YAML file in the values directory
func LoadHelmValues(valuesFile string) (map[string]interface{}, error) {
	// If no values file is specified, return an empty map
	if valuesFile == "" {
		return map[string]interface{}{}, nil
	}

	// Construct the path to the values file
	valuesPath := filepath.Join("values", valuesFile+".yaml")

	// Check if the file exists
	if _, err := os.Stat(valuesPath); os.IsNotExist(err) {
		fmt.Printf("Warning: Values file %s does not exist, using default values\n", valuesPath)
		return map[string]interface{}{}, nil
	}

	// Read the file
	data, err := ioutil.ReadFile(valuesPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read values file %s: %w", valuesPath, err)
	}

	// Parse the YAML
	var values map[string]interface{}
	err = yaml.Unmarshal(data, &values)
	if err != nil {
		return nil, fmt.Errorf("failed to parse values file %s: %w", valuesPath, err)
	}

	return values, nil
}

// MergeValues merges two maps of values, with the override map taking precedence
func MergeValues(base, override map[string]interface{}) map[string]interface{} {
	result := make(map[string]interface{})

	// Copy base values
	for k, v := range base {
		result[k] = v
	}

	// Apply overrides
	for k, v := range override {
		// If both are maps, merge them recursively
		if baseMap, ok := result[k].(map[string]interface{}); ok {
			if overrideMap, ok := v.(map[string]interface{}); ok {
				result[k] = MergeValues(baseMap, overrideMap)
				continue
			}
		}
		// Otherwise, just override
		result[k] = v
	}

	return result
}
