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

// remote.go mirrors upstream 3-networks-hub-and-spoke/envs/shared/remote.tf.
//
// Pulumi-port note: the cross-stage reads live where they are consumed — the
// hub host project comes from stack config (hub_project_id), and the 1-org
// StackReference (ACM policy id, net-hub project number) is read inside
// modules/shared_vpc (service_control.go, hub path) — a documented engine
// adaptation. No StackReferences are declared at this leaf.
package main
