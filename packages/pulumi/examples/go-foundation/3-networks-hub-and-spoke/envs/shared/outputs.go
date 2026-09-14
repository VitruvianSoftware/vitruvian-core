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

// outputs.go mirrors upstream 3-networks-hub-and-spoke/envs/shared/outputs.tf.
//
// Pulumi-port note: the hub stack exports (shared_vpc_host_project_id,
// network_name, dns_policy) are emitted by the shared_vpc module in hub mode
// (modules/shared_vpc, hub branch of New) so the export values can be built
// next to the resources they reference — a documented engine adaptation that
// keeps this leaf a thin orchestrator. No additional exports are declared
// here.
package main
