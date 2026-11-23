#!/usr/bin/env python3
"""Reproducible quality indicators for the OrderFlow educational test report."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable


@dataclass(frozen=True)
class TestInputs:
    kloc: float = 12.5
    defects_total: int = 25
    tests_planned: int = 50
    tests_executed: int = 47
    tests_passed: int = 44
    requirements_total: int = 40
    requirements_checked: int = 38
    defects_before_release: int = 18
    defects_after_release: int = 2
    resolution_hours: tuple[float, ...] = (1.5, 2.0, 2.5, 3.0, 4.5)


def _positive(value: float, label: str) -> None:
    if value <= 0:
        raise ValueError(f"{label} must be greater than zero")


def defect_density(defects: int, kloc: float) -> float:
    _positive(kloc, "KLOC")
    if defects < 0:
        raise ValueError("defects cannot be negative")
    return defects / kloc


def pass_rate(passed: int, executed: int) -> float:
    _positive(executed, "executed tests")
    if passed < 0 or passed > executed:
        raise ValueError("passed tests must be between zero and executed tests")
    return passed / executed * 100.0


def requirements_coverage(checked: int, total: int) -> float:
    _positive(total, "total requirements")
    if checked < 0 or checked > total:
        raise ValueError("checked requirements must be between zero and total")
    return checked / total * 100.0


def defect_detection_efficiency(before: int, after: int) -> float:
    total = before + after
    _positive(total, "total defects")
    if before < 0 or after < 0:
        raise ValueError("defect counts cannot be negative")
    return before / total * 100.0


def mean_time_to_repair(hours: Iterable[float]) -> float:
    values = tuple(hours)
    _positive(len(values), "repair count")
    if any(value < 0 for value in values):
        raise ValueError("repair times cannot be negative")
    return sum(values) / len(values)


def calculate(inputs: TestInputs = TestInputs()) -> dict[str, float]:
    return {
        "defect_density": defect_density(inputs.defects_total, inputs.kloc),
        "pass_rate": pass_rate(inputs.tests_passed, inputs.tests_executed),
        "requirements_coverage": requirements_coverage(
            inputs.requirements_checked, inputs.requirements_total
        ),
        "defect_detection_efficiency": defect_detection_efficiency(
            inputs.defects_before_release, inputs.defects_after_release
        ),
        "mttr_hours": mean_time_to_repair(inputs.resolution_hours),
    }


def main() -> None:
    values = calculate()
    print("OrderFlow educational quality indicators")
    print(f"D  defect density:               {values['defect_density']:.2f} defects/KLOC")
    print(f"P  passed tests:                  {values['pass_rate']:.2f}%")
    print(f"C  requirements coverage:        {values['requirements_coverage']:.2f}%")
    print(f"E  defect detection efficiency:   {values['defect_detection_efficiency']:.2f}%")
    print(f"MTTR mean repair time:            {values['mttr_hours']:.2f} hours")


if __name__ == "__main__":
    main()
