# gazelle:ignore

# Inter-app boundary (#82): default targets to vitruvian-relay-internal
# visibility so other apps cannot depend on its internals.
package(default_visibility = ["//apps/suites/vitruvian-relay:__subpackages__"])

# Makes this folder a package so MODULE.bazel can name :Cargo.toml and
# :Cargo.lock for the @vitruvian_relay_crates hub.
exports_files([
    "Cargo.lock",
    "Cargo.toml",
])
