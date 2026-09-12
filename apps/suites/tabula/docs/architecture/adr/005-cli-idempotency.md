# ADR-005: TabCLI Command Idempotency

**Status:** Accepted  
**Date:** 2025-12-08  
**Deciders:** Tabula Core Team

## Context

As we automate more of our infrastructure and development workflows using `tabcli`, we need to
ensure that commands can be run safely in automated environments (CI/CD pipelines, setup scripts)
without requiring user intervention or causing errors if run multiple times.

Currently, some commands prompt for user confirmation or fail if resources already exist, which
hinders automation. For example, creating a project that already exists should not be a failure in a
setup script, and configuring an environment should not block on interactive prompts during a CI
run.

## Decision

All `tabcli` commands must be designed to be **idempotent**.

1.  **Re-runnable**: Running a command multiple times must have the same effect as running it once.
    It should not error if the desired state is already achieved.
    - _Example_: `tabcli infra setup` should succeed if the project already exists.
    - _Example_: `tabcli db init` should succeed if the database is already initialized.

2.  **Non-interactive Mode**: All commands that require user input must support flags (e.g.,
    `--force`, `--yes`, or specific value flags) to bypass prompts for automation.
    - _Example_: `tabcli dev setup --force` should overwrite configuration without prompting.

3.  **State Checking**: Commands should check the current state before attempting actions. If the
    resource exists or the state is already correct, the command should succeed (optionally logging
    that no action was needed).

## Consequences

### Positive

- **Robust Automation**: Enables reliable CI/CD pipelines and setup scripts.
- **Simplified Onboarding**: New developers can re-run setup scripts without fear of errors or
  duplicate resource creation.
- **Predictability**: The system converges to the desired state regardless of the starting state.

### Negative

- **Implementation Complexity**: Commands require additional logic to check state before acting.
- **Safety Risks**: The `--force` flag allows bypassing safety checks, which requires careful usage
  in production environments.
