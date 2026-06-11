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

"node_image macro for OCI containers (sibling of go_image / py3_image)"

load("@aspect_rules_js//js:defs.bzl", "js_image_layer")
load("@rules_oci//oci:defs.bzl", "oci_image", "oci_load")

def node_image(name, binary, root = "/app", env = {}, workdir = None, base = "@nodejs_base"):
    """Create a Node.js image from a js_binary.

    js_image_layer splits the binary's runfiles into cacheable layers (node
    toolchain / third-party package store / first-party packages /
    node_modules links / app) and generates a container-suitable launcher.

    Args:
        name: The name of the image.
        binary: The js_binary to create the image from.
        root: The root directory where everything will be put into.
        env: The environment variables to set in the image.
        workdir: The working directory; defaults to the runfiles tree root,
            which is what js_binary's chdir/runfiles resolution expects.
        base: The base image (needs a shell for the js_binary launcher).
    """
    binary_label = native.package_relative_label(binary)
    binary_path = "{}/{}/{}".format(root, binary_label.package, binary_label.name)
    runfiles_dir = "{}.runfiles".format(binary_path)
    repo_name = binary_label.repo_name or "_main"

    js_image_layer(
        name = name + "_layers",
        binary = binary,
        platform = select({
            "@platforms//cpu:arm64": "//tools/platforms:linux_aarch64",
            "@platforms//cpu:x86_64": "//tools/platforms:linux_x86_64",
        }),
        root = root,
    )

    oci_image(
        name = name,
        base = base,
        entrypoint = [binary_path],
        env = env,
        tars = [name + "_layers"],
        workdir = workdir or "{}/{}".format(runfiles_dir, repo_name),
    )

    oci_load(
        name = name + ".load",
        image = name,
        repo_tags = [
            native.package_name() + ":latest",
        ],
    )
