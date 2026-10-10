# Shared examples

Some rules exist twice: once in the bot (JavaScript, `../src`) and once in the
library the Mac apps share (Swift, `../macos/Sources/NexusAgentCore`). The files
here are one set of examples for those rules. Both sides' tests read them, so
changing a rule on one side fails the other side's tests.

| File | The rule |
|---|---|
| `archive-annotations.json` | which Antigravity annotation text marks a conversation archived |
| `approval-modes.json` | which agy permission flags an `AGY_APPROVAL_MODE` value gives; `null` is the absent key |
| `agy-flags.json` | which flags a whole `.env` gives agy after the prompt and the format: permission, model, then effort. The effort line is passed on as written, and a thinking line counts only when there is no effort to go by |
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

For `agy-flags.json` it means the bot started the way it starts: its modules
loaded in a fresh process, over a folder holding the example's `.env`.

## Where the apps do not follow the bot

One difference is kept on purpose, and `agy-flags.json` records it instead of
hiding it. The bot loads `.env` with `dotenv`, which never replaces a variable
that is already set in the bot's process: there the process wins over the
file, even when the variable is set to nothing. The Mac apps read the bot's
settings from `.env` alone and never from their own process environment. They
are started from the Dock or at login, so their environment is not the bot's
and nobody sets it on purpose; reading it would let a stray variable change how
an agent is run with nothing in Settings to show for it.

So a case with an `environment` (variables set before the bot starts) has two
answers: `args` is what the bot passes and the bot's test checks, `apps` is
what the apps pass and the apps' test checks. A case without one has `args`
only, and both sides must give it. In practice the two can only part ways for
a bot that is started by hand, or by a service, with one of its settings
exported: the apps then show and run what the file says, and that bot runs
what its environment says.

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
