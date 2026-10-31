# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

"""The oauth-user-inspector candidate smoke command, defined once.

//tools/deploy:cloud-run runs a custom smoke with `bash -c` from wherever it
was started -- under `bazel run` that is its runfiles tree, outside any
workspace -- so the command enters the checkout before calling Bazel.
Shared by :deploy and the delivery unit (infra/app/BUILD) and by
//apps/web/oauth-user-inspector:deploy_smoke_test, which runs it through the
real deploy tool.
"""

OAUTH_SMOKE = 'cd "${BUILD_WORKSPACE_DIRECTORY:?the oauth smoke runs under bazel run}" && bazel run //apps/web/oauth-user-inspector:smoke'
