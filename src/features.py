"""
features.py
Computes log returns from raw price data.
"""

import numpy as np
import pandas as pd


def compute_log_returns(price_df, price_col="Close", scale_pct=True):
    """
    Compute log returns from a price series.

    Parameters
    ----------
    price_df : pd.DataFrame
        DataFrame with a price column, indexed by date.
    price_col : str
        Name of the column containing prices.
    scale_pct : bool
        If True, multiplies returns by 100 (common convention for GARCH
        estimation — helps numerical optimizers converge, since raw log
        returns are very small numbers e.g. 0.0005).

    Returns
    -------
    pd.Series
        Log returns, named 'log_return'.
    """
    prices = price_df[price_col]
    log_returns = np.log(prices / prices.shift(1)).dropna()
    log_returns.name = "log_return"

    if scale_pct:
        log_returns = log_returns * 100

    return log_returns


if __name__ == "__main__":
    raw = pd.read_csv("../data/raw/eurusd_daily.csv", index_col="Date", parse_dates=True)
    returns = compute_log_returns(raw)
    returns.to_csv("../data/processed/eurusd_log_returns.csv")
    print(returns.describe())
