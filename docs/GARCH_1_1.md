# GARCH(1,1) — Detailed Working Log

*Companion document to `methodology.md`. This log captures the full process
— including data issues, bugs, wrong turns, and corrections — not just the
final result. The goal is to document the reasoning, not just the
conclusion.*

## 1. Objective

Specify and validate a GARCH(1,1) model on EUR/USD daily log returns, in
order to (a) isolate the volatility shock from its mechanical inertia
(clustering), and (b) obtain a standardized residual series usable as a
"fear shock" input variable for the later return regression.

## 2. Data pipeline

### 2.1 First attempt: yfinance — failed

Initial `data_loader.py` used `yfinance` with ticker `EURUSD=X`. Failed with:

```
Failed to get ticker 'EURUSD=X' reason: Expecting value: line 1 column 1 (char 0)
Exception('%ticker%: No timezone found, symbol may be delisted')
```

Diagnosis: not an actual delisting — a known, recurring issue where
`yfinance`'s handling of Yahoo's backend API breaks after Yahoo-side
changes, particularly for FX tickers (`=X` suffix), which are less
reliably supported than equity tickers.

**Decision**: switch to FRED as the primary data source rather than
continuing to debug yfinance — more stable, and a better-justified source
academically (official central-bank-adjacent data vs. scraped data).

### 2.2 Switch to FRED — successful

New loader (`data_loader_fred.py`) pulls the `DEXUSEU` series directly from
FRED's CSV endpoint. Result: 4,176 daily observations retrieved
successfully (2010-01-01 to 2026-09-11).

### 2.3 Price convention check

**Issue identified**: FRED's `DEXUSEU` is quoted as USD per EUR (e.g. 1.16
= 1 EUR buys 1.16 USD). This is the **opposite** convention from the
illustrative example used earlier in the project ("1$ s'échange contre
1.1€"), which implicitly quoted USD per EUR... no — quoted EUR per USD.

**Decision**: keep FRED's native convention (USD per EUR), since it matches
the standard market convention for "EUR/USD" (EUR as base currency, USD as
quote currency) used by traders, Bloomberg, Reuters, etc. The original
illustrative example from earlier in the project used the opposite
convention by mistake — corrected here, documented rather than silently
fixed.

### 2.4 Zero-return check

39 out of 4,175 daily log returns were exactly 0 (≈0.93% of observations).
Checked whether these cluster around known US/EU bank holidays (which
would suggest FRED repeating a stale value) — dates found to be dispersed
with no visible calendar pattern. Conclusion: consistent with FRED's
4-decimal rounding on low-volatility days, not a data quality issue.
Left untouched in the series.

## 3. Return series diagnostics (pre-GARCH)

Log returns (scaled ×100), full sample, n = 4,175:

| Statistic | Value |
|---|---|
| Mean | -0.0052% |
| Std. dev. | 0.518% |
| Min | -2.672% |
| Max | 3.064% |

Mean near zero: consistent with weak-form market efficiency (no exploitable
average drift). Min/max well beyond several standard deviations from the
mean — early visual indication of fat tails, later confirmed formally (see
section 5).

## 4. GARCH(1,1) — Normal distribution (first specification)

```
mu       = -0.00588   (p = 0.394, not significant)
omega    =  0.001446  (p = 0.031)
alpha[1] =  0.0350     (p ≈ 1.6e-9)
beta[1]  =  0.9595     (p < 0.001)

Log-Likelihood = -2900.17
AIC = 5808.34   BIC = 5833.69
```

- μ not significant: consistent with the random-walk expectation for
  returns direction.
- α + β = 0.9945 (< 1, stationarity condition satisfied)
- Implied shock half-life: ln(0.5)/ln(0.9945) ≈ 126 trading days (~6 months)

## 5. Diagnostics — Normal model

### 5.1 A methodological bug and its correction

Initial diagnostic script called `result.arch_lm_test(lags=10)` **without**
`standardized=True`. This runs the ARCH-LM test on the raw mean-model
residuals rather than the GARCH-standardized residuals, which will almost
always reject strongly for financial return series — not because the GARCH
is misspecified, but because that's expected on any returns series before
volatility modeling. This produced a seemingly contradictory result:

| Test | Result |
|---|---|
| Ljung-Box on squared standardized residuals (lags 10, 20) | p = 0.933 / 0.591 — no remaining ARCH effect |
| ARCH-LM (raw residuals, bug) | p ≈ 0.0000 — apparently rejects |

**Correction**: re-ran with `standardized=True`. Result: statistic = 4.14,
p = 0.941 — consistent with the Ljung-Box result. The two tests agree once
both are run on the correctly standardized series. No real model
misspecification; the discrepancy was a test-configuration error, not a
model flaw.

### 5.2 Fat tails

Excess kurtosis of standardized residuals: **1.620** (Normal = 0). QQ-plot
against the Normal distribution shows clear deviation in the tails.
Standardized residual range: -5.91 to +5.02 — under a true Normal
distribution, values at ±5 standard deviations would be virtually
impossible at this sample size.

**Decision**: re-fit with a Student's t innovation distribution.

## 6. GARCH(1,1) — Student's t distribution (second specification)

```
mu       = -0.00578   (p = 0.368, not significant)
omega    =  0.000651  (p = 0.099, NOT significant — down from p=0.031 in Normal model)
alpha[1] =  0.0374     (p ≈ 3.3e-12)
beta[1]  =  0.9611     (p < 0.001)
nu       =  7.0414     (p ≈ 4.1e-22)

Log-Likelihood = -2818.39
AIC = 5646.78   BIC = 5678.46
```

- α + β = 0.9985 (up from 0.9945) → implied half-life ≈ 462 trading days
  (~18 months), nearly 4x longer than under the Normal specification.
  **Noted as a real sensitivity of the model to the distributional
  assumption, not a rounding artifact** — flagged as a limitation.
- ω loses significance under this specification — noted, not dismissed.

## 7. Model comparison and selection

| Metric | Normal | Student's t |
|---|---|---|
| AIC | 5808.34 | **5646.78** |
| BIC | 5833.69 | **5678.46** |
| Log-Likelihood | -2900.17 | **-2818.39** |
| Ljung-Box p (lag 10) | 0.933 | 0.972 |
| ARCH-LM p (standardized) | 0.941 | 0.976 |
| Excess kurtosis (empirical) | 1.620 | 1.831 |

**AIC/BIC decisively favor the Student's t specification** (ΔAIC ≈ 161.6,
ΔBIC ≈ 155.2 — both far beyond conventional significance thresholds for
model comparison).

### 7.1 A second interpretation error, corrected

Initial read of the Student's t diagnostics flagged the empirical excess
kurtosis of 1.831 as "still too high, fat tails not absorbed" — but this
compared the empirical value against 0, which is only the correct
benchmark for a **Normal**-distribution model. For a Student's t model with
ν degrees of freedom, the theoretical excess kurtosis is:

theoretical excess kurtosis = 6 / (ν − 4)

With ν = 7.0414: 6 / 3.0414 ≈ **1.973**

The empirical value (1.831) is close to this theoretical value (1.973) —
this is a **good** result, indicating the fitted ν correctly describes the
actual shape of the residual distribution. The earlier flag was a
diagnostic-threshold error (comparing to the wrong reference), not a real
model deficiency.

## 8. Final decision

**Retained model: GARCH(1,1) with Student's t innovations (ν ≈ 7.04).**

Both the Ljung-Box and standardized ARCH-LM tests confirm no remaining
conditional heteroskedasticity. The empirical kurtosis matches the
model-implied kurtosis closely. AIC/BIC both favor this specification over
the Normal alternative decisively.

The standardized residual series from this model — `standardized_residual`
in `data/processed/eurusd_garch_shocks.csv` — is the volatility "shock"
variable to be used as the ΔY(t) input in the next stage (return
regression, section 3.3 of `methodology.md`).

## 9. Known limitations of this stage

- α + β is highly sensitive to the distributional assumption (0.9945 vs.
  0.9985) — the implied persistence/half-life should be reported as a
  range, not a single confident number, until further robustness checks
  (e.g., sub-period stability, discussed as a future diagnostic in
  `methodology.md`) are run.
- ω is not statistically significant under the Student's t specification —
  flagged, not yet resolved.
- This entire specification uses daily closing data only (no intraday
  realized volatility) — same data-access limitation already documented in
  `methodology.md` section 6.

## 10. Files produced at this stage

- `src/data_loader_fred.py` — FRED-based data loader (replaces yfinance
  attempt)
- `src/features.py` — log return computation
- `src/garch_model.py` — GARCH fitting and shock extraction (`fit_garch`,
  `extract_shock`)
- `src/garch_diagnostics.py` — side-by-side Normal vs. Student's t
  diagnostics (Ljung-Box, standardized ARCH-LM, QQ-plot, kurtosis
  comparison)
- `data/raw/eurusd_daily.csv`, `data/processed/eurusd_log_returns.csv`,
  `data/processed/eurusd_garch_shocks.csv`
- `docs/qqplot_std_residuals_normal.png`, `docs/qqplot_std_residuals_student_t.png`
