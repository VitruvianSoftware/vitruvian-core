# Tools

## Overview
Component package providing implementation for `apps/desktop/vitruvian/Tools`.

## Interface
- `[ByHand.swift:Exit]`
- `[ByHand.swift:Control]`
- `[ByHand.swift:Key]`
- `[ByHandRules.swift:ByHandRules]`
- `[uninstall.sh:script entrypoint]`

## Invariants
- None

## Side Effects
- [ReleaseFeedCheck.swift:49]: `URLSession.shared.dataTask(with: request) { _, response, _ in`
- [ReleaseFeedCheck.swift:89]: `URLSession.shared.dataTask(with: request) { data, _, _ in`
- [ReleaseFeedCheck.swift:114]: `log.add(request, "HTTP \(reply.status), \(reply.body.count) bytes\(length)")`
- [ToolFixture.swift:31]: `// and no attribute, as a script's `&` or Python's `subprocess` starts one,`
- [uninstall.sh:25]: `# Written by URLSession on the app's behalf, so they exist without the app ever`

## Verification
- Run: `bazel test //apps/desktop/vitruvian/Tools/...`
