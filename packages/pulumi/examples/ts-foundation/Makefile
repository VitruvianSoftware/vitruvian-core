# Copyright 2026 Vitruvian Software
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

.PHONY: lint build test validate clean

STAGES := 0-bootstrap 1-org 2-environments/envs/development 2-environments/envs/nonproduction 2-environments/envs/production \
	3-networks-hub-and-spoke/envs/development 3-networks-hub-and-spoke/envs/nonproduction 3-networks-hub-and-spoke/envs/production 3-networks-hub-and-spoke/envs/shared \
	3-networks-svpc/envs/development 3-networks-svpc/envs/nonproduction 3-networks-svpc/envs/production 3-networks-svpc/envs/shared \
	4-projects/business_unit_1/development 4-projects/business_unit_1/nonproduction 4-projects/business_unit_1/production 4-projects/business_unit_1/shared \
	5-app-infra/business_unit_1/development 5-app-infra/business_unit_1/nonproduction 5-app-infra/business_unit_1/production

# Lint all stages (TypeScript compile check)
lint:
	@for stage in $(STAGES); do \
		echo "=== Compiling $$stage ===" ; \
		cd $$stage && npx tsc --noEmit && cd $(CURDIR) ; \
	done

# Build (install + compile)
build: install lint

# Run unit tests
test:
	npx vitest run

# Run unit tests with coverage
test-coverage:
	npx vitest run --coverage

# Install root and stage dependencies
install:
	npm install
	@for stage in $(STAGES); do \
		echo "=== Installing $$stage ===" ; \
		cd $$stage && npm install && cd $(CURDIR) ; \
	done

# Pre-flight environment validation
validate:
	@echo "Usage: ./scripts/validate-requirements.sh -o <ORG_ID> -b <BILLING_ACCOUNT> -u <USER_EMAIL>"
	@./scripts/validate-requirements.sh $(ARGS)

# Clean build artifacts
clean:
	@find . -name 'node_modules' -type d -prune -exec rm -rf {} + 2>/dev/null || true
	@find . -name 'dist' -type d -prune -exec rm -rf {} + 2>/dev/null || true
	@find . -name '*.js' -not -name 'jest.config.js' -type f -delete 2>/dev/null || true
	@find . -name '*.js.map' -type f -delete 2>/dev/null || true
	@find . -name '*.d.ts' -type f -delete 2>/dev/null || true
	@echo "Cleaned build artifacts."
