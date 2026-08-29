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

"""Comprehensive Test Runner for Monorepo Naming Enforcement Test Suite.

Provides CLI options to execute tests by tier, measure execution time,
and render detailed test result summary matrices.

Usage:
  python3 tools/lint-naming/test_runner.py [--tier 1,2,3,4] [--verbose]
"""

import argparse
import os
import sys
import time
import unittest

# Ensure tools/lint-naming is in python path
_PKG_DIR = os.path.dirname(os.path.abspath(__file__))
if _PKG_DIR not in sys.path:
    sys.path.insert(0, _PKG_DIR)

from tests.tier1_feature_test import Tier1FeatureTestSuite
from tests.tier2_boundary_test import Tier2BoundaryTestSuite
from tests.tier3_pairwise_test import Tier3PairwiseTestSuite
from tests.tier4_realworld_test import Tier4RealWorldScenarioTestSuite


TIER_MAPPING = {
    1: ("Tier 1: Feature Coverage (F1-F10)", Tier1FeatureTestSuite),
    2: ("Tier 2: Boundary & Corner Cases", Tier2BoundaryTestSuite),
    3: ("Tier 3: Pairwise Cross-Feature Interactions", Tier3PairwiseTestSuite),
    4: ("Tier 4: Real-World Scenarios", Tier4RealWorldScenarioTestSuite),
}


def run_tests(tiers=None, verbosity=1) -> int:
    selected_tiers = tiers or [1, 2, 3, 4]
    total_ran = 0
    total_failed = 0
    total_errors = 0
    tier_results = []

    start_time = time.time()
    print("=" * 80)
    print(" Vitruvian Core — Monorepo Naming Enforcement Test Suite")
    print("=" * 80)

    for tier_num in sorted(selected_tiers):
        if tier_num not in TIER_MAPPING:
            print(f"Unknown tier: {tier_num}")
            continue

        tier_name, test_class = TIER_MAPPING[tier_num]
        suite = unittest.TestLoader().loadTestsFromTestCase(test_class)
        runner = unittest.TextTestRunner(verbosity=verbosity)

        print(f"\n▶ Executing {tier_name} ({suite.countTestCases()} test cases)...")
        tier_start = time.time()
        result = runner.run(suite)
        tier_duration = time.time() - tier_start

        failures = len(result.failures)
        errors = len(result.errors)
        passed = result.testsRun - failures - errors

        total_ran += result.testsRun
        total_failed += failures
        total_errors += errors

        status = "PASSED" if result.wasSuccessful() else "FAILED"
        tier_results.append((tier_num, tier_name, result.testsRun, passed, failures, errors, tier_duration, status))

    total_duration = time.time() - start_time

    # Render Summary Table
    print("\n" + "=" * 80)
    print(" TEST EXECUTION SUMMARY")
    print("=" * 80)
    print(f"{'Tier':<8} {'Description':<42} {'Total':<7} {'Pass':<7} {'Fail':<7} {'Time (s)':<9} {'Status'}")
    print("-" * 80)
    for t_num, t_name, total, p, f, e, d, st in tier_results:
        print(f"Tier {t_num:<3} {t_name[:40]:<42} {total:<7} {p:<7} {f+e:<7} {d:<9.3f} {st}")
    print("-" * 80)
    print(f"{'TOTAL':<51} {total_ran:<7} {total_ran - total_failed - total_errors:<7} {total_failed + total_errors:<7} {total_duration:<9.3f} {'PASSED' if (total_failed + total_errors) == 0 else 'FAILED'}")
    print("=" * 80)

    return 0 if (total_failed + total_errors) == 0 else 1


def main():
    parser = argparse.ArgumentParser(description="Monorepo Naming Enforcement Test Suite Runner")
    parser.add_argument(
        "--tier",
        type=str,
        default="1,2,3,4",
        help="Comma-separated list of tiers to run (e.g. '1,2,3,4')",
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Run tests with high verbosity",
    )

    args = parser.parse_args()
    selected = [int(x.strip()) for x in args.tier.split(",") if x.strip().isdigit()]
    verbosity = 2 if args.verbose else 1

    sys.exit(run_tests(tiers=selected, verbosity=verbosity))


if __name__ == "__main__":
    main()
