# Proto

## Overview
Component package providing implementation for `apps/desktop/courier/gchat/proto`.

## Interface
- `[googlechat.proto:UserType]`
- `[googlechat.proto:UserId]`
- `[googlechat.proto:User]`
- `[googlechat.proto:UserBlockRelationship]`
- `[googlechat.proto:DndSettings]`
- `[googlechat.proto:Emoji]`
- `[googlechat.proto:CustomStatus]`
- `[googlechat.proto:UserStatus]`
- `[googlechat.proto:UserStatusUpdatedEvent]`
- `[googlechat.proto:GetUserStatusRequest]`
- `[googlechat.proto:GetUserStatusResponse]`
- `[googlechat.proto:GetSelfUserStatusRequest]`
- `[googlechat.proto:GetSelfUserStatusResponse]`
- `[googlechat.proto:ClientFeatureCapabilities]`
- `[googlechat.proto:RequestHeader]`
- `[googlechat.proto:InviteCategory]`
- `[googlechat.proto:Member]`
- `[googlechat.proto:MemberId]`
- `[googlechat.proto:MembershipId]`
- `[googlechat.proto:Membership]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/courier/gchat/proto/...`
