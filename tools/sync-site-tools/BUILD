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

"""The Tools section of vitruviansoftware.dev, copied from packages/vitruvian-sdk.

    bazel run //tools/sync-site-tools:sync    writes the copies
"""

# gazelle:ignore

load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_test")

py_binary(
    name = "sync",
    srcs = ["sync.py"],
    main = "sync.py",
)

# The committed copies are what sync.py writes from the SDK's files now. Not
# `manual` and not tied to macOS: plain Python, so the Linux lane runs it,
# whenever the guide, the protocol's README, a hello sample or a copy changes.
py_test(
    name = "in_sync_test",
    size = "small",
    srcs = ["sync.py"],
    args = ["--check"],
    data = [
        "//apps/web/vitruviansoftware-dev:tools_pages",
        "//packages/vitruvian-sdk:site_sources",
    ],
    main = "sync.py",
)
