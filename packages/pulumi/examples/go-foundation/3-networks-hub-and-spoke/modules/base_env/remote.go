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

// remote.go mirrors upstream 3-networks-hub-and-spoke/modules/base_env/
// remote.tf.
//
// Pulumi-port note: the cross-stage reads happen at the leaf roots — the hub
// host project is read from the 1-org StackReference in envs/<env>/remote.go
// and passed in via Args.HubProjectID, and the ACM policy id is resolved
// inside modules/shared_vpc (service_control.go) — a documented engine
// adaptation. No StackReferences are declared in this module.
package base_env
