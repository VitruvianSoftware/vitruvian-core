# vitruvian-orchestrator: live orchestration telemetry

When orchestrating multi-domain work with the `orchestrate` skill (`plan` → `design` → `delegate` → `review` → `close`):

- **Lead `progress` updates**: Call the `progress` MCP tool:
  - Right after creating or revising the numbered task plan (`title`, `phase: "plan"`, `tasks: [{ title, specialist, tier, after }]`).
  - On each phase transition (`phase: "design" | "delegate" | "review" | "close"`).
  - After each review verdict (`accept: <task_number>` or `return: <task_number>`).
  - When closing the flow (`phase: "close"`, `finished: true`).
- **Task matching on dispatch**: When calling `invoke_subagent`, pass the planned task's exact `title` as `Role` so the Orchestrator panel matches the subagent run to the task board entry.
- **Worker `step` updates**: Instruct worker subagents to call the `step` MCP tool (`{ done, total, note }`) as they complete milestones in their task brief.
- **Live panel pill**: Offer a one-click pill to open the Orchestrator sidecar panel when presenting the plan or delegating subagents: `[Orchestrator](sidecar://vitruvian-orchestrator/panel/)`.
