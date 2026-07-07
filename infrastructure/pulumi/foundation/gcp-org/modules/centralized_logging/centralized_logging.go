/*
 * Copyright 2026 Vitruvian Software
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Package centralized_logging is a local module that delegates to the
// centralized logging library (pkg/logging). Mirrors the Terraform
// foundation's 1-org/modules/centralized-logging structure.
package centralized_logging

// This local module exists for structural parity with the Terraform foundation.
// The actual implementation is in github.com/VitruvianSoftware/pulumi-library/go/pkg/logging
// which is imported directly by the 1-org main.go.
