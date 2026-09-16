"""
garch_model.py
Calibrates a GARCH(1,1) model on EUR/USD log returns and extracts
the conditional volatility and standardized residual (the "shock").

DECISION (documented in docs/GARCH_1_1.md, section 8): the retained
model uses Student's t innovations (nu ~ 7.04), not Normal — it
significantly outperforms the Normal specification on AIC/BIC and
matches the empirical kurtosis of the residuals. The __main__ block
below reflects that decision explicitly, so the CSV it writes always
corresponds to the model actually documented as final.
"""

import pandas as pd
from arch import arch_model


def fit_garch(returns, p=1, q=1, dist="t"):
    """
    Fit a GARCH(p, q) model on a returns series.

    Parameters
    ----------
    returns : pd.Series
        Log returns (already scaled, e.g. x100 — see features.py).
    p, q : int
        GARCH order. (1, 1) is the standard starting point.
    dist : str
        Error distribution. Default is 't' (Student's t) — this is the
        model retained after comparison with 'normal' (see
        docs/GARCH_1_1.md). Pass dist='normal' explicitly if you need
        to reproduce the earlier, discarded specification for
        comparison purposes.

    Returns
    -------
    result : arch.univariate.base.ARCHModelResult
        The fitted model result object.
    """
    model = arch_model(returns, vol="Garch", p=p, q=q, dist=dist, mean="Constant")
    result = model.fit(disp="off")
    return result


def extract_shock(result):
    """
    Extract the conditional volatility and the standardized residual
    (the "shock", cleaned of mechanical volatility inertia) from a
    fitted GARCH result.

    The standardized residual z(t) = residual(t) / conditional_vol(t)
    is what should behave like i.i.d. noise IF the GARCH specification
    is correctly capturing the volatility dynamics. This is your
    "fear shock" variable — not the raw conditional volatility itself.

    Returns
    -------
    pd.DataFrame
        Columns: conditional_volatility, residual, standardized_residual
    """
    out = pd.DataFrame({
        "conditional_volatility": result.conditional_volatility,
        "residual": result.resid,
    })
    out["standardized_residual"] = out["residual"] / out["conditional_volatility"]
    return out


if __name__ == "__main__":
    returns = pd.read_csv(
        "../data/processed/eurusd_log_returns.csv",
        index_col="Date", parse_dates=True
    )["log_return"]

    # Explicit: this is the retained/final specification (Student's t).
    result = fit_garch(returns, dist="t")
    print(result.summary())

    shocks = extract_shock(result)
    shocks.to_csv("../data/processed/eurusd_garch_shocks.csv")
    print("\nShock series saved (Student's t specification — final model).")
    print(shocks.tail())