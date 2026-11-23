#!/usr/bin/env python3
"""Reproducible financial and error-budget calculations for OrderFlow."""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class OutageInputs:
    revenue_per_hour: float = 12_000.0
    outage_hours: float = 2.0
    lost_orders_per_hour: float = 18.0
    handling_cost_per_order: float = 120.0


@dataclass(frozen=True)
class ProtectionMeasure:
    name: str
    annual_cost: float
    probability_after: float
    consequence_after: float


BASELINE_PROBABILITY = 0.20
BASELINE_CONSEQUENCE = 150_000.0
MEASURES = (
    ProtectionMeasure("Monitoring and alerting", 6_000.0, 0.12, 150_000.0),
    ProtectionMeasure("Automatic failover / replica", 18_000.0, 0.08, 110_000.0),
    ProtectionMeasure("Backup and restore drills", 3_000.0, 0.20, 110_000.0),
)


def outage_cost(inputs: OutageInputs = OutageInputs()) -> dict[str, float]:
    if inputs.revenue_per_hour < 0 or inputs.outage_hours < 0:
        raise ValueError("revenue and outage duration cannot be negative")
    if inputs.lost_orders_per_hour < 0 or inputs.handling_cost_per_order < 0:
        raise ValueError("orders and handling cost cannot be negative")
    lost_revenue = inputs.revenue_per_hour * inputs.outage_hours
    lost_orders = inputs.lost_orders_per_hour * inputs.outage_hours
    recovery_cost = lost_orders * inputs.handling_cost_per_order
    return {
        "lost_revenue": lost_revenue,
        "lost_orders": lost_orders,
        "recovery_cost": recovery_cost,
        "direct_total": lost_revenue + recovery_cost,
    }


def expected_loss(probability: float, consequence: float) -> float:
    if not 0 <= probability <= 1:
        raise ValueError("probability must be between 0 and 1")
    if consequence < 0:
        raise ValueError("consequence cannot be negative")
    return probability * consequence


def evaluate_measure(measure: ProtectionMeasure) -> dict[str, float | str]:
    el_before = expected_loss(BASELINE_PROBABILITY, BASELINE_CONSEQUENCE)
    el_after = expected_loss(measure.probability_after, measure.consequence_after)
    delta = el_before - el_after
    net = delta - measure.annual_cost
    return {
        "name": measure.name,
        "annual_cost": measure.annual_cost,
        "el_before": el_before,
        "el_after": el_after,
        "delta_el": delta,
        "net_gain": net,
    }


def mttr_saving(hours_before: float, hours_after: float, cost_per_hour: float) -> float:
    if hours_before < 0 or hours_after < 0 or cost_per_hour < 0:
        raise ValueError("times and hourly cost cannot be negative")
    if hours_after > hours_before:
        raise ValueError("hours_after cannot exceed hours_before for a saving calculation")
    return (hours_before - hours_after) / 60.0 * cost_per_hour


def error_budget(slo: float, annual_hours: float = 8760.0, actual_downtime_hours: float = 1.25) -> dict[str, float]:
    if not 0 < slo <= 1:
        raise ValueError("SLO must be greater than 0 and no greater than 1")
    if annual_hours <= 0 or actual_downtime_hours < 0:
        raise ValueError("annual hours must be positive and downtime non-negative")
    budget_percent = (1.0 - slo) * 100.0
    budget_hours = annual_hours * (1.0 - slo)
    remaining_hours = budget_hours - actual_downtime_hours
    consumed_percent = (actual_downtime_hours / budget_hours * 100.0) if budget_hours else 0.0
    return {
        "budget_percent": budget_percent,
        "budget_hours": budget_hours,
        "actual_downtime_hours": actual_downtime_hours,
        "remaining_hours": remaining_hours,
        "consumed_percent": consumed_percent,
    }


def main() -> None:
    outage = outage_cost()
    print("OrderFlow: educational downtime model")
    print(f"Lost revenue:          {outage['lost_revenue']:,.2f} RUB")
    print(f"Orders for recovery:   {outage['lost_orders']:.0f}")
    print(f"Recovery handling:     {outage['recovery_cost']:,.2f} RUB")
    print(f"Direct total:          {outage['direct_total']:,.2f} RUB")
    print("\nAnnual expected-loss model")
    for measure in MEASURES:
        row = evaluate_measure(measure)
        print(
            f"{row['name']}: EL before={row['el_before']:,.2f}; "
            f"EL after={row['el_after']:,.2f}; ΔEL={row['delta_el']:,.2f}; "
            f"net={row['net_gain']:,.2f} RUB/year"
        )
    saving = mttr_saving(120, 20, 12_000)
    print(f"One-incident MTTR saving: {saving:,.2f} RUB")
    budget = error_budget(0.9995)
    print("\nError budget")
    for key, value in budget.items():
        print(f"{key}: {value:.4f}")


if __name__ == "__main__":
    main()
