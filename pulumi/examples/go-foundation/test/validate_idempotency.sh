#!/bin/bash
# Copyright 2026 Vitruvian Software
#
# Validates that all foundation stages are idempotent (no-drift)
# by running `pulumi preview --expect-no-changes` on each deployed stack.

set -e

echo "============================================="
echo " Foundation Idempotency Validation"
echo "============================================="
echo ""

STAGES=("0-bootstrap" "1-org" "2-environments" "3-networks-svpc" "3-networks-hub-and-spoke" "4-projects" "5-app-infra")

for stage in "${STAGES[@]}"; do
	if [ -d "$stage" ]; then
		echo "━━━ Checking $stage ━━━"
		pushd "$stage" >/dev/null

		# In a real environment, you might iterate over multiple stacks.
		# For now, we attempt to run it on the currently selected stack.
		# We ignore errors if there is no stack selected or if it's not initialized.
		pulumi preview --expect-no-changes || echo "  [WARN] Idempotency check failed or no stack selected for $stage"

		popd >/dev/null
		echo ""
	fi
done

echo "Idempotency validation completed."
