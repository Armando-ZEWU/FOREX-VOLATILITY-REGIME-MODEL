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

    # ---- Illustrative comparison: what if we assumed each regime with
    # certainty, instead of using the model's actual mixture? ----
    # NOT the operational range (see ms_garch_forecast.R's methodological
    # choice) -- shown only to make the value of regime-awareness visible,
    # using each regime's own long-run volatility level from docs/ms_garch.md
    # section 4.2, scaled to match the same ~2.0x-vol multiplier implied by
    # the actual Risk() interval (rather than re-deriving a full per-regime
    # Student's t quantile, which would need each regime's own nu and
    # h=1 conditional vol -- an approximation, clearly labeled as such).
    implied_multiplier_low = inputs["return_q_low"] / inputs["vol_forecast"]
    implied_multiplier_high = inputs["return_q_high"] / inputs["vol_forecast"]

    sigma_regime1 = 0.206  # long-run vol, low-vol regime (docs/ms_garch.md, 4.2)
    sigma_regime2 = 0.730  # long-run vol, high-vol regime (docs/ms_garch.md, 4.2)

    print("\n--- Illustrative only: range if each regime were assumed with certainty ---")
    print("(approximation using each regime's long-run vol level and the same")
    print(" quantile multiplier as the actual mixture forecast -- not the")
    print(" model's actual per-regime forecast, which would require each")
    print(" regime's own nu and h=1 conditional variance)")
    for label, sigma in [("Low-volatility regime (calm)", sigma_regime1),
                          ("High-volatility regime (stress)", sigma_regime2)]:
        r_low_illustr = implied_multiplier_low * sigma
        r_high_illustr = implied_multiplier_high * sigma
        p_min_illustr, p_max_illustr = compute_price_range(
            last_price, r_low_illustr, r_high_illustr
        )
        width_pct = (p_max_illustr - p_min_illustr) / last_price
        print(f"  {label}: [{p_min_illustr:.4f}, {p_max_illustr:.4f}] "
              f"(width: {width_pct:.2%})")

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
