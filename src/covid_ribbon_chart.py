"""
covid_ribbon_chart.py
Time-series ribbon chart for the COVID out-of-sample robustness test
(covid_robustness_test.R) -- one continuous chart (not one image per day,
per the format decision made for the September rolling test when the
window is short; here 84 days makes a single ribbon chart the right
format instead).

Shows: actual EUR/USD price as a line, nested confidence bands
(20/50/80/95%) computed day by day with FROZEN pre-2020 parameters, and
the 7 breach days marked and color-coded by the two distinct groups
identified in docs/covid_robustness_test.md:
  - Group A: breaches where the model's regime probability had NOT yet
    reacted (P(stress) < 50% at the time of forecast)
  - Group B: breaches where the model HAD already flagged high stress
    (P(stress) > 95%) but the realized move still exceeded even the
    widened band
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt


def load_data(
    fan_path="../data/processed/covid_robustness_fan_data.csv",
    result_path="../data/processed/covid_robustness_result.csv",
):
    fan = pd.read_csv(fan_path, parse_dates=["target_date"])
    result = pd.read_csv(result_path, parse_dates=["target_date"])
    return fan, result


def classify_breach_group(row):
    if row["inside_range"]:
        return "inside"
    return "group_b_late" if row["prob_stress"] > 0.5 else "group_a_early"


def plot_ribbon(fan, result, save_path="../docs/covid_ribbon_chart.png"):
    result = result.copy()
    result["breach_group"] = result.apply(classify_breach_group, axis=1)

    levels = sorted(fan["confidence_level"].unique(), reverse=True)
    fig, ax = plt.subplots(figsize=(13, 6))

    for i, cl in enumerate(levels):
        sub = fan[fan["confidence_level"] == cl].sort_values("target_date")
        alpha_fill = 0.12 + 0.45 * (i / max(len(levels) - 1, 1))
        ax.fill_between(sub["target_date"], sub["p_min"], sub["p_max"],
                         color="steelblue", alpha=alpha_fill,
                         label=f"{cl:.0%} band")

    # Actual price line
    result_sorted = result.sort_values("target_date")
    ax.plot(result_sorted["target_date"], result_sorted["actual_price"],
            color="black", linewidth=1.2, label="Actual EUR/USD")

    # Breach points, color-coded by group
    group_colors = {"group_a_early": "orange", "group_b_late": "red"}
    group_labels = {
        "group_a_early": "Breach: regime not yet reacted (P(stress)<50%)",
        "group_b_late": "Breach: regime already flagged stress (P(stress)>95%)",
    }
    for group, color in group_colors.items():
        sub = result_sorted[result_sorted["breach_group"] == group]
        if len(sub) > 0:
            ax.scatter(sub["target_date"], sub["actual_price"],
                       color=color, s=60, zorder=5, label=group_labels[group])

    ax.set_ylabel("EUR/USD")
    ax.set_title("COVID out-of-sample robustness test (2020-01-01 to 2020-04-30)\n"
                 "Pre-2020-only frozen parameters, one-step-ahead rolling forecast")
    ax.legend(loc="upper left", bbox_to_anchor=(1.02, 1), fontsize=9)
    ax.tick_params(axis="x", rotation=45)
    plt.tight_layout()
    plt.savefig(save_path, dpi=150)
    print(f"Saved {save_path}")


if __name__ == "__main__":
    fan, result = load_data()
    print(f"Loaded {len(result)} forecast days, "
          f"{(~result['inside_range']).sum()} breaches.")
    plot_ribbon(fan, result)
