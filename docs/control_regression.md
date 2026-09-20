# Control Regression — Robustness Check on the Baseline

*Companion document to `methodology.md`, `docs/GARCH_1_1.md`, and
`docs/regression_baseline.md`. This log documents the addition of control
variables (interest rate differential, DXY proxy) to the baseline
regression as a robustness check — NOT a new baseline, an extension of it.
Kept as a separate file from `regression_baseline.md` because the two
answer different questions: the baseline established whether the
volatility shock alone explains next-day returns; this stage asks whether
that (null) result survives the addition of theoretically motivated
confounders.*

## 1. Objective

Test whether adding two control variables — the Fed/ECB interest rate
differential and a broad-dollar proxy for DXY — changes the baseline
result (β₁ on ΔY(t) not significant, model not jointly significant; see
`regression_baseline.md`). The goal is not to search for significance, but
to check whether the null result on ΔY(t) was possibly masking a
confounded relationship.

## 2. Control variable sourcing

All three series retrieved from FRED (same stable CSV endpoint already
used for EUR/USD in `data_loader_fred.py`), avoiding a repeat of the
`yfinance` reliability issue documented in `GARCH_1_1.md` section 2.1:

| Variable | FRED series | Frequency |
|---|---|---|
| Fed funds rate | `DFF` | Daily |
| ECB deposit facility rate | `ECBDFR` | Daily |
| DXY proxy | `DTWEXBGS` | Daily |

### 2.1 Decision: ECB deposit facility rate, not MRO or marginal lending rate

FRED also hosts `ECBMRRFR` (main refinancing rate) and `ECBMLFR` (marginal
lending facility rate). The deposit facility rate (`ECBDFR`) was retained
as it is considered the ECB's de facto reference rate in the ample-liquidity
regime the Eurosystem has operated under for most of the sample period —
consistent with recent literature on rate-differential-based FX models.

### 2.2 Known limitation: DTWEXBGS is not the commercial DXY

`DTWEXBGS` (Nominal Broad U.S. Dollar Index) is **not** the commercial DXY
index. DXY weights a basket of 6 currencies dominated by the euro (~58%
weight); `DTWEXBGS` is a broader trade-weighted basket including
emerging-market currencies. Both proxy "dollar strength" but are not
interchangeable. Retained as an accessible, FRED-hosted alternative,
consistent with the project's general sourcing strategy (an imperfect but
well-targeted and reproducible measure over an unreachable proprietary
one — same logic already applied to the volatility proxy itself in
`methodology.md` section 4.2).

## 3. Calendar alignment check

Before merging, checked for date mismatches between the control series and
the EUR/USD return series:

- 2 dates present in controls but absent from EUR/USD returns
  (2010-01-04 — sample start edge effect; 2018-12-24 — a partial trading
  day likely not recorded in FRED's `DEXUSEU`)
- 20 dates present in EUR/USD returns but absent from the controls
  (mostly explained by identifiable US federal closures not reflected in
  `DFF` reporting — e.g. 2012-10-29/30, Hurricane Sandy closures;
  2016-01-22/25/26, Winter Storm Jonas — while FX itself continued trading
  via other financial centers)

**Conclusion**: 22 mismatched dates out of ~4,175 (≈0.5%), all consistent
with identifiable calendar effects rather than a data quality issue.
Handled via inner join (see section 4); not further investigated.

## 4. Specification decisions

Full model:

r(t+1) = α + β₁·ΔY(t) + β₂·r(t) + β₃·diff_rate(t) + β₄·r_dxy(t) + u(t)

### 4.1 diff_rate(t): level, not variation

diff_rate(t) = fed_rate(t) − ecb_rate(t)

Decision: use the **level**, not the day-to-day variation. Rationale: policy
rates are step functions, changing only at rare policy meeting dates — a
variation-based series would be zero on nearly all days and only
non-zero at policy shocks, which is a fundamentally different (event-based)
signal than a continuous UIP-style differential. The level is also the
conventional choice in the uncovered interest rate parity (UIP) literature,
which compares rate *levels*, not rate changes.

### 4.2 r_dxy(t): log return, not level

r_dxy(t) = ln(dxy_proxy(t) / dxy_proxy(t−1))

Decision: use the log return, not the raw index level. Rationale: `dxy_proxy`
is a price-like index, structurally similar to EUR/USD itself — using its
level would risk the same spurious-regression problem (non-stationarity,
Granger & Newbold 1974) already identified and corrected for EUR/USD in
`methodology.md` section 3.2. Consistency of treatment across all
price-like series in the model.

### 4.3 Re-estimating the baseline on the controls-aligned sample

The controls-aligned dataset has 4,153 observations, vs. 4,173 in the
original baseline (`regression_baseline.md`) — a small reduction due to
the calendar mismatches in section 3. To make the β₁ before/after
comparison meaningful, **the baseline model was re-estimated on this same
4,153-observation sample**, rather than compared directly against the
original 4,173-observation baseline result. This isolates the effect of
adding controls from the effect of a changed sample.

## 5. Results

### 5.1 Baseline, re-estimated on the aligned sample (n = 4,153)

```
F-statistic: 0.8512   (p = 0.427)   -- not jointly significant
delta_y_t:  coef = -0.1329   p = 0.578   -- not significant
r_t:        coef =  0.0196   p = 0.243   -- not significant
```

Consistent with the original baseline result (`regression_baseline.md`):
β₁ ≈ -0.13 to -0.15 depending on exact sample, never significant.

### 5.2 Extended specification with controls (n = 4,153)

```
F-statistic: 0.7265   (p = 0.574)   -- not jointly significant
AIC: 6337   BIC: 6369   (vs. 6334 / 6353 for the re-estimated baseline
                          -- AIC/BIC both WORSEN with the added controls)

delta_y_t:  coef = -0.1308   p = 0.584   -- not significant
r_t:        coef =  0.0235   p = 0.432   -- not significant
diff_rate:  coef =  0.0100   p = 0.257   -- not significant
r_dxy:      coef =  0.8591   p = 0.865   -- not significant (least of all)
```

### 5.3 β₁ stability comparison (the key test of this stage)

| | β₁ (delta_y_t) | p-value |
|---|---|---|
| Before controls | -0.1329 | 0.578 |
| After controls | -0.1308 | 0.584 |

β₁ changes by ≈1.6% in magnitude, p-value essentially unchanged. **No
evidence of confounding** — the volatility shock's null effect on next-day
return direction is not an artifact of omitting the rate differential or
dollar strength.

## 6. Interpretation

This is a **robustness confirmation of a null result**, not a new finding.
Three things are now established together:

1. The baseline null result (no direction predictability from ΔY(t) or
   r(t) alone) is not due to omitted-variable bias from the two most
   theoretically obvious FX confounders.
2. Neither `diff_rate` nor `r_dxy` themselves predict next-day EUR/USD
   direction at this horizon — consistent with the broader empirical
   literature on the difficulty of beating a random walk in FX at short
   horizons (Meese & Rogoff, 1983).
3. Model fit (AIC/BIC) actually **worsens** with the added controls,
   reinforcing that their inclusion is not statistically justified for
   this specific target variable (next-day return direction) — a
   deliberate stopping point, not a prompt to keep adding variables in
   search of significance (a p-hacking risk explicitly avoided, as noted
   in `regression_baseline.md` section 6).

**What this does NOT undermine**: as with the baseline, this null result on
*direction* says nothing about whether ΔY(t) explains return *magnitude*
(|r(t+1)|) or about the market-regime detection objective — both remain
open, separate questions per `methodology.md` section 7.

### 6.1 What the two control coefficients mean economically

**diff_rate (coef = 0.0100, p = 0.257)**: economic theory (uncovered
interest rate parity, UIP) predicts a relationship between the interest
rate differential and expected currency returns. Taking this coefficient
at face value despite its lack of significance: a 1 percentage point
widening of the Fed-ECB rate differential (a fairly large policy move,
larger than most single rate decisions) would be associated with only a
0.01% shift in next-day expected return — an effect too small to matter
economically even before considering that it is statistically
indistinguishable from zero. This null result is not an anomaly specific
to this project: it echoes a well-known puzzle in international finance
(the "forward premium puzzle" / Fama, 1984), where UIP frequently fails to
hold, or holds with an unexpected sign, in short-horizon empirical tests.
This project's finding is consistent with that broader, decades-old
literature rather than contradicting it.

**r_dxy (coef = 0.8591, p = 0.865)**: the coefficient's 95% confidence
interval runs from about -9.0 to +10.7. In plain terms, this range is
consistent with everything from "the dollar index and next-day EUR/USD
returns move strongly against each other" to "they move strongly
together" to "there is no relationship at all" — the data at this daily
horizon simply do not pin down the relationship in either direction. This
is a materially different (and more informative) statement than just
"not significant": it says the estimate carries essentially no usable
precision, not merely a small or moderate one.

**Practical takeaway for someone building on this model**: at a one-day
horizon, neither the rate differential nor broad dollar strength provide a
usable directional signal for EUR/USD, over and above what is already
known (nothing) from the volatility shock and momentum terms alone. This
does not mean these variables are economically irrelevant to exchange
rates in general — the literature is clear that they matter at other
horizons and in other specifications — only that, in this specific
one-day-ahead, level/return specification, they add no exploitable
information.

### 6.2 A robustness check on standard errors, prompted by diff_rate's high autocorrelation

`diff_rate` (the level of the Fed-ECB rate differential) is extremely
persistent — autocorrelation of 0.998 at lag 1, still 0.98 at lag 20 (an
expected property of a policy-rate-level series, which moves in rare,
discrete steps and stays flat between them; see the same point made about
its step-function nature in `methodology.md`, section 4.1). This raised a
concern: the HAC (Newey-West) standard errors reported in section 5 used
`maxlags=5`, which may be insufficient to fully correct for
autocorrelation this persistent — an under-corrected standard error would
be too small, potentially overstating significance.

**Check performed**: re-running the extended specification with
`maxlags=10` and `maxlags=20` in `run_ols()`. The result does not change
in any way that matters: `diff_rate` and every other coefficient remain
far from conventional significance thresholds regardless of the lag
choice. This is the expected outcome, not a surprising one — `maxlags=5`
being too short would, if anything, have *understated* the true standard
errors, meaning the already-not-significant result would only become
*more* clearly non-significant with a longer lag window, never less. The
robustness check confirms this rather than overturning anything in
section 5-6's conclusions.

## 7. Files produced at this stage

- `src/control_variables_loader.py` — FRED loaders for `DFF`, `ECBDFR`,
  `DTWEXBGS`
- `src/control_regression.py` — merged dataset construction
  (`build_full_dataset`), generic HAC-robust OLS runner (`run_ols`),
  baseline re-estimation and extended model comparison
- `data/raw/fed_rate.csv`, `data/raw/ecb_rate.csv`, `data/raw/dxy_proxy.csv`
- `data/processed/control_variables.csv`
- `data/processed/regression_dataset_extended.csv`
