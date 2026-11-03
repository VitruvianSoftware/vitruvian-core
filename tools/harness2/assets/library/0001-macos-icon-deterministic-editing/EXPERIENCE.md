# 0001 macOS icon: deterministic editing of an existing image

Source: Antigravity conversation 7894ad88-4e79-4e6f-932f-15e3265842fb (2026-11-02), seeded by hand
from its transcript when Harness² was installed. One base trajectory; no edited harness has run yet.

<edits>
component: skills/macos-icon-edit (SKILL.md + scripts/icon_crop_scale.py)
candidates: seed
change: an on-demand skill and a standard-library script that measure the content box, strip a border colour, scale the artwork with sips and centre it on a transparent canvas
observed: without it the agent asked an image generator for a crop/border edit three times (steps 43, 456, 625) and hand-wrote a PNG decoder in about twenty one-off python3 -c commands (steps 754-815) because Pillow is not installed; the one result the user accepted (step 867) came from the deterministic path, sips at 824 on 1024 (step 812)
verdict: confounded
component: plugin hooks (pre-tool-use: write locks, INV-0001 generative refusal, loop guard)
candidates: seed
change: refuse writes to files the user locked, refuse image-generator while the request is a deterministic image edit, refuse an identical retry of a call that just failed
observed: after "DO NOT TOUCH THE NEW AppIcon-Default.png" (step 579) and "WITHOUT MODIFYING the image" (step 723) the constraints lived only in prose; the user had to ask for two reverts (steps 521, 561) after edits landed on the wrong file
verdict: no observed effect
component: rules/harness2-memory.md
candidates: seed
change: workspace facts: macOS icon grid 1024 canvas / 824 artwork; which Brand/ file is which; no Pillow, sips present
observed: the agent first scaled the artwork edge to edge at 1024 (step 808, user: "Did you enlarge it too much?"), then corrected to 824 (steps 812-828), which the user accepted
verdict: confounded
</edits>

<experience>
cue: the user asks to change the geometry of an existing image or icon (remove a border, crop, enlarge, scale, pad) rather than to create new artwork
lesson: route it to an on-demand skill whose script measures and transforms the existing pixels deterministically (C6 skill + C7 script), back it with a PreToolUse hook that refuses generative image tools for such requests (C8), and record the target grid as a workspace fact (macOS: 824 artwork on a 1024 canvas)
evidence: the skill row and the memory row; within the one trajectory, three generative attempts and an edge-to-edge 1024 scale were rejected by the user, and the deterministic 824-on-1024 result was accepted
confidence: medium – one conversation, but the contrast between the rejected generative path and the accepted deterministic path is direct and the user stated it explicitly
</experience>
