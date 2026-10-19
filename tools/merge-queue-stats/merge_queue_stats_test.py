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

"""The counting in merge_queue_stats, on hand-made timelines: no network."""

import datetime as dt
import unittest

import merge_queue_stats as m

SINCE = dt.datetime(2026, 10, 5, tzinfo=dt.timezone.utc)
UNTIL = dt.datetime(2026, 10, 19, tzinfo=dt.timezone.utc)


def added(at):
    return {"__typename": "AddedToMergeQueueEvent", "createdAt": at}


def removed(at, reason, who=m.QUEUE_BOT):
    return {
        "__typename": "RemovedFromMergeQueueEvent",
        "createdAt": at,
        "reason": reason,
        "actor": {"login": who},
    }


def pr(merged, *events):
    return {"number": 1, "mergedAt": merged, "timelineItems": {"nodes": list(events)}}


class QueueTimes(unittest.TestCase):
    def test_last_and_first_entry(self):
        retried = pr(
            "2026-10-10T01:00:00Z",
            added("2026-10-10T00:00:00Z"),
            removed("2026-10-10T00:20:00Z", "failed_checks"),
            added("2026-10-10T00:50:00Z"),
            removed("2026-10-10T01:00:00Z", "merged"),
        )
        last, first = m.queue_times([retried], SINCE, UNTIL)
        self.assertEqual(last, [10.0])
        self.assertEqual(first, [60.0])

    def test_skips_unmerged_outside_window_and_never_queued(self):
        pulls = [
            pr(None, added("2026-10-10T00:00:00Z")),
            pr("2026-10-20T00:00:00Z", added("2026-10-19T23:00:00Z")),
            pr("2026-10-10T00:00:00Z"),
            pr(
                "2026-10-10T00:05:00Z", added("2026-10-10T00:10:00Z")
            ),  # an entry after the merge
        ]
        self.assertEqual(m.queue_times(pulls, SINCE, UNTIL), ([], []))


class Ejections(unittest.TestCase):
    def test_counts_the_queue_bot_only_and_never_merged(self):
        pulls = [
            pr(
                "2026-10-10T01:00:00Z",
                removed("2026-10-10T00:20:00Z", "failed_checks"),
                removed("2026-10-10T00:30:00Z", "checks_timed_out"),
                removed("2026-10-10T00:40:00Z", "failed_checks"),
                removed("2026-10-10T00:45:00Z", "dequeued", who="james"),
                removed("2026-10-10T01:00:00Z", "merged"),
                removed("2026-10-20T00:00:00Z", "failed_checks"),
            )
        ]
        self.assertEqual(
            m.ejections(pulls, SINCE, UNTIL),
            {"failed_checks": 2, "checks_timed_out": 1},
        )


class Report(unittest.TestCase):
    def test_shape(self):
        pulls = [pr("2026-10-10T00:10:00Z", added("2026-10-10T00:00:00Z"))]
        runs = [
            {"name": "CI", "conclusion": "failure"},
            {"name": "CI", "conclusion": "timed_out"},
            {"name": "Presubmit", "conclusion": "success"},
        ]
        out = m.report("o/r", SINCE, UNTIL, pulls, runs, ['Revert "x"'])
        self.assertIn("| PRs merged through the queue | 1 (0.1/day) |", out)
        self.assertIn("median 10.0 min, p90 10.0 min", out)
        self.assertIn("**Ejections by the queue:** 0", out)
        self.assertIn("**Breakage on main:** 2 failed push run(s), 1 revert(s)", out)
        self.assertIn("- CI: 2", out)
        self.assertNotIn("Presubmit", out)

    def test_percentile(self):
        self.assertIsNone(m.percentile([], 0.5))
        self.assertEqual(m.percentile([3, 1, 2], 0.5), 2)
        self.assertEqual(m.percentile(list(range(1, 11)), 0.9), 9)


if __name__ == "__main__":
    unittest.main()
