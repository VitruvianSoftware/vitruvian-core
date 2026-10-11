#!/usr/bin/env python3
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

"""Unit tests for tools/sync-downloads helper routines."""

import unittest
from sync_downloads import parse_semver, format_size


class TestSyncDownloads(unittest.TestCase):
    def test_parse_semver(self):
        self.assertEqual(parse_semver("v1.2.3"), (1, 2, 3))
        self.assertEqual(parse_semver("home-speaker-v1.11.0"), (1, 11, 0))
        self.assertEqual(parse_semver("vitruvian-v3.37.1"), (3, 37, 1))
        self.assertEqual(parse_semver("nexus-agent-1.20.1"), (1, 20, 1))
        self.assertEqual(parse_semver("0.1.2"), (0, 1, 2))
        self.assertEqual(parse_semver("no-numbers"), (0, 0, 0))

    def test_format_size_kilobytes(self):
        self.assertEqual(format_size(500 * 1024), "500 KB")
        self.assertEqual(format_size(994 * 1024), "994 KB")

    def test_format_size_megabytes(self):
        self.assertEqual(format_size(4 * 1024 * 1024), "4.0 MB")
        self.assertEqual(format_size(10 * 1024 * 1024), "10 MB")
        self.assertEqual(format_size(int(78.3 * 1024 * 1024)), "78.3 MB")


if __name__ == "__main__":
    unittest.main()
