"""
covid_candlestick_chart.py
Enriches the COVID robustness test results with real Open/High/Low/Close
data (Pound Sterling Live, since FRED's DEXUSEU is a single daily rate,
not true OHLC), producing:
  1. A full 84-row comparison table (forecast range vs. real OHLC),
     exported to CSV since it is too long for inline markdown.
  2. A candlestick + confidence-band chart, replacing the plain black
     line used in the first version of covid_ribbon_chart.py.

DATA SOURCE NOTE: OHLC values come from an independent source
(poundsterlinglive.com/history/EUR-USD-2020), not FRED. The model itself
was fitted and forecast entirely on FRED's single-rate series (no change
to the forecasting pipeline) -- this OHLC data is used ONLY to enrich the
comparison/visualization with real intraday context, the same principle
already applied for the September 2026 rolling test. A modest source
discrepancy between FRED's daily rate and this source's Close is expected
(same order as the ~0.05% already documented in price_range.md, section
7.1) and does not affect the forecasts themselves.
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.dates as mdates


def load_and_merge(
    result_path="../data/processed/covid_robustness_result.csv",
    fan_path="../data/processed/covid_robustness_fan_data.csv",
    ohlc_path="../data/raw/eurusd_ohlc_2020_covid.csv",
):
    result = pd.read_csv(result_path, parse_dates=["target_date"])
    fan = pd.read_csv(fan_path, parse_dates=["target_date"])
    ohlc = pd.read_csv(ohlc_path, parse_dates=["Date"])

    merged = result.merge(ohlc, left_on="target_date", right_on="Date", how="left")
    missing = merged[merged["Date"].isna()]
    if len(missing) > 0:
        print(f"WARNING: {len(missing)} forecast date(s) had no matching OHLC row:")
        print(missing["target_date"].tolist())

    return merged, fan


def build_full_table(merged):
    """Full 84-row table: forecast range vs. FRED close (model's own
    target) AND the independent source's Open/High/Low/Close for context."""
    table = merged[[
        "target_date", "p_min", "p_max", "actual_price",
        "Open", "High", "Low", "Close", "inside_range", "prob_stress"
    ]].copy()
    table["close_breach_direction"] = np.where(
        table["inside_range"], "inside",
        np.where(table["actual_price"] > table["p_max"], "upper", "lower")
    )
    table["low_below_pmin"] = table["Low"] < table["p_min"]
    table["high_above_pmax"] = table["High"] > table["p_max"]
    return table


def plot_candlestick_with_bands(merged, fan, save_path="../docs/covid_candlestick_chart.png"):
    merged = merged.sort_values("target_date")
    dates = merged["target_date"]
    date_nums = mdates.date2num(dates)

    fig, ax = plt.subplots(figsize=(15, 6))

    levels = sorted(fan["confidence_level"].unique(), reverse=True)
    for i, cl in enumerate(levels):
        sub = fan[fan["confidence_level"] == cl].sort_values("target_date")
        alpha_fill = 0.12 + 0.45 * (i / max(len(levels) - 1, 1))
        ax.fill_between(sub["target_date"], sub["p_min"], sub["p_max"],
                         color="steelblue", alpha=alpha_fill,
                         label=f"{cl:.0%} band", zorder=1)

    # Hand-drawn candlesticks (no external dependency like mplfinance):
    # a thin line from Low to High, a filled body from Open to Close,
    # green if Close >= Open, red otherwise.
    width = 0.6
    for i, row in merged.iterrows():
        d = date_nums[merged.index.get_loc(i)]
        color = "green" if row["Close"] >= row["Open"] else "red"
        ax.plot([d, d], [row["Low"], row["High"]], color="black", linewidth=0.7, zorder=3)
        lower = min(row["Open"], row["Close"])
        height = abs(row["Close"] - row["Open"])
        ax.bar(d, height if height > 0 else 0.0005, bottom=lower, width=width,
               color=color, edgecolor="black", linewidth=0.4, zorder=4)

    ax.xaxis.set_major_formatter(mdates.DateFormatter("%Y-%m-%d"))
    ax.xaxis.set_major_locator(mdates.WeekdayLocator(interval=1))
    ax.set_ylabel("EUR/USD")
    ax.set_title("COVID out-of-sample robustness test (2020-01-01 to 2020-04-30)\n"
                 "Real OHLC (Pound Sterling Live) vs. FRED-based forecast bands "
                 "(pre-2020-only frozen parameters)")
    ax.legend(loc="upper left", bbox_to_anchor=(1.01, 1), fontsize=8)
    plt.xticks(rotation=45, ha="right")
    plt.tight_layout()
    plt.savefig(save_path, dpi=150)
    print(f"Saved {save_path}")


if __name__ == "__main__":
    merged, fan = load_and_merge()
    table = build_full_table(merged)
    table.to_csv("../data/processed/covid_full_comparison_table.csv", index=False)
    print(f"Full comparison table ({len(table)} rows) saved to "
          "covid_full_comparison_table.csv")

    n_close_breach = (~table["inside_range"]).sum()
    n_low_breach = table["low_below_pmin"].sum()
    n_high_breach = table["high_above_pmax"].sum()
    print(f"Breaches on Close: {n_close_breach} | "
          f"Days with Low below p_min: {n_low_breach} | "
          f"Days with High above p_max: {n_high_breach}")

    plot_candlestick_with_bands(merged, fan)
