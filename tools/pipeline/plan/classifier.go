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
	"path/filepath"
	"strings"
)

// ClassifyPersonaAndOperation deterministically maps a list of changed file paths to a persona and operation.
func ClassifyPersonaAndOperation(files []string, isDocsOnly, isGlobalImpact bool) (Persona, Operation) {
	if isDocsOnly {
		return PersonaDocsAuthor, OperationDocsOnly
	}
	if isGlobalImpact {
		return PersonaPlatformAdmin, OperationGlobalConfig
	}

	var hasFrontend, hasBackend, hasInfra, hasMigration, hasDepUpdate, hasPlatform bool

	for _, f := range files {
		clean := filepath.ToSlash(f)
		clean = strings.TrimPrefix(clean, "./")
		clean = strings.TrimPrefix(clean, "/")
		ext := filepath.Ext(clean)

		if strings.Contains(clean, "/migrations/") || strings.HasSuffix(clean, ".sql") || strings.Contains(clean, "prisma/schema.prisma") {
			hasMigration = true
		}
		if clean == "pnpm-lock.yaml" || clean == "go.mod" || clean == "go.sum" || clean == "requirements.txt" || clean == "MODULE.bazel.lock" {
			hasDepUpdate = true
		}

		if strings.HasPrefix(clean, "infrastructure/") ||
			strings.HasPrefix(clean, "pulumi/") ||
			strings.HasPrefix(clean, "tools/pulumi/") ||
			strings.HasPrefix(clean, "tools/cloud-bootstrap/") ||
			strings.Contains(clean, "/infra/") ||
			ext == ".bu" || ext == ".tf" {
			hasInfra = true
		} else if strings.HasPrefix(clean, "packages/design-system/") ||
			strings.HasPrefix(clean, "tabula/web/") ||
			strings.HasPrefix(clean, "tabula/extension/") ||
			strings.HasPrefix(clean, "backstage/packages/app/") ||
			ext == ".tsx" || ext == ".jsx" || ext == ".css" || ext == ".scss" {
			hasFrontend = true
		} else if strings.HasPrefix(clean, "tools/") || strings.HasPrefix(clean, ".github/") {
			hasPlatform = true
		} else if strings.HasPrefix(clean, "tabula/api/") ||
			strings.HasPrefix(clean, "tabula/cli/") ||
			strings.HasPrefix(clean, "devx/") ||
			strings.HasPrefix(clean, "homelab/") ||
			strings.HasPrefix(clean, "mcp-slack/") ||
			strings.HasPrefix(clean, "oauth-user-inspector/") ||
			strings.HasPrefix(clean, "backstage/packages/backend/") ||
			ext == ".go" || ext == ".py" || ext == ".rs" {
			hasBackend = true
		}
	}

	// Classify Persona
	count := 0
	if hasFrontend {
		count++
	}
	if hasBackend {
		count++
	}
	if hasInfra {
		count++
	}
	if hasPlatform {
		count++
	}

	var persona Persona
	if count > 1 {
		persona = PersonaFullStackDev
	} else if hasFrontend {
		persona = PersonaFrontendDev
	} else if hasBackend {
		persona = PersonaBackendDev
	} else if hasInfra {
		persona = PersonaInfraEng
	} else if hasPlatform {
		persona = PersonaPlatformAdmin
	} else {
		persona = PersonaBackendDev
	}

	// Classify Operation
	var operation Operation
	if hasMigration {
		operation = OperationDatabaseMigration
	} else if hasDepUpdate {
		operation = OperationDepUpdate
	} else if count > 1 {
		operation = OperationMultiDiscipline
	} else if hasFrontend {
		operation = OperationUIFeature
	} else if hasBackend {
		operation = OperationBackendAPI
	} else if hasInfra {
		operation = OperationInfraProvision
	} else {
		operation = OperationBackendAPI
	}

	return persona, operation
}
