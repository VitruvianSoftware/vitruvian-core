# pkg/vpc_service_controls — Vpc Service Controls

Creates VPC Service Controls access policies, access levels, and service perimeters (regular and bridge).

## Installation

```bash
go get github.com/VitruvianSoftware/pulumi-library/go/pkg/vpc_service_controls
```

```go
import "github.com/VitruvianSoftware/pulumi-library/go/pkg/vpc_service_controls"
```

## Interface
- `[vpc_sc.go:GetDefaultRestrictedServices]`
- `[vpc_sc.go:VpcServiceControlsArgs]`
- `[vpc_sc.go:VpcServiceControls]`
- `[vpc_sc.go:NewVpcServiceControls]`

## Invariants
- None

## Side Effects
- [vpc_sc.go:8]: `*      http://www.apache.org/licenses/LICENSE-2.0`

## Verification
- Run: `bazel test //packages/pulumi/library/go/pkg/vpc_service_controls/...`
