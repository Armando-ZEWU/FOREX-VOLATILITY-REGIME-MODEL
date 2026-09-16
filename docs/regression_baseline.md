# Baseline Regression — r(t+1) on GARCH Volatility Shock

*Companion document to `methodology.md` and `docs/GARCH_1_1.md`. This log
uses the final GARCH(1,1) output documented in `GARCH_1_1.md` (Student's t
specification, ν ≈ 7.04) as its direct input — specifically, the
`conditional_volatility` series σ(t) from that model, saved in
`data/processed/eurusd_garch_shocks.csv`.*

## 1. Objective

Test whether the GARCH-estimated volatility level shift explains the
following day's EUR/USD return — a baseline specification, without control
variables, as decided in `methodology.md` (section 7): control variables
(rate differential, DXY) are deliberately withheld at this stage to avoid
confounding the estimate of the volatility shock's own effect.

## 2. Specification

r(t+1) = α + β₁·ΔY(t) + β₂·r(t) + u(t)

Where:
- **r(t)**: EUR/USD daily log return (×100), from `features.py`
- **ΔY(t)** = ln(σ(t) / σ(t−1)): log-change in the GARCH conditional
  volatility σ(t). **Uses σ(t), the conditional volatility level, not the
  standardized residual z(t)** — see `methodology.md` section 4.3 and the
  discussion below for why.
- **r(t+1)**: EUR/USD daily log return realized the following trading day
  (the outcome variable)

### 2.1 Why σ(t), not the standardized residual z(t)

The GARCH model produces two series with opposite statistical properties:
- `conditional_volatility` σ(t) — a persistent, slow-moving **level**
  (autocorrelated by construction — that is the entire point of GARCH)
- `standardized_residual` z(t) — the cleaned **shock**, which behaves close
  to white noise if the GARCH is well specified (confirmed in
  `GARCH_1_1.md`, section 8: no remaining ARCH effect)

Taking a "variation" of z(t) would compute the change in an already-clean
noise series — not economically meaningful. ΔY(t) as a *level-shift*
signal requires the persistent series, σ(t).

## 3. Data alignment

- `r_t_plus_1` built via `shift(-1)` (a forward/lead operation) on the
  return series — explicitly NOT a lag. Documented in code comments to
  avoid an inversion of the causal direction (choc at t explains return at
  t+1, not the reverse).
- Final sample after alignment and dropping edge NaNs: **4,173
  observations** (from the original 4,175 log returns).

## 4. Estimation method

OLS via `statsmodels`, with **HAC (Newey-West) standard errors**,
`maxlags=5`. Chosen over plain OLS standard errors because financial
return residuals commonly exhibit heteroskedasticity and/or residual
autocorrelation, which would otherwise understate standard errors and
inflate apparent significance (a well-documented risk of false positives
in empirical finance).

## 5. Results

```
R-squared:            0.001
Adj. R-squared:       0.000
F-statistic:          0.976   (Prob = 0.377)

               coef      std err      z       P>|z|
const        -0.0051     0.008     -0.648     0.517
delta_y_t    -0.1546     0.240     -0.644     0.519
r_t           0.0206     0.017      1.231     0.218
```

- **Model not jointly significant** (F-test p = 0.377)
- **β₁ (delta_y_t): -0.1546, p = 0.519 — not significant.** No detected
  predictive effect of the volatility level shift on next-day return
  direction.
- **β₂ (r_t): 0.0206, p = 0.218 — not significant.** No detected momentum
  or mean-reversion at a 1-day horizon.
- Residual diagnostics: Jarque-Bera p ≈ 1.6e-126 (residuals strongly
  non-normal, excess kurtosis ≈ 4.8) — expected given the fat-tailed
  nature of FX returns already documented in `GARCH_1_1.md`; consistent
  with, not contradicting, the earlier decision to model returns'
  volatility (not the regression residuals here) with a Student's t
  distribution.

## 6. Interpretation

This is a **null result on direction**, not a failed model. It is
consistent with the weak-form market efficiency hypothesis stated at the
project's outset (`methodology.md`, section 2): on a market as liquid as
EUR/USD spot, next-day return **direction** is expected to be close to
unpredictable from contemporaneous volatility level or the prior day's
return alone. This aligns with the well-documented empirical finding that
structural exchange-rate models struggle to beat a random walk at short
horizons (Meese & Rogoff, 1983).

**What this does NOT undermine**: the project's objective (a) — measuring
a market fear/volatility shift quantitatively — was already achieved and
validated in `GARCH_1_1.md`, independently of whether that shift predicts
return direction. This regression tests one specific, falsifiable use of
that measurement; it returning null is itself a valid, documented finding,
not a reason to keep adding variables until something becomes significant
(a p-hacking risk explicitly avoided here).

## 7. What this does NOT settle

- Whether ΔY(t) explains return **magnitude** (|r(t+1)|) rather than
  direction — untested at this stage, and a more theoretically natural
  target given that GARCH itself is a volatility-magnitude model.
- Whether control variables (rate differential, DXY) change this result —
  to be tested next, per `methodology.md` section 7, with β₁ compared
  before/after their addition.
- Whether volatility regimes (normal/bubble/panic) can still be
  meaningfully detected from σ(t) or ΔY(t), independently of return
  predictability — a separate question from this regression, addressed in
  a later stage (HMM / Markov-switching).

## 8. Files produced at this stage

- `src/regression.py` — dataset construction (`build_regression_dataset`)
  and baseline OLS estimation (`run_baseline_regression`)
- `data/processed/regression_dataset_baseline.csv` — aligned regression
  dataset (r_t, delta_y_t, r_t_plus_1)
