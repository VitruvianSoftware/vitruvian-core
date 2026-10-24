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

load("@aspect_rules_py//py:defs.bzl", "py_binary", "py_library", "py_test")

# The files the catalog's part is written from, and the file it writes.
SITE_FILES = [
    "//:.claude-plugin/marketplace.json",
    "//apps/desktop/antigravity/plugins/ext-marketplace:site_sources",
    "//apps/desktop/antigravity/plugins/gh-watch:site_sources",
    "//apps/desktop/antigravity/plugins/hookify:site_sources",
    "//apps/desktop/antigravity/plugins/live-context:site_sources",
    "//apps/desktop/antigravity/plugins/ralph-loop:site_sources",
    "//apps/desktop/antigravity/plugins/receipts-report:site_sources",
    "//apps/desktop/antigravity/plugins/savvy-fleet:site_sources",
    "//apps/desktop/antigravity/plugins/security-guidance:site_sources",
    "//apps/desktop/antigravity/plugins/worktree-band:site_sources",
    "//apps/web/vitruviansoftware-dev:.claude-plugin/marketplace.json",
    "//apps/web/vitruviansoftware-dev:_data/extensions.yml",
    "//apps/web/vitruviansoftware-dev:_data/tools.yml",
    "//apps/web/vitruviansoftware-dev:ai/catalog.json",
    "//catalog:catalog.schema.json",
    "//catalog:public-key.txt",
    "//catalog:tools.json",
]

# The catalog's part alone, for //catalog:bump, which rewrites _data/tools.yml
# after it changes an entry.
py_library(
    name = "catalogue",
    srcs = ["catalogue.py"],
    imports = ["."],
    visibility = ["//catalog:__pkg__"],
)

py_binary(
    name = "sync",
    srcs = [
        "catalogue.py",
        "registry.py",
        "sync.py",
    ],
    imports = ["."],
    main = "sync.py",
)

# The committed copies are what sync.py writes from the SDK's files now. Not
# `manual` and not tied to macOS: plain Python, so the Linux lane runs it,
# whenever the guide, the protocol's README, a hello sample, the catalog or
# a copy changes.
py_test(
    name = "in_sync_test",
    size = "small",
    srcs = ["sync_test.py"],
    data = SITE_FILES + [
        "//apps/web/vitruviansoftware-dev:tools_pages",
        "//packages/vitruvian-sdk:release-please-config.json",
        "//packages/vitruvian-sdk:site_sources",
    ],
    main = "sync_test.py",
    deps = [":sync"],
)
