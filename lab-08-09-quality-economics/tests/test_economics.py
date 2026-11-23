import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from economics import (  # noqa: E402
    MEASURES,
    OutageInputs,
    error_budget,
    evaluate_measure,
    expected_loss,
    mttr_saving,
    outage_cost,
)


class EconomicsTests(unittest.TestCase):
    def test_downtime_cost(self):
        result = outage_cost(OutageInputs())
        self.assertEqual(result["lost_revenue"], 24_000)
        self.assertEqual(result["lost_orders"], 36)
        self.assertEqual(result["recovery_cost"], 4_320)
        self.assertEqual(result["direct_total"], 28_320)

    def test_expected_loss_and_measures(self):
        self.assertEqual(expected_loss(0.2, 150_000), 30_000)
        results = [evaluate_measure(item) for item in MEASURES]
        self.assertEqual([row["net_gain"] for row in results], [6_000, 3_200, 5_000])

    def test_mttr_saving(self):
        self.assertAlmostEqual(mttr_saving(120, 20, 12_000), 20_000)
        with self.assertRaises(ValueError):
            mttr_saving(20, 40, 1000)

    def test_error_budget(self):
        result = error_budget(0.9995, actual_downtime_hours=1.25)
        self.assertAlmostEqual(result["budget_percent"], 0.05)
        self.assertAlmostEqual(result["budget_hours"], 4.38)
        self.assertAlmostEqual(result["remaining_hours"], 3.13)
        self.assertAlmostEqual(result["consumed_percent"], 1.25 / 4.38 * 100)

    def test_invalid_inputs_are_rejected(self):
        with self.assertRaises(ValueError):
            expected_loss(1.2, 100)
        with self.assertRaises(ValueError):
            outage_cost(OutageInputs(outage_hours=-1))
        with self.assertRaises(ValueError):
            error_budget(0)


if __name__ == "__main__":
    unittest.main()
