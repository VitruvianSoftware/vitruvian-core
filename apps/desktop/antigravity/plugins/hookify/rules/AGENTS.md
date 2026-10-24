# hookify: declarative hook guardrails

The `hookify` plugin evaluates declarative rules on every `PreToolUse` and
`Stop` event from two sources:

1. **Workspace Markdown rules:** `.agents/hookify.<rule-name>.md` in the
   current repository.
2. **Global JSON rules:** `~/.gemini/antigravity/hookify-rules.json` managed by
   the Hookify side panel.

## How to respond when a Hookify rule triggers

- **Blocked tool call (`deny`):** Read the rule reason returned by the hook,
  adjust your command or file edit so it complies with the guardrail, and do
  not attempt to bypass or delete `.agents/hookify.*.md` unless the user
  explicitly asks you to change the rule.
- **Rewritten input (`overwrite`):** Hookify automatically rewrote the tool
  arguments to a safer or canonical form; continue with the rewritten call.
- **Blocked stop (`continue: false`):** Complete the missing verification step
  named in the stop reason before finishing your turn.
- **Authoring rules:** When the user asks to create or update a guardrail rule,
  load the `hookify` skill (`skills/hookify/SKILL.md`) for the exact YAML
  frontmatter schema, supported operators, and actions.
