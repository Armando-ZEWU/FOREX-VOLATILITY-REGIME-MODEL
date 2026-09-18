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


def load_regime_fan_inputs(path="../data/processed/ms_garch_regime_conditional_forecast.csv"):
    return pd.read_csv(path)


def to_price_bands_regime(df, regime_label):
    """Same conversion as to_price_bands, filtered to one regime."""
    sub = df[df["regime"] == regime_label].copy()
    sub["p_low"] = sub["last_price"] * np.exp(sub["return_q_low"] / 100)
    sub["p_high"] = sub["last_price"] * np.exp(sub["return_q_high"] / 100)
    return sub.sort_values("confidence_level")


def plot_fan_chart_panel(ax, df, title, last_price):
    df_sorted = df.sort_values("confidence_level", ascending=False)
    n = len(df_sorted)
    for i, (_, row) in enumerate(df_sorted.iterrows()):
        alpha_fill = 0.15 + 0.5 * (i / max(n - 1, 1))
        ax.fill_between(
            [0, 1], [row["p_low"], row["p_low"]], [row["p_high"], row["p_high"]],
            color="steelblue", alpha=alpha_fill,
            label=f"{row['confidence_level']:.0%}"
        )
    ax.axhline(last_price, color="black", linestyle="--", linewidth=1)
    ax.set_xticks([])
    ax.set_title(title)


def plot_all_fan_charts(mixture_df, regime_df, save_path="../docs/fan_chart.png"):
    """Three panels side by side: mixture (operational), calm regime, stress regime."""
    last_price = mixture_df["last_price"].iloc[0]
    last_date = mixture_df["last_date"].iloc[0]

    calm_df = to_price_bands_regime(regime_df, "1_calm")
    stress_df = to_price_bands_regime(regime_df, "2_stress")

    fig, axes = plt.subplots(1, 3, figsize=(14, 5), sharey=True)
    plot_fan_chart_panel(axes[0], mixture_df, "Operational (regime mixture)", last_price)
    plot_fan_chart_panel(axes[1], calm_df, "If calm regime (certain)", last_price)
    plot_fan_chart_panel(axes[2], stress_df, "If stress regime (certain)", last_price)

    axes[0].set_ylabel("EUR/USD")
    axes[-1].legend(loc="upper left", bbox_to_anchor=(1.02, 1), title="Confidence level")
    fig.suptitle(f"MS-GARCH one-step-ahead price fan charts (as of {last_date})")
    plt.tight_layout()
    plt.savefig(save_path, dpi=150)
    print(f"Fan charts saved to {save_path}")


if __name__ == "__main__":
    df = load_fan_inputs()
    df = to_price_bands(df)
    print("--- Mixture (operational) ---")
    print(df[["confidence_level", "p_low", "p_high"]].to_string(index=False))

    regime_df = load_regime_fan_inputs()
    calm_bands = to_price_bands_regime(regime_df, "1_calm")
    stress_bands = to_price_bands_regime(regime_df, "2_stress")
    print("\n--- Calm regime (certain) ---")
    print(calm_bands[["confidence_level", "p_low", "p_high"]].to_string(index=False))
    print("\n--- Stress regime (certain) ---")
    print(stress_bands[["confidence_level", "p_low", "p_high"]].to_string(index=False))

    plot_all_fan_charts(df, regime_df)