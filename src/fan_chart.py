"""
fan_chart.py
Builds a Bank-of-England-style fan chart from the multi-level MS-GARCH
forecast (ms_garch_forecast.R, section 5), converting each confidence
band's return interval into an actual EUR/USD price band.
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt


def load_fan_inputs(path="../data/processed/ms_garch_fan_chart_inputs.csv"):
    return pd.read_csv(path)


def to_price_bands(df):
    """Convert each row's return interval (%) into a price interval."""
    df = df.copy()
    df["p_low"] = df["last_price"] * np.exp(df["return_q_low"] / 100)
    df["p_high"] = df["last_price"] * np.exp(df["return_q_high"] / 100)
    return df.sort_values("confidence_level")


def plot_fan_chart(df, save_path="../docs/fan_chart.png"):
    last_price = df["last_price"].iloc[0]
    last_date = df["last_date"].iloc[0]

    fig, ax = plt.subplots(figsize=(8, 5))

    # Draw widest band first, narrowest last, so narrower bands are not
    # visually hidden underneath wider ones.
    df_sorted = df.sort_values("confidence_level", ascending=False)
    n = len(df_sorted)
    for i, (_, row) in enumerate(df_sorted.iterrows()):
        alpha_fill = 0.15 + 0.5 * (i / max(n - 1, 1))  # darker = narrower/more central
        ax.fill_between(
            [0, 1], [row["p_low"], row["p_low"]], [row["p_high"], row["p_high"]],
            color="steelblue", alpha=alpha_fill,
            label=f"{row['confidence_level']:.0%}"
        )

    ax.axhline(last_price, color="black", linestyle="--", linewidth=1,
               label=f"Last price ({last_price:.4f})")
    ax.set_xticks([])
    ax.set_ylabel("EUR/USD")
    ax.set_title(f"MS-GARCH one-step-ahead price fan chart\n(as of {last_date})")
    ax.legend(loc="upper left", bbox_to_anchor=(1.02, 1), title="Confidence level")
    plt.tight_layout()
    plt.savefig(save_path, dpi=150)
    print(f"Fan chart saved to {save_path}")


if __name__ == "__main__":
    df = load_fan_inputs()
    df = to_price_bands(df)
    print(df[["confidence_level", "p_low", "p_high"]].to_string(index=False))
    plot_fan_chart(df)
