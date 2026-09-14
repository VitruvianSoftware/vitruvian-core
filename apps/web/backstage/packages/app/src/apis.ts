// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import {
  ScmIntegrationsApi,
  scmIntegrationsApiRef,
  ScmAuth,
} from "@backstage/integration-react";
import {
  AnyApiFactory,
  configApiRef,
  createApiFactory,
} from "@backstage/core-plugin-api";

export const apis: AnyApiFactory[] = [
  createApiFactory({
    api: scmIntegrationsApiRef,
    deps: { configApi: configApiRef },
    factory: ({ configApi }) => ScmIntegrationsApi.fromConfig(configApi),
  }),
  // Backs scmAuthApiRef, which the GitHub Actions plugin uses to call the
  // GitHub API as the signed-in user.
  //
  // NOTE ON SCOPE: ScmAuth.forGithub requests `repo read:org read:user`. `repo`
  // is broad -- read/write on every repository the user can reach, private
  // included -- so users see that on the consent screen the first time they
  // open a CI/CD tab. It is kept at the upstream default deliberately: this org
  // has private repositories, and narrowing to `public_repo` would work today
  // and then fail silently the first time a private repo is added to the
  // catalog, which is a far worse failure mode than a broad-but-visible scope.
  //
  // To narrow it anyway (only safe while every catalogued repo is public):
  //   ScmAuth.forAuthApi(githubAuthApi, {
  //     host: "github.com",
  //     scopeMapping: { default: ["public_repo", "read:org", "read:user"] },
  //   })
  ScmAuth.createDefaultApiFactory(),
];
