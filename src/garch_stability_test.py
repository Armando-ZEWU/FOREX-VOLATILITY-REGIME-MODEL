"""
garch_stability_test.py
Tests the temporal stability of the GARCH(1,1) Student's t model by
re-estimating it independently on 5 equal, contiguous sub-periods of
the EUR/USD log return series (835 observations each, chosen because
4175 / 5 = 835 exactly -- avoiding an uneven split or an arbitrary
truncation that unequal periods would require).

This test belongs to objective (a) of the project (validating the
measurement tool itself), not (b) -- see docs/methodology.md and the
discussion preceding this script. It complements the limitation already
flagged in docs/GARCH_1_1.md (section 9): persistence (alpha+beta) is
sensitive to the distributional assumption; this test checks whether it
is ALSO sensitive to the time period used for calibration.
"""

import pandas as pd
import numpy as np
from garch_model import fit_garch


def split_into_equal_periods(returns, n_periods=5):
    """
    Split a returns series into n_periods equal, contiguous, non-overlapping
    chunks, in chronological order. Raises if the series length is not
    evenly divisible by n_periods (by design -- avoids silently truncating
    data or creating unequal periods).
    """
    n = len(returns)
    if n % n_periods != 0:
        raise ValueError(
            f"Series length ({n}) is not evenly divisible by {n_periods}. "
            f"Adjust n_periods or explicitly decide how to handle the "
            f"remainder before proceeding."
        )
    chunk_size = n // n_periods
    periods = []
    for i in range(n_periods):
        chunk = returns.iloc[i * chunk_size: (i + 1) * chunk_size]
        periods.append(chunk)
    return periods


def summarize_garch_result(result, label):
    params = result.params
    return {
        "period": label,
        "start_date": result.model._y_series.index[0].date(),
        "end_date": result.model._y_series.index[-1].date(),
        "n_obs": result.nobs,
        "omega": params.get("omega"),
        "alpha": params.get("alpha[1]"),
        "beta": params.get("beta[1]"),
        "nu": params.get("nu"),
        "alpha_plus_beta": params.get("alpha[1]", 0) + params.get("beta[1]", 0),
        "half_life_days": np.log(0.5) / np.log(params.get("alpha[1]", 0) + params.get("beta[1]", 0)),
        "log_likelihood": result.loglikelihood,
        "aic": result.aic,
    }


if __name__ == "__main__":
    returns = pd.read_csv(
        "../data/processed/eurusd_log_returns.csv",
        index_col="Date", parse_dates=True
    )["log_return"]

    periods = split_into_equal_periods(returns, n_periods=5)

    summaries = []
    for i, period_returns in enumerate(periods, start=1):
        label = f"Period {i}"
        print(f"\nFitting GARCH(1,1) Student's t on {label} "
              f"({period_returns.index[0].date()} to {period_returns.index[-1].date()}, "
              f"n={len(period_returns)})...")
        result = fit_garch(period_returns, dist="t")
        summaries.append(summarize_garch_result(result, label))

    comparison = pd.DataFrame(summaries).set_index("period")
    print("\n" + "="*90)
    print("STABILITY COMPARISON ACROSS 5 EQUAL SUB-PERIODS")
    print("="*90)
    print(comparison.to_string())

    comparison.to_csv("../data/processed/garch_stability_comparison.csv")
