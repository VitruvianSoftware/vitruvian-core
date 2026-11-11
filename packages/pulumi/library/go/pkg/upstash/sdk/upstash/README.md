# Upstash

## Overview
Component package providing implementation for `packages/pulumi/library/go/pkg/upstash/sdk/upstash`.

## Interface
- `[getQstashEndpointData.go:GetQstashEndpointData]`
- `[getQstashEndpointData.go:GetQstashEndpointDataArgs]`
- `[getQstashEndpointData.go:GetQstashEndpointDataResult]`
- `[getQstashEndpointData.go:GetQstashEndpointDataOutput]`
- `[getQstashEndpointData.go:GetQstashEndpointDataOutputArgs]`
- `[getQstashEndpointData.go:ElementType]`
- `[getQstashEndpointData.go:GetQstashEndpointDataResultOutput]`
- `[getQstashEndpointData.go:ElementType]`
- `[getQstashEndpointData.go:ToGetQstashEndpointDataResultOutput]`
- `[getQstashEndpointData.go:ToGetQstashEndpointDataResultOutputWithContext]`
- `[getQstashEndpointData.go:EndpointId]`
- `[getQstashEndpointData.go:Id]`
- `[getQstashEndpointData.go:TopicId]`
- `[getQstashEndpointData.go:Url]`
- `[getQstashScheduleData.go:GetQstashScheduleData]`
- `[getQstashScheduleData.go:GetQstashScheduleDataArgs]`
- `[getQstashScheduleData.go:GetQstashScheduleDataResult]`
- `[getQstashScheduleData.go:GetQstashScheduleDataOutput]`
- `[getQstashScheduleData.go:GetQstashScheduleDataOutputArgs]`
- `[getQstashScheduleData.go:ElementType]`
- Subdirectory: [config](./config/README.md)
- Subdirectory: [internal](./internal/README.md)

## Invariants
- None

## Side Effects
- [qstashScheduleV2.go:36]: `// Method of Http Request on QStash`
- [qstashScheduleV2.go:107]: `// Method of Http Request on QStash`
- [qstashScheduleV2.go:135]: `// Method of Http Request on QStash`
- [search.go:24]: `// The number of maximum query operations you can perform in a day. Only quer...`
- [search.go:30]: `// The number of maximum query operations you can perform per second. Only qu...`
- [search.go:32]: `// The number of maximum vectors in a read operation. Query and fetch operati...`
- [vectorIndex.go:26]: `// The number of maximum query operations you can perform in a day. Only quer...`
- [vectorIndex.go:32]: `// The number of maximum query operations you can perform per second. Only qu...`
- [vectorIndex.go:34]: `// The number of maximum vectors in a read operation. Query and fetch operati...`

## Verification
- Run: `bazel test //packages/pulumi/library/go/pkg/upstash/sdk/upstash/...`
