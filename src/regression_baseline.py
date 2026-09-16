"""
regression.py
Estimates the baseline (no control variables) OLS regression:

    r(t+1) = alpha + beta1 * DeltaY(t) + beta2 * r(t) + u(t)

where:
    r(t)      = EUR/USD daily log return at time t
    DeltaY(t) = log-change in GARCH conditional volatility,
                ln(sigma(t) / sigma(t-1))  -- the volatility "level shift"
                signal (see docs/GARCH_1_1.md and methodology.md, section 4.3
                for why conditional_volatility, not the standardized
                residual, is the correct series here)
    r(t+1)    = EUR/USD daily log return at time t+1 (the outcome)

This is a baseline specification WITHOUT control variables (rate
differential, DXY, etc.), by design (see methodology.md section 7):
the goal is to see what the volatility shock alone explains before
adding controls that could confound the estimate of beta1.
"""

import pandas as pd
import numpy as np
import statsmodels.api as sm


def build_regression_dataset(returns_path, shocks_path):
    """
    Build the aligned dataset for the regression.

    Parameters
    ----------
    returns_path : str
        Path to the log returns CSV (from features.py).
    shocks_path : str
        Path to the GARCH shocks CSV (from garch_model.py), containing
        the 'conditional_volatility' column.

    Returns
    -------
    pd.DataFrame
        Columns: r_t, delta_y_t, r_t_plus_1 — one row per date t,
        with r_t_plus_1 being the return realized the NEXT trading day.
        Rows with any missing value (start/end of sample, due to the
        lag/lead operations) are dropped.
    """
    returns = pd.read_csv(returns_path, index_col="Date", parse_dates=True)["log_return"]
    sigma = pd.read_csv(shocks_path, index_col="Date", parse_dates=True)["conditional_volatility"]

    df = pd.DataFrame({"r_t": returns, "sigma_t": sigma})

    # DeltaY(t) = log-change in conditional volatility
    df["delta_y_t"] = np.log(df["sigma_t"] / df["sigma_t"].shift(1))

    # r(t+1): the return realized on the NEXT trading day relative to row t.
    # shift(-1) pulls the following row's value up to the current row —
    # this is the forward-looking (lead) operation, not a lag.
    df["r_t_plus_1"] = df["r_t"].shift(-1)

    df = df.dropna(subset=["delta_y_t", "r_t_plus_1", "r_t"])
    return df[["r_t", "delta_y_t", "r_t_plus_1"]]


def run_baseline_regression(df):
    """
    Estimate r(t+1) = alpha + beta1 * delta_y_t + beta2 * r_t + u(t) via OLS.

    Uses HAC (Newey-West) standard errors, since financial return
    residuals commonly exhibit heteroskedasticity and/or residual
    autocorrelation that plain OLS standard errors would understate.

    Returns
    -------
    result : statsmodels.regression.linear_model.RegressionResultsWrapper
    """
    X = df[["delta_y_t", "r_t"]]
    X = sm.add_constant(X)
    y = df["r_t_plus_1"]

    model = sm.OLS(y, X)
    # maxlags=5: standard choice for daily data (~one trading week);
    # revisit if residual diagnostics suggest otherwise.
    result = model.fit(cov_type="HAC", cov_kwds={"maxlags": 5})
    return result


if __name__ == "__main__":
    df = build_regression_dataset(
        returns_path="../data/processed/eurusd_log_returns.csv",
        shocks_path="../data/processed/eurusd_garch_shocks.csv",
    )
    print(f"Regression sample size: {len(df)} observations\n")

    result = run_baseline_regression(df)
    print(result.summary())

    df.to_csv("../data/processed/regression_dataset_baseline.csv")
