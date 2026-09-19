"""
rolling_fan_charts.py
Builds ONE separate fan chart image per day of the rolling test chain
(rolling_test_chain.R) -- not a single combined multi-panel figure, per
explicit design choice: each forecast origin gets its own standalone
chart, with the actual observed price marked as a point.
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt


def load_rolling_fan_inputs(path="../data/processed/rolling_fan_chart_inputs.csv"):
    df = pd.read_csv(path)
    df["target_date"] = pd.to_datetime(df["target_date"])
    return df


def plot_single_day_fan_chart(day_df, target_date, save_path):
    day_df = day_df.sort_values("confidence_level", ascending=False)
    actual = day_df["actual_price"].iloc[0]

    fig, ax = plt.subplots(figsize=(4, 6))
    n = len(day_df)
    for i, (_, row) in enumerate(day_df.iterrows()):
        alpha_fill = 0.15 + 0.5 * (i / max(n - 1, 1))
        ax.fill_between(
            [0, 1], [row["p_min"], row["p_min"]], [row["p_max"], row["p_max"]],
            color="steelblue", alpha=alpha_fill,
            label=f"{row['confidence_level']:.0%}"
        )

    # Actual observed price, marked as a point -- the whole purpose of
    # this per-day chart is to see at a glance whether it landed inside
    # or outside each band.
    ax.scatter([0.5], [actual], color="red", zorder=5, s=80,
               label=f"Actual ({actual:.4f})")

    ax.set_xticks([])
    ax.set_ylabel("EUR/USD")
    ax.set_title(f"Forecast for {target_date.strftime('%Y-%m-%d')}")
    ax.legend(loc="upper left", bbox_to_anchor=(1.02, 1), fontsize=8)
    plt.tight_layout()
    plt.savefig(save_path, dpi=150)
    plt.close(fig)
    print(f"Saved {save_path}")


if __name__ == "__main__":
    df = load_rolling_fan_inputs()

    for target_date in sorted(df["target_date"].unique()):
        day_df = df[df["target_date"] == target_date]
        date_str = pd.Timestamp(target_date).strftime("%Y%m%d")
        save_path = f"../docs/fan_chart_rolling_{date_str}.png"
        plot_single_day_fan_chart(day_df, pd.Timestamp(target_date), save_path)
