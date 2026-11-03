---
name: harness2
description: Improve this agent's own harness from past conversations (Harness², arXiv:2610.14224) with Claude Opus as the editor, and manage per-conversation file locks.
---

# Harness²

Harness² improves how you work by editing this plugin (`~/.gemini/config/plugins/harness2/`)
from evidence: a conversation's transcript. Claude Opus plays the paper's roles: an INV editor
(how the agent works), a DOM editor (what a practitioner knows), a composer that merges them,
and an experience reflector that writes one transferable lesson to the library.

## Commands (run with run_command)

- `harness2 status` – installed hooks, active locks, library entries.
- `harness2 distill <conversation-id> --apply` – learn from a conversation (default: the
  newest). Without `--apply` it proposes only; `harness2 apply <run-dir>` adopts a proposal.
  Takes several minutes: run it in the background and tell the user it is running.
- `harness2 probe "<task>" [--workspace <dir>] --apply` – before a task: Claude solves it on
  paper and adds whatever your harness is missing for it.
- `harness2 lock <conversation-id> <file> [--no-generative-image] [--size 1024x1024]` and
  `harness2 unlock <conversation-id> [<file>]` – manage a conversation's hard constraints.
- `harness2 validate` – the structural rules every harness change must pass.
- `harness2 library` – the lessons learned so far.

Your conversation id is the folder name under `~/.gemini/antigravity/brain/` for this chat.

## When the user asks how to make you smarter

Say what failed in plain words, then offer `harness2 distill <this conversation> --apply`.
Do not hand-edit this plugin's rules yourself: distill validates every change first.
