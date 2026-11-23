import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from quality_metrics import (  # noqa: E402
    TestInputs,
    calculate,
    defect_density,
    defect_detection_efficiency,
    mean_time_to_repair,
    pass_rate,
    requirements_coverage,
)


class QualityMetricsTests(unittest.TestCase):
    def test_report_values(self):
        values = calculate(TestInputs())
        self.assertAlmostEqual(values["defect_density"], 2.0)
        self.assertAlmostEqual(values["pass_rate"], 44 / 47 * 100)
        self.assertAlmostEqual(values["requirements_coverage"], 95.0)
        self.assertAlmostEqual(values["defect_detection_efficiency"], 90.0)
        self.assertAlmostEqual(values["mttr_hours"], 2.7)

    def test_zero_denominators_are_rejected(self):
        with self.assertRaises(ValueError):
            defect_density(2, 0)
        with self.assertRaises(ValueError):
            pass_rate(1, 0)
        with self.assertRaises(ValueError):
            requirements_coverage(1, 0)
        with self.assertRaises(ValueError):
            defect_detection_efficiency(0, 0)
        with self.assertRaises(ValueError):
            mean_time_to_repair([])

    def test_invalid_counts_are_rejected(self):
        with self.assertRaises(ValueError):
            pass_rate(3, 2)
        with self.assertRaises(ValueError):
            requirements_coverage(5, 4)
        with self.assertRaises(ValueError):
            defect_density(-1, 2)

    def test_mttr_uses_arithmetic_mean(self):
        self.assertAlmostEqual(mean_time_to_repair([1.0, 2.0, 3.0]), 2.0)


if __name__ == "__main__":
    unittest.main()
