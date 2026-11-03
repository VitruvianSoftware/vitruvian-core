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
"""`swift_test` for this repository: rules_swift's, kept out of ~/Library/Preferences.

Load this instead of `@build_bazel_rules_swift//swift:swift_test.bzl`. It links
:test_preferences into the test, which opens every UserDefaults suite the test
uses, and `UserDefaults.standard`, in a container under the test's temporary
directory (see test_preferences.c). `bazel run //tools/conformance:check` fails
a BUILD file that loads the upstream rule directly.
"""

load("@build_bazel_rules_swift//swift:swift_test.bzl", _swift_test = "swift_test")

def swift_test(name, deps = [], **kwargs):
    """A rules_swift `swift_test` whose preferences never reach ~/Library/Preferences.

    Args:
      name: the test's name.
      deps: its dependencies; //tools/swift-test-preferences:test_preferences is added.
      **kwargs: everything else rules_swift's `swift_test` takes.
    """
    _swift_test(
        name = name,
        deps = deps + [Label("//tools/swift-test-preferences:test_preferences")],
        **kwargs
    )
