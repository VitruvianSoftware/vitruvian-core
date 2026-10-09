# Shared examples

Some rules exist twice: once in the bot (JavaScript, `../src`) and once in the
library the Mac apps share (Swift, `../macos/Sources/NexusAgentCore`). The files
here are one set of examples for those rules. Both sides' tests read them, so
changing a rule on one side fails the other side's tests.

| File | The rule |
|---|---|
| `archive-annotations.json` | which Antigravity annotation text marks a conversation archived |

## Who reads them

- `../src/shared-cases.test.js` runs every case through the bot's own code.
- `../macos/Tests/SharedCasesTests.swift` runs the same cases through the
  shared Swift library, which the standalone app and the Vitruvian desktop app
  are both built from.

Each test fails if a file is missing or has no cases, and neither skips a case.

## The bot is the authority

The bot is what actually runs. When the two sides disagree, the apps change to
show and write what the bot will do. The expected values here come from
running the bot's code, not from reading it.

## Adding a case

Add it here, not in one language's test. Run the bot's code on the input to
get the expected value, then run both tests:

```
bazel test //apps/desktop/nexus-agent/src:shared_cases_test
bazel test --config=macos-app //apps/desktop/nexus-agent/macos:NexusAgentTests
```

Every file has the same shape: `{ "rule": "<one sentence>", "cases": [ { "name": "<plain words>", ... } ] }`.
