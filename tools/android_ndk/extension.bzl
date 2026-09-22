"""A hermetic Android NDK, pinned by checksum.

rules_android_ndk resolves the NDK from ANDROID_NDK_HOME on the machine. That
makes the C++ half of an APK build depend on whatever each developer and each
CI runner happens to have installed -- the GitHub images ship 27.3.13750724,
a developer is likely on whatever `sdkmanager` last fetched -- which is the
dependency @llvm_toolchain exists to avoid for every other language here.

So this fetches a pinned archive instead and hands rules_android_ndk that path.
`path` wins over the environment variable, so ANDROID_NDK_HOME is ignored even
when it is set.

Upgrading: change _NDK_VERSION and both checksums together. Google publishes
SHA-1 in https://dl.google.com/android/repository/repository2-3.xml, not the
SHA-256 http_archive wants, so the honest route is to download the archive,
confirm it against the published SHA-1, and hash the verified bytes. The
values below were produced that way.
"""

load("@rules_android_ndk//:rules.bzl", "android_ndk_repository")

_NDK_VERSION = "r29"

_ARCHIVES = {
    "darwin": struct(
        sha256 = "ce5e4b100ec5fe5be4eb3edcb2c02528824ff9cda3860f5304619be6c3da34d3",
        url = "https://dl.google.com/android/repository/android-ndk-r29-darwin.zip",
    ),
    "linux": struct(
        sha256 = "4abbbcdc842f3d4879206e9695d52709603e52dd68d3c1fff04b3b5e7a308ecf",
        url = "https://dl.google.com/android/repository/android-ndk-r29-linux.zip",
    ),
}

def _host_key(module_ctx):
    name = module_ctx.os.name.lower()
    if name.startswith("mac"):
        return "darwin"
    if name.startswith("linux"):
        return "linux"

    # Windows ships an archive too, but nothing here builds Android on it and
    # an untested entry is worse than a clear refusal.
    fail("hermetic NDK: unsupported host OS %r (darwin and linux only)" % name)

def _impl(module_ctx):
    archive = _ARCHIVES[_host_key(module_ctx)]

    # The download happens inside the repository rule, which is the only place
    # Bazel lets one write. Upstream rules_android_ndk has no `url`, so the
    # repo carries a patch adding it -- see
    # third_party/rules_android_ndk/hermetic_ndk.patch for why the alternatives
    # do not work.
    android_ndk_repository(
        name = "androidndk",
        sha256 = archive.sha256,
        strip_prefix = "android-ndk-" + _NDK_VERSION,
        url = archive.url,
    )

hermetic_android_ndk = module_extension(implementation = _impl)
