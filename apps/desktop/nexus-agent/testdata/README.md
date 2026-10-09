# Shared examples

Some rules exist twice: once in the bot (JavaScript, `../src`) and once in the
library the Mac apps share (Swift, `../macos/Sources/NexusAgentCore`). The files
here are one set of examples for those rules. Both sides' tests read them, so
changing a rule on one side fails the other side's tests.

| File | The rule |
|---|---|
| `archive-annotations.json` | which Antigravity annotation text marks a conversation archived |
| `approval-modes.json` | which agy permission flags an `AGY_APPROVAL_MODE` value gives; `null` is the absent key |
| `env-lines.json` | what one line of `.env` assigns, as the bot's `dotenv` reads it; `null` key and value mean nothing |
| `env-files.json` | what a whole `.env` file assigns, as `dotenv` reads it; a line ends only at `\n`, `\r` or `\r\n`, so a file's line endings and look-alike characters (U+2028, form feed) change nothing |
| `env-written-values.json` | the text the apps write after the `=` for a value, which `dotenv` must read back as that value |

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

For `.env`, "the bot" means the `dotenv` package it loads the file with: the
bot's test runs each line through `dotenv.parse`.

## What is not here

- **Values that run over several lines.** `dotenv` reads a quoted value that
  continues on the next line, and lets the value start on the line after the
  `=`. The apps read `.env` one line at a time and cannot do that, so
  `env-lines.json` holds single lines only. The apps never write such a value:
  they remove line breaks before writing.
- **Values no spelling can carry.** A case in `env-written-values.json` marked
  `"lossy": true` is a value that cannot be written on one line so that
  `dotenv` reads it back: a `#` together with every quote character that could
  have protected it. Both tests assert the bot reads something different for
  it, so the limit stays visible. If a spelling is found, those assertions
  fail and the mark comes off.

## Adding a case

Add it here, not in one language's test. Run the bot's code on the input to
get the expected value, then run both tests:

```
bazel test //apps/desktop/nexus-agent/src:shared_cases_test
bazel test --config=macos-app //apps/desktop/nexus-agent/macos:NexusAgentTests
```

Every file has the same shape: `{ "rule": "<one sentence>", "cases": [ { "name": "<plain words>", ... } ] }`.
