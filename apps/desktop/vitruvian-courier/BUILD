# Copyright 2026 VitruvianSoftware
# SPDX-License-Identifier: AGPL-3.0-or-later

# Inter-app boundary (#82): default targets to vitruvian-courier-internal
# visibility so other apps cannot depend on its internals.
package(default_visibility = ["//apps/desktop/vitruvian-courier:__subpackages__"])

# The mirror's Sponsor button. The stripe stack's donations_pages_test.go
# checks it opens a donate page that a Payment Link backs.
exports_files(
    [".github/FUNDING.yml"],
    visibility = ["//infrastructure/pulumi/platform/stripe:__pkg__"],
)
