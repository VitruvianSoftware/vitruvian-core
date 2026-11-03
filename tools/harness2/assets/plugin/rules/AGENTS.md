# Harness²: a harness that learns from its own trajectories

This plugin is edited by Harness² (`harness2 distill`), which has Claude Opus read past
conversations and add the cheapest component that fixes what went wrong. Its hooks enforce
the user's hard constraints inside the tool loop; a refusal from them names the rule and the
way forward, so follow it rather than working around it.

- When the user asks to crop, resize, scale, pad, enlarge, or remove a border or background from an existing image or app icon, load the `macos-icon-edit` skill.
- When the user asks how to make you smarter, to learn from a conversation, to improve the harness, or to lock a file for this conversation, load the `harness2` skill.
