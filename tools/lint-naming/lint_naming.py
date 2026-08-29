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

"""CLI runner for Monorepo Naming Convention Linter."""

import argparse
import os
import sys
from typing import List

try:
    from .rules import ViolationSeverity
    from .scanner import RepositoryNamingScanner
except (ImportError, ValueError):
    from rules import ViolationSeverity
    from scanner import RepositoryNamingScanner


def main(argv: List[str] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Vitruvian Core Monorepo Naming Convention Linter & Enforcement Tool"
    )
    parser.add_argument(
        "--root",
        default=os.environ.get("BUILD_WORKSPACE_DIRECTORY", "."),
        help="Root directory to scan (defaults to BUILD_WORKSPACE_DIRECTORY or current directory)",
    )
    parser.add_argument(
        "--format",
        choices=["text", "json"],
        default="text",
        help="Output format (text or json)",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Fail on warnings as well as errors",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        default=True,
        help="Exit with non-zero status if violations are found",
    )

    args = parser.parse_args(argv)

    scanner = RepositoryNamingScanner(root_dir=args.root)
    violations = scanner.scan()

    report = scanner.format_report(violations, output_format=args.format)
    print(report)

    if not args.check:
        return 0

    if args.strict and violations:
        return 1

    has_errors = any(v.severity == ViolationSeverity.ERROR for v in violations)
    return 1 if has_errors else 0


if __name__ == "__main__":
    sys.exit(main())
