"""
control_regression.py
Extends the baseline regression (regression.py) with two control
variables:

    diff_rate(t) = fed_rate(t) - ecb_rate(t)      [level, per UIP theory]
    r_dxy(t)     = ln(dxy_proxy(t) / dxy_proxy(t-1))  [log return, NOT
                   level, to avoid the same spurious-regression risk
                   already addressed for EUR/USD itself — see
                   methodology.md and docs/GARCH_1_1.md]

Full specification:
    r(t+1) = alpha + beta1*DeltaY(t) + beta2*r(t)
             + beta3*diff_rate(t) + beta4*r_dxy(t) + u(t)

To make the comparison of beta1 before/after controls meaningful, the
baseline model is RE-ESTIMATED on the same (smaller, controls-aligned)
sample used here — comparing across different samples would confound
the effect of adding controls with the effect of a changed sample.
"""

import pandas as pd
import numpy as np
import statsmodels.api as sm


def build_full_dataset(returns_path, shocks_path, controls_path):
    """
    Build the aligned dataset including control variables.

    Returns
    -------
    pd.DataFrame
        Columns: r_t, delta_y_t, r_t_plus_1, diff_rate, r_dxy
    """
    returns = pd.read_csv(returns_path, index_col="Date", parse_dates=True)["log_return"]
    sigma = pd.read_csv(shocks_path, index_col="Date", parse_dates=True)["conditional_volatility"]
    controls = pd.read_csv(controls_path, index_col="Date", parse_dates=True)

    df = pd.DataFrame({"r_t": returns, "sigma_t": sigma})
    df["delta_y_t"] = np.log(df["sigma_t"] / df["sigma_t"].shift(1))
    df["r_t_plus_1"] = df["r_t"].shift(-1)

    df = df.join(controls, how="inner")
    df["diff_rate"] = df["fed_rate"] - df["ecb_rate"]
    df["r_dxy"] = np.log(df["dxy_proxy"] / df["dxy_proxy"].shift(1))

    cols = ["r_t", "delta_y_t", "r_t_plus_1", "diff_rate", "r_dxy"]
    df = df.dropna(subset=cols)
    return df[cols]


def run_ols(df, x_cols, y_col="r_t_plus_1", maxlags=5):
    """Generic HAC-robust OLS runner, used for both baseline and extended specs."""
    X = sm.add_constant(df[x_cols])
    y = df[y_col]
    model = sm.OLS(y, X)
    return model.fit(cov_type="HAC", cov_kwds={"maxlags": maxlags})


if __name__ == "__main__":
    df = build_full_dataset(
        returns_path="../data/processed/eurusd_log_returns.csv",
        shocks_path="../data/processed/eurusd_garch_shocks.csv",
        controls_path="../data/processed/control_variables.csv",
    )
    print(f"Aligned sample size (with controls): {len(df)} observations\n")

    # Re-estimate the baseline on THIS SAME sample, for a fair beta1 comparison
    print("="*70)
    print("BASELINE (re-estimated on controls-aligned sample)")
    print("="*70)
    result_baseline = run_ols(df, x_cols=["delta_y_t", "r_t"])
    print(result_baseline.summary())

    # Extended specification with controls
    print("\n" + "="*70)
    print("EXTENDED (with diff_rate and r_dxy)")
    print("="*70)
    result_extended = run_ols(df, x_cols=["delta_y_t", "r_t", "diff_rate", "r_dxy"])
    print(result_extended.summary())

    # Side-by-side beta1 comparison
    print("\n" + "="*70)
    print("BETA1 (delta_y_t) COMPARISON")
    print("="*70)
    b1_before = result_baseline.params["delta_y_t"]
    p1_before = result_baseline.pvalues["delta_y_t"]
    b1_after = result_extended.params["delta_y_t"]
    p1_after = result_extended.pvalues["delta_y_t"]
    print(f"Before controls: beta1 = {b1_before:.4f}  (p = {p1_before:.4f})")
    print(f"After controls:  beta1 = {b1_after:.4f}  (p = {p1_after:.4f})")

    df.to_csv("../data/processed/regression_dataset_extended.csv")
