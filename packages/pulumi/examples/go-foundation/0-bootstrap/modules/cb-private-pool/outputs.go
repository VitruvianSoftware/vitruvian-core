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

// Mirrors: 0-bootstrap/modules/cb-private-pool/outputs.tf in the TF
// foundation — the module's output surface, exposed as fields on the
// CbPrivatePool component resource.

package cbprivatepool

import (
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// CbPrivatePool is the component resource mirroring upstream
// 0-bootstrap/modules/cb-private-pool.
type CbPrivatePool struct {
	pulumi.ResourceState

	// PrivateWorkerPoolID mirrors upstream output "private_worker_pool_id".
	PrivateWorkerPoolID pulumi.StringOutput
	// WorkerRangeID mirrors upstream output "worker_range_id" ("" when
	// peering is disabled).
	WorkerRangeID pulumi.StringOutput
	// WorkerPeeredIPRange mirrors upstream output "worker_peered_ip_range".
	WorkerPeeredIPRange pulumi.StringOutput
	// PeeredNetworkID mirrors upstream output "peered_network_id".
	PeeredNetworkID pulumi.StringOutput
}
