# Changelog

All notable changes to the vitruvian-orchestrator OpenCode plugin are recorded here.

## [0.2.1](https://github.com/VitruvianSoftware/vitruvian-core/compare/vitruvian-orchestrator-opencode-v0.2.0...vitruvian-orchestrator-opencode-v0.2.1) (2026-11-22)


### Features

* **vitruvian-orchestrator-opencode:** publish the OpenCode plugin to npm, with its agents and skills in one entry ([#5332](https://github.com/VitruvianSoftware/vitruvian-core/issues/5332)) ([1504e55](https://github.com/VitruvianSoftware/vitruvian-core/commit/1504e55fd6464937705b2d4c3de72cb427e9e187))

## 0.2.0

* Generic plugin: a team file (`.agents/team.json`) maps roles to your own agents, every role has a generic agent that works without one, and `team_setup` writes a starter team file or syncs its model settings into your agent files.
* Installable from npm as `@vitruviansoftware/opencode-vitruvian-orchestrator`: one entry in `opencode.json` loads the tools, the sidebar, the agents and the skills.
