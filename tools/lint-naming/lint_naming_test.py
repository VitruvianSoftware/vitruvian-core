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

"""Unified Test Suite Entrypoint for Monorepo Naming Enforcement.

Combines all 4 tiers of testing:
- Tier 1: Feature Coverage (60 test cases across 10 features F1-F10)
- Tier 2: Boundary & Corner Cases (60 test cases across extreme inputs)
- Tier 3: Pairwise Cross-Feature Interactions (20 test cases)
- Tier 4: Real-World Scenarios (5 workload simulations)
"""

import os
import sys
import unittest

# Ensure tools/lint-naming is in python path
_PKG_DIR = os.path.dirname(os.path.abspath(__file__))
if _PKG_DIR not in sys.path:
    sys.path.insert(0, _PKG_DIR)

from tests.tier1_feature_test import Tier1FeatureTestSuite
from tests.tier2_boundary_test import Tier2BoundaryTestSuite
from tests.tier3_pairwise_test import Tier3PairwiseTestSuite
from tests.tier4_realworld_test import Tier4RealWorldScenarioTestSuite


def suite() -> unittest.TestSuite:
    """Create consolidated test suite across all 4 tiers."""
    test_suite = unittest.TestSuite()
    loader = unittest.TestLoader()

    test_suite.addTests(loader.loadTestsFromTestCase(Tier1FeatureTestSuite))
    test_suite.addTests(loader.loadTestsFromTestCase(Tier2BoundaryTestSuite))
    test_suite.addTests(loader.loadTestsFromTestCase(Tier3PairwiseTestSuite))
    test_suite.addTests(loader.loadTestsFromTestCase(Tier4RealWorldScenarioTestSuite))

    return test_suite


if __name__ == "__main__":
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite())
    sys.exit(0 if result.wasSuccessful() else 1)
