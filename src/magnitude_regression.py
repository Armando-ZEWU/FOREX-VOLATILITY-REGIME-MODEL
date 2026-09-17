"""
magnitude_regression.py
Tests whether the GARCH volatility signal explains next-day return
MAGNITUDE |r(t+1)|, rather than direction (already tested in
regression.py / control_regression.py, both null results).

Two specifications run side by side, per the discussion in
docs/magnitude_regression.md:

  Spec A (delta_y_t): |r(t+1)| = a + b1*DeltaY(t) + b2*|r(t)| + u(t)
      Consistent with the rest of the project's use of the log-change
      in conditional volatility as the "shock" variable.

  Spec B (sigma_t level): |r(t+1)| = a + b1*sigma(t) + b2*|r(t)| + u(t)
      Tests the RAW conditional volatility level directly, since a null
      result on Spec A alone would be ambiguous: it could mean the
      volatility-magnitude link is genuinely weak, OR that taking the
      log-change of an already highly persistent series dilutes a
      relationship that is clearly present at the level. Running both
      side by side disambiguates this.

Control variable: |r(t)|, not signed r(t) -- see docs/magnitude_regression.md
for why the control must also switch to a magnitude measure here (its own
persistence, not momentum/mean-reversion, is what's relevant for
explaining |r(t+1)|).
"""

import pandas as pd
import numpy as np
import statsmodels.api as sm


def build_magnitude_dataset(returns_path, shocks_path):
    """
    Build the aligned dataset for the magnitude regressions.

    Returns
    -------
    pd.DataFrame
        Columns: r_t, abs_r_t, sigma_t, delta_y_t, abs_r_t_plus_1
    """
    returns = pd.read_csv(returns_path, index_col="Date", parse_dates=True)["log_return"]
    sigma = pd.read_csv(shocks_path, index_col="Date", parse_dates=True)["conditional_volatility"]

    df = pd.DataFrame({"r_t": returns, "sigma_t": sigma})
    df["abs_r_t"] = df["r_t"].abs()
    df["delta_y_t"] = np.log(df["sigma_t"] / df["sigma_t"].shift(1))
    df["abs_r_t_plus_1"] = df["r_t"].shift(-1).abs()

    cols = ["r_t", "abs_r_t", "sigma_t", "delta_y_t", "abs_r_t_plus_1"]
    df = df.dropna(subset=cols)
    return df[cols]


def run_ols(df, x_cols, y_col="abs_r_t_plus_1", maxlags=5):
    X = sm.add_constant(df[x_cols])
    y = df[y_col]
    model = sm.OLS(y, X)
    return model.fit(cov_type="HAC", cov_kwds={"maxlags": maxlags})


if __name__ == "__main__":
    df = build_magnitude_dataset(
        returns_path="../data/processed/eurusd_log_returns.csv",
        shocks_path="../data/processed/eurusd_garch_shocks.csv",
    )
    print(f"Sample size: {len(df)} observations\n")

    print("="*70)
    print("SPEC A: |r(t+1)| ~ delta_y_t + |r_t|")
    print("="*70)
    result_a = run_ols(df, x_cols=["delta_y_t", "abs_r_t"])
    print(result_a.summary())

    print("\n" + "="*70)
    print("SPEC B: |r(t+1)| ~ sigma_t (level) + |r_t|")
    print("="*70)
    result_b = run_ols(df, x_cols=["sigma_t", "abs_r_t"])
    print(result_b.summary())

    print("\n" + "="*70)
    print("COMPARISON")
    print("="*70)
    print(f"Spec A - AIC: {result_a.aic:.2f}  BIC: {result_a.bic:.2f}  "
          f"R2: {result_a.rsquared:.4f}")
    print(f"Spec B - AIC: {result_b.aic:.2f}  BIC: {result_b.bic:.2f}  "
          f"R2: {result_b.rsquared:.4f}")

    df.to_csv("../data/processed/magnitude_regression_dataset.csv")
