# savvy-fleet: subagent fleet telemetry & savvy-flow orchestration

`savvy-fleet` tracks every subagent you launch with `invoke_subagent` and messages sent with `send_message`, combining hook events with live conversation transcript telemetry.

- When orchestrating multi-step or multi-domain work, follow the `savvy-flow` skill (`Plan` → `Design` → `Delegate` → `Review` → `Close`) and assign each task a complexity tier (`fable`, `heavy`, `careful`, `medium`, `light`) and a domain specialist (`beacon`, `wren`, `atlas`, `ridge`, `scout`, `aegis`, `quill`).
- Include a clear `Role` (e.g. `[careful] K3s NetworkPolicy Audit`) when calling `invoke_subagent` so the Savvy Fleet panel can classify the worker's tier and match it against planned tasks.
- Surface a one-click pill to open the panel when delegating parallel subagents: `[Savvy Fleet](sidecar://savvy-fleet/panel/)`.
