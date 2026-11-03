# Harness² for Antigravity

Antigravity keeps making the same kind of mistake in a conversation even after you correct it.
Harness² fixes the harness around the model instead of hoping the model gets smarter. It does
two things:

1. **Live hooks** read your messages and enforce what you said. If you say "do not touch X", writes
   to X are refused. If you ask to crop, scale or strip a border from an existing image, image
   generators are refused and the agent is pointed at a deterministic script. If a tool call
   just failed, the identical call is refused rather than retried blind. Lessons learned from
   earlier conversations are pinned right before the model's turn when your message matches them.
2. **`harness2 distill`** has Claude Opus read a finished conversation and edit Antigravity's
   harness: it adds a skill, a script, a hook rule or (last resort) a line of always-on text.
   Each change must pass a validator before it is adopted, and each run writes one lesson to a
   library that later conversations draw on.

It follows *Harness²: Recursive Agent Harnessing for an Open World* (arXiv:2610.14224). The
prompts are the paper's Appendix H, adapted to Antigravity's file layout.

```
 your message ──► PreInvocation hook ──► locks + matched lessons pinned ──► model turn
                                                                              │
                     PreToolUse hook  ◄────────────── each tool call ◄─────────┘
                     (refuse locked writes, generators on pixel edits, blind retries)
                                                                              │
                     Stop hook ◄───────────────────────── end of turn ◄────────┘
                     (locked file changed? declared image size wrong? → one more pass)

 later:  harness2 distill <conversation> --apply
         INV editor ─┐
                     ├─► composer ─► validator (retry once) ─► plugin updated
         DOM editor ─┘                                     └─► reflector ─► library entry
```

## Use

```sh
bazel run //tools/harness2 -- install      # once, and after pulling changes to this folder
harness2 status                            # what is installed, locked and learned
harness2 distill <conversation-id>         # propose harness changes from a conversation (newest if omitted)
harness2 apply <run-dir>                   # adopt a proposal (or pass --apply to distill)
harness2 probe "resize the app icon" --workspace ~/Workspace/... --apply
harness2 lock <conversation-id> AppIcon-Default.png --no-generative-image
harness2 validate                          # the four rules, on the installed harness and library
```

The conversation id is the folder name under `~/.gemini/antigravity/brain/`. A distill runs
four Claude Opus sessions, each in its own folder under `~/.gemini/antigravity/harness2/runs/`,
and takes several minutes.

## Safety: the transcript is untrusted

A conversation's transcript includes tool output, web pages and file contents, so it can carry
instructions someone planted. Distill is built on that assumption:

- **Each Claude session is confined.** It gets exactly five tools (`--tools
  Read,Edit,Write,Glob,Grep`), may edit only inside its own run folder and read only there
  (plus `--workspace` for `probe`, read-only). No shell, web, subagents, scheduling, remote
  triggers or MCP servers; no user settings or plugins; tokens stripped from the environment.
  Checked live: the session lists only those five tools, and writes outside its folder and
  reads of other files are refused.
- **Hook rules can only ask or refuse.** The validator rejects any hookify rule not named
  `harness2-*`, any action other than warn/block, and any extra key (no argument rewriting).
- **A person adopts changes.** `distill` only proposes. Read `harness.diff`, then run
  `harness2 apply`. The hooks refuse the agent's own attempts to run `harness2 apply`,
  `--apply`, `--reseed` or `unlock`, and any edit of the harness's own files (both plugins,
  `hookify-rules.json`, `~/.gemini/antigravity/harness2/`). `distill --apply` is for you to
  use by hand: it prints the diff and asks before adopting (`--yes` skips the question).
- **Install never merges hook rules from a harness that fails validation.**
- **Adoption is all-or-nothing.** The new plugin is assembled and validated beside the live one
  and swapped in with two renames; the previous plugin is kept whole in the run folder, and any
  failure puts it back exactly.
- **No symlinks** in a proposal, and the event log never records tool output.

## What gets installed

| Where | What |
|---|---|
| `~/.gemini/config/plugins/harness2/` | The plugin. `hooks/` + `lib/` are code and are refreshed on every install. `rules/`, `skills/`, `scripts/`, `sub_agents/`, `guardrails.json`, `hookify-rules.json` are the **harness** distill edits; install only seeds them when missing (`--reseed` overwrites, after a backup) |
| `~/.gemini/config/plugins/hookify/` | Copied from `apps/desktop/antigravity/plugins/hookify` if not already installed |
| `~/.gemini/config/config.json` | `harness2` and `hookify` set to enabled; every other key kept; backed up first |
| `~/.gemini/antigravity/hookify-rules.json` | The harness's `harness2-*` rules merged in; your other rules kept |
| `~/.gemini/antigravity/harness2/` | `state/` (per-conversation locks), `library/` (lessons + adopted trees), `runs/`, `events.jsonl`, `hooks.log` |
| `~/.local/bin/harness2` | Wrapper that runs the installed CLI |

## The validator (paper Appendix H)

A proposal that breaks any rule is rejected whole:

1. Every skill has a trigger line in always-on text (`When <situation>, load the `<name>` skill.`)
   and frontmatter whose `name:` matches its folder.
2. No template braces in always-on text.
3. Every script a skill or rule names exists and compiles; helpers live in the skill's `scripts/`.
4. Always-on text stays under 8,000 characters (about 2,000 tokens), because every word of it is
   paid on every model call.

## Limits

- The hooks fail **open**: if Python is missing or crashes, PreToolUse answers allow (logged to
  `hooks.log`). A hook that blocked everything when broken would be worse.
- Constraint extraction is pattern matching on your words, not understanding. It catches "do not
  touch X", "leave X alone", "without modifying", crop/scale/border requests and corrections;
  phrasing outside those patterns is missed. `harness2 lock` sets the same state by hand.
- The shell side of the file lock recognises common writes (redirection into the file, `cp`/`mv`
  onto it, `rm`, `sips`, `sed -i`, `find -delete`, Python `open(..., 'w')`/`shutil`/`os.remove`,
  `git checkout`/`restore`). A determined command in another language can still get through;
  the Stop check then flags the changed file.
- The check on the harness's own files reads paths as written in the command, so a relative
  path after `cd` into the plugin folder gets past it. It is a guard that fails open, not a
  security boundary; `harness2 validate` and the run folder's backups are the backstop.
- The distill sessions cannot run code, so an editor cannot test a script it writes; the
  validator only checks that it compiles.
- An explicit ask to generate ("use nano banana to…") is respected: the image-generator block
  only applies when the request is an edit of existing pixels.
- The paper rolls out each candidate harness before composing. There is no benchmark runner here,
  so the composer and reflector work from the one base conversation; the prompts say so, and the
  reflector is told to prefer `confounded` over invented credit.
- Antigravity's exact PreInvocation payload field for your message is not documented; the hook
  reads `lastUserInput` (and a few aliases) and falls back to the transcript's last user message.
