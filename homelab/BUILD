# gazelle:prefix github.com/VitruvianSoftware/homelab

# Inter-app boundary (#82): targets in this package default to homelab-internal
# visibility so other top-level apps can't depend on homelab internals. Each
# internal/* package already sets explicit //homelab:__subpackages__; this marks
# the boundary at the app root for consistency and future root-package targets.
package(default_visibility = ["//homelab:__subpackages__"])
