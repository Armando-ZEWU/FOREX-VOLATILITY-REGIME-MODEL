"""
price_range.py
Converts the MS-GARCH(K=2) one-step-ahead forecast (ms_garch_forecast.R)
into an actual EUR/USD price range -- the project's original operational
objective (b), stated at the very start of methodology.md.

Inputs (from R, see docs/ms_garch.md and the price-range discussion):
    - last_price: EUR/USD price on the last observed date
    - return_q_low / return_q_high: 95% predictive interval on the next-day
      log return (%, matching features.py's x100 scale), from the FULL
      predictive distribution (regime-mixture-weighted via Risk(), not
      conditioned on an assumed single regime -- see ms_garch_forecast.R
      for why)
    - vol_forecast, prob_regime_1_current, prob_regime_2_current: context

Output: P_min, P_max -- the actual EUR/USD price range implied by the
model, plus an illustrative (not operational) comparison of what the
range would look like under each regime assumed with certainty, to make
the value of regime-awareness visible.
"""

import pandas as pd
import numpy as np


def load_forecast_inputs(path="../data/processed/ms_garch_price_range_inputs.csv"):
    df = pd.read_csv(path)
    return df.iloc[0]


def compute_price_range(last_price, return_q_low, return_q_high):
    """
    Convert a log-return interval (in %, i.e. already x100) into an
    actual price range.

    r = ln(P_next / P_last)  =>  P_next = P_last * exp(r)
    Dividing by 100 undoes the x100 scaling applied in features.py.

    Returns
    -------
    (P_min, P_max) : tuple of float
    """
    r_low = return_q_low / 100
    r_high = return_q_high / 100
    p_min = last_price * np.exp(r_low)
    p_max = last_price * np.exp(r_high)
    return p_min, p_max


if __name__ == "__main__":
    inputs = load_forecast_inputs()

    last_price = inputs["last_price"]
    last_date = inputs["last_date"]
    confidence_level = inputs["confidence_level"]

    p_min, p_max = compute_price_range(
        last_price, inputs["return_q_low"], inputs["return_q_high"]
    )

    print(f"As of {last_date}, EUR/USD = {last_price:.4f}")
    print(f"Current regime probabilities: "
          f"low-vol = {inputs['prob_regime_1_current']:.1%}, "
          f"high-vol = {inputs['prob_regime_2_current']:.1%}")
    print(f"Model-implied volatility forecast (regime-weighted): "
          f"{inputs['vol_forecast']:.4f}")
    print()
    print(f"{confidence_level:.0%} price range for the next trading day:")
    print(f"  [{p_min:.4f}, {p_max:.4f}]")
    print(f"  Width: {(p_max - p_min):.4f} "
          f"({(p_max - p_min) / last_price:.2%} of current price)")

    # ---- TRUE regime-conditional comparison (Haas et al. 2004a recursion) ----
    # Replaces the earlier "illustrative only" approximation, which used each
    # regime's long-run volatility level and the mixture's quantile multiplier.
    # This version uses the ACTUAL one-step-ahead regime-conditional forecast
    # (own sigma_k(t+1) and own nu_k per regime), computed in
    # ms_garch_forecast.R section 6 and validated there against the Risk()
    # mixture result (exact match on implied volatility: 0.3055 vs 0.3055).
    regime_forecast = pd.read_csv(
        "../data/processed/ms_garch_regime_conditional_forecast.csv"
    )
    target_cl = confidence_level  # match the operational confidence level (0.95)
    regime_forecast_cl = regime_forecast[
        np.isclose(regime_forecast["confidence_level"], target_cl)
    ]

    print("\n--- Regime-conditional forecast (exact, not illustrative) ---")
    print("(if tomorrow were certainly in this regime -- not the operational")
    print(" forecast, which correctly mixes both regimes by their current")
    print(" probability, but a genuine per-regime forecast, not an approximation)")
    for _, row in regime_forecast_cl.iterrows():
        label = "Low-volatility regime (calm)" if row["regime"] == "1_calm" \
            else "High-volatility regime (stress)"
        p_min_r, p_max_r = compute_price_range(
            last_price, row["return_q_low"], row["return_q_high"]
        )
        width_pct = (p_max_r - p_min_r) / last_price
        print(f"  {label}: [{p_min_r:.4f}, {p_max_r:.4f}] (width: {width_pct:.2%})")

    # Save the operational result
    result = pd.DataFrame([{
        "date": last_date,
        "last_price": last_price,
        "confidence_level": confidence_level,
        "p_min": p_min,
        "p_max": p_max,
        "range_width_pct": (p_max - p_min) / last_price,
    }])
    result.to_csv("../data/processed/price_range_output.csv", index=False)