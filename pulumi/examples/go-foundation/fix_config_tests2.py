import os

mock_tmpl = """/*
 * Copyright 2026 Vitruvian Software
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 */

package main

import (
\t"os"
\t"testing"

\t"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
\t"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
\t"github.com/stretchr/testify/assert"
)

type mocks int

func (mocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
\treturn args.Name + "_id", args.Inputs, nil
}

func (mocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
\treturn args.Args, nil
}
"""

envs_test = mock_tmpl + """
func TestDeployEnvBaseline(t *testing.T) {
\tos.Setenv("PULUMI_CONFIG", `{"project:org_id":"123", "project:billing_account":"123", "project:org_stack_name":"org-stack"}`)
\tdefer os.Unsetenv("PULUMI_CONFIG")

\terr := pulumi.RunErr(func(ctx *pulumi.Context) error {
\t\tcfg := loadEnvConfig(ctx)
\t\tassert.Equal(t, "org-stack", cfg.OrgStackName)
\t\treturn nil
\t}, pulumi.WithMocks("project", "stack", mocks(0)))
\tassert.NoError(t, err)
}
"""

app_test = mock_tmpl + """
func TestAppConfigDefaultsReal(t *testing.T) {
\tos.Setenv("PULUMI_CONFIG", `{"project:env":"development"}`)
\tdefer os.Unsetenv("PULUMI_CONFIG")

\terr := pulumi.RunErr(func(ctx *pulumi.Context) error {
\t\tcfg := loadAppInfraConfig(ctx)

\t\tassert.Equal(t, "development", cfg.Env)
\t\tassert.Equal(t, "bu1", cfg.BusinessCode)

\t\treturn nil
\t}, pulumi.WithMocks("project", "stack", mocks(0)))
\tassert.NoError(t, err)
}
"""

with open('2-environments/config_test.go', 'w') as f: f.write(envs_test)
with open('5-app-infra/config_test.go', 'w') as f: f.write(app_test)

