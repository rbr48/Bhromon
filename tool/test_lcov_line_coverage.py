"""Tests for tool/lcov_line_coverage.py. Run from the repository root:

    python3 -m unittest discover -s tool -p "test_*.py"
"""

import io
import tempfile
import unittest
from pathlib import Path

import lcov_line_coverage as coverage


class LineTotalsTest(unittest.TestCase):
    def test_sums_every_record(self):
        trace = io.StringIO(
            "SF:lib/a.dart\nDA:1,1\nLF:4\nLH:3\nend_of_record\n"
            "SF:lib/b.dart\nLF:6\nLH:1\nend_of_record\n"
        )
        self.assertEqual(coverage.line_totals(trace), (4, 10))

    def test_ignores_function_and_branch_records(self):
        trace = io.StringIO("FNF:9\nFNH:2\nBRF:8\nBRH:8\nLF:5\nLH:5\n")
        self.assertEqual(coverage.line_totals(trace), (5, 5))

    def test_an_empty_tracefile_has_no_lines(self):
        self.assertEqual(coverage.line_totals(io.StringIO("")), (0, 0))

    def test_surrounding_whitespace_is_ignored(self):
        trace = io.StringIO("  LF:8  \n\tLH:2\n")
        self.assertEqual(coverage.line_totals(trace), (2, 8))


class PercentTest(unittest.TestCase):
    def test_is_the_hit_share_of_the_found_lines(self):
        # The figure the workflow comment recorded: 10334 of 40353 lines.
        self.assertAlmostEqual(coverage.percent(10334, 40353), 25.61, places=2)
        self.assertEqual(coverage.percent(51, 200), 25.5)


class MainTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.directory = Path(directory.name)
        self.trace = self.directory / "lcov.info"

    def write(self, text):
        self.trace.write_text(text, encoding="utf-8")

    def test_passes_exactly_at_the_floor(self):
        self.write("LF:200\nLH:51\n")  # 25.5%
        self.assertEqual(coverage.main([str(self.trace), "--min", "25.5"]), 0)

    def test_fails_below_the_floor(self):
        self.write("LF:200\nLH:50\n")  # 25.0%
        self.assertEqual(coverage.main([str(self.trace), "--min", "25.5"]), 1)

    def test_without_a_floor_it_only_reports(self):
        self.write("LF:4\nLH:1\n")  # 25.0%, and no floor to fail
        self.assertEqual(coverage.main([str(self.trace)]), 0)

    def test_a_missing_file_is_an_error(self):
        absent = self.directory / "absent.info"
        self.assertEqual(coverage.main([str(absent), "--min", "25.5"]), 2)

    def test_a_tracefile_with_no_lines_is_an_error(self):
        self.write("SF:lib/a.dart\nend_of_record\n")
        self.assertEqual(coverage.main([str(self.trace), "--min", "25.5"]), 2)


if __name__ == "__main__":
    unittest.main()
