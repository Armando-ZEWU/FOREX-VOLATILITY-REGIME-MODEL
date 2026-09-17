# GARCH Temporal Stability Test

*Companion document to `docs/GARCH_1_1.md` (specifically its section 9,
"Known limitations", which first flagged that persistence α+β is
sensitive to the distributional assumption). This document extends that
limitation check to a different dimension: is persistence ALSO sensitive
to the time period used for calibration, independent of the Normal vs.
Student's t choice already resolved?*

## 1. Why this test belongs to objective (a), not (b)

This is a validation test on the measurement tool itself (the GARCH
model), not on its operational use (price ranges, regime detection). It
asks whether the single GARCH(1,1) calibrated on the full 2010-2026 sample
— the one used throughout `regression_baseline.md`,
`control_regression.md`, and `magnitude_regression.md` — is a stable
description of volatility dynamics across time, or whether it is an
average that poorly represents any single sub-period.

This was deliberately run **before** choosing a regime-detection method
(HMM vs. Markov-Switching GARCH), on the reasoning that the stability
result itself should inform that choice: applying a simple HMM on top of
an unstable global GARCH's σ(t) would inherit that instability as a hidden
bias, whereas a genuinely unstable GARCH is itself an argument for a
Markov-Switching GARCH (which re-estimates α, β, ω per regime) rather than
a simpler two-stage approach.

## 2. Method

### 2.1 Splitting choice: 5 equal periods, not 4

The full sample has 4,175 observations. An initial 4-period split was
considered and rejected: 4175 / 4 = 1043.75, which is not an integer —
using it would force either an arbitrary truncation of the sample or
unequal period sizes without a principled reason for the inequality, both
of which would undermine the neutrality the split is meant to provide.
5 periods divide evenly: 4175 / 5 = 835 exactly. This was chosen precisely
for this reason, not for any substantive reason related to the number 5.

### 2.2 Chronological, non-overlapping, equal-size split (no cherry-picking)

Periods were defined purely by chronological order and equal size — not by
economically motivated breakpoints (e.g. "before/after COVID",
"before/after the Eurozone debt crisis"). This was a deliberate choice to
avoid selection bias: choosing break dates based on known economic events
risks unconsciously picking dates that confirm a story already assumed
rather than testing stability neutrally.

Resulting periods:

| Period | Date range | n |
|---|---|---|
| 1 | 2010-01-05 to 2013-05-01 | 835 |
| 2 | 2013-05-02 to 2016-08-29 | 835 |
| 3 | 2016-08-30 to 2020-01-07 | 835 |
| 4 | 2020-01-08 to 2023-05-10 | 835 |
| 5 | 2023-05-11 to 2026-09-11 | 835 |

Each period's GARCH(1,1) with Student's t innovations was estimated
independently, using the same specification already validated in
`GARCH_1_1.md`.

## 3. Results

| Period | ω | α | β | ν | α+β | Half-life (days) |
|---|---|---|---|---|---|---|
| 1 | 0.004378 | 0.0283 | 0.9612 | 12.59 | 0.9895 | 65.5 |
| 2 | 0.000382 | 0.0386 | 0.9614 | 5.95 | **0.999991** | **80,366 (not meaningful — see section 4)** |
| 3 | 0.000233 | 0.0170 | 0.9809 | 10.58 | 0.9979 | 335.1 |
| 4 | 0.003341 | 0.0720 | 0.9192 | 6.89 | 0.9912 | 78.5 |
| 5 | 0.001878 | 0.0408 | 0.9494 | 5.54 | 0.9902 | 70.5 |

## 4. Diagnosing the Period 2 anomaly

Period 2's implied half-life (≈80,366 days, ≈220 years) is not
economically meaningful and was investigated before being interpreted.
Full model summary for Period 2:

```
omega      coef = 0.000382   p = 0.519   -- NOT significant
alpha[1]   coef = 0.0386     p = 1.25e-8 -- significant, in line with other periods
beta[1]    coef = 0.9614     p < 0.001   -- significant, in line with other periods
nu         coef = 5.949      p = 2.57e-6 -- significant
```

**Root cause**: only ω is not statistically distinguishable from zero on
this sub-sample. The GARCH's long-run (unconditional) variance is given
by ω / (1 − α − β). When α+β is very close to 1 (here, 0.999991) and ω is
close to zero and imprecisely estimated, this ratio becomes numerically
unstable — even a tiny change in the denominator produces an enormous
swing in the implied half-life. This is a known numerical fragility of
GARCH models operating near the IGARCH boundary (α+β = 1 exactly), not a
sign that the model itself failed.

**Plausible economic context**: 2013-2016 was a historically calm period
for EUR/USD (ECB near-zero/negative rates, few major macro shocks within
this specific window), which likely makes it difficult to precisely pin
down the variance "floor" (ω) when the whole series stays close to that
floor throughout the period.

**Conclusion on Period 2**: α and β themselves remain valid and
interpretable (in line with the other four periods); the derived half-life
figure specifically should be treated as not meaningful and must never be
quoted on its own (e.g. in the README or a written report) without this
explanation attached.

## 5. Overall stability conclusion

Excluding the Period 2 half-life artifact (while keeping its valid α, β
estimates):

| Period | α+β | Half-life reliable? |
|---|---|---|
| 1 | 0.9895 | Yes — 65.5 days |
| 2 | 0.999991 | No — ω not significant, numerically unstable ratio |
| 3 | 0.9979 | Yes — 335.1 days |
| 4 | 0.9912 | Yes — 78.5 days |
| 5 | 0.9902 | Yes — 70.5 days |

**Even excluding the Period 2 artifact, persistence varies substantially
across periods** — from a half-life of ~65-80 days (Periods 1, 4, 5) to
~335 days (Period 3). This is a genuine, non-artifactual finding: **the
single full-sample GARCH(1,1) is not temporally stable**. It represents an
average behavior that does not closely describe any single sub-period,
most notably Period 3 (2016-2020), which shows a persistence roughly 4-5x
longer than the periods surrounding it.

## 6. Implication for the regime-detection model choice

This result directly informs the next stage of the project (regime
detection, per `methodology.md` section 7). A simple HMM applied to σ(t)
generated by the single full-sample GARCH would inherit this instability
as a hidden bias: σ(t) itself would be a somewhat distorted description of
volatility in any given sub-period, before any regime-detection layer is
even applied on top of it.

This finding reinforces the case — already anticipated in the project's
discussion before this test was run — for giving serious consideration to
a **Markov-Switching GARCH** (which re-estimates ω, α, β separately per
regime, directly addressing the instability documented here) rather than
defaulting to the simpler two-stage HMM-on-top-of-a-fixed-GARCH approach,
despite the added implementation complexity of the former.

**This document does not yet make the final method choice** — that
decision, and its justification, is documented separately in the
regime-detection stage itself once made.

## 7. Files produced at this stage

- `src/garch_stability_test.py` — equal-period splitting
  (`split_into_equal_periods`), per-period GARCH fitting and summary
  extraction (`summarize_garch_result`)
- `data/processed/garch_stability_comparison.csv`
