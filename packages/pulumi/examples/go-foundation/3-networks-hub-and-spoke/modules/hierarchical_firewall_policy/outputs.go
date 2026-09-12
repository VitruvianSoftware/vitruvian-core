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

// outputs.go mirrors upstream 3-networks-hub-and-spoke/modules/
// hierarchical_firewall_policy/outputs.tf.
//
// Pulumi-port note: the policy id/rule outputs are encapsulated by the
// library HierarchicalFirewallPolicy component and are not consumed by any
// caller in this port, so New returns only an error — a documented engine
// adaptation.
package hierarchical_firewall_policy
