# COVID Out-of-Sample Robustness Test (Jan-Apr 2020)

*Companion document to `rolling_test.md`. Where that test (n=4, September
2026) could not distinguish "expected frozen-parameter behavior" from "a
structural reactivity problem" (section 5.3), this test was designed
specifically to answer that question, using a genuinely out-of-sample
model and a large enough window (84 trading days) to compute a real
empirical coverage rate.*

## 1. Why a separate, re-estimated model was required

The project's main MS-GARCH model (`ms_garch.R`) was calibrated on the
full 2010-2026 sample — including the COVID period itself. Testing that
model "on" 2020 would be close to circular: the model's own likelihood was
partly shaped by the event being tested. A genuine robustness test
requires a model that has never seen the shock.

**Fix**: `ms_garch_pre2020.R` re-estimates a separate MS-GARCH(K=2) using
only data through 2019-12-31 (2,501 observations). This model is then
**frozen** and used, unmodified, throughout the entire Jan-Apr 2020 test —
exactly the same frozen-parameter design as the September rolling test.

### 1.1 A known limitation of the pre-2020 fit, carried forward honestly

The pre-2020 model's stress-regime tail parameter is poorly identified:
**ν₂ = 71.73, SE = 202.05** — the uncertainty is nearly 3x the estimate
itself (p = 0.361), far less precise than the full-sample model's already
weak ν₂ = 22.0 (SE = 16.85). A ν this high is close to Normal-tailed. This
suggests the pre-2020 decade contains too few genuine extreme events for
the model to have learned how heavy the stress regime's tail should really
be. This limitation is **not corrected** — artificially fixing it would
defeat the purpose of testing what a model built from pre-2020 information
alone would actually have produced. It is flagged here because it becomes
directly relevant in section 4.

Otherwise, the fit is structurally consistent with the full-sample model:
regime long-run volatilities (σ₁≈0.215, σ₂≈0.726) closely match the
full-sample values (0.206, 0.730), and stable probabilities (68.7%/31.3%
vs. 71.7%/28.3%) are similar.

## 2. Test design

- **Window**: 2020-01-01 to 2020-04-30 (84 trading days) — starts exactly
  at the pre-2020 cutoff (no gap, no overlap) and deliberately begins
  before the shock (January was calm), so the test covers both a stable
  period and the acute crisis.
- **Single data source**: unlike the September test, this window sits
  entirely within the project's original FRED-sourced data — no
  source-switching caveat applies to the forecasting pipeline itself.
- **Frozen parameters, single `set.seed(42)` before the loop** — same
  design as `rolling_test_chain.R`.

## 3. Empirical coverage

```
Coverage: 77 / 84 = 91.7% (nominal target: 95%)
Breaches: 7 (expected under nominal 95%: ~4.2)
```

**The correct statistical test here is one-sided**, since the concern is
specifically under-coverage (too many breaches), not deviation in either
direction:

```
One-sided binomial test (H1: true breach rate > 5%): p = 0.127
(two-sided: p = 0.200)
```

**Interpretation, stated precisely**: even with the more favorable
one-sided test, p = 0.127 is above conventional thresholds (0.05 or even
0.10) — the data do not provide statistically significant evidence of
under-coverage. **This is not a validation of good calibration** — with
n=84, the test has limited power to distinguish a true 5% breach rate from
a true 8% one; absence of significant evidence of a problem is not
evidence of no problem. What it does say, in relation to `rolling_test.md`
section 5.3's open question: the model did **not** collapse or show a
dramatic coverage failure (e.g. 60-70%) during a genuine, major crisis —
a reassuring result, though not a decisive one.

## 4. Close-based breaches: two distinct groups, exactly as hypothesized

| Date | Actual (Close) | Direction | Breach size | P(stress) at forecast time |
|---|---|---|---|---|
| 2020-02-21 | 1.0855 | Upper | 0.02% | 0.3% |
| 2020-02-27 | 1.0977 | Upper | 0.31% | 0.3% |
| 2020-03-02 | 1.1164 | Upper | 0.90% | 2.5% |
| 2020-03-06 | 1.1319 | Upper | 0.09% | 49.3% |
| 2020-03-12 | 1.1081 | Lower | 0.63% | 98.7% |
| 2020-03-17 | 1.0971 | Lower | 0.30% | 99.2% |
| 2020-03-26 | 1.1025 | Upper | 0.44% | 98.4% |

**Group A (regime not yet reacted, P(stress) < 50%)**: 02-21, 02-27,
03-02, 03-06 (borderline, 49.3%) — consistent with the reactive-not-
predictive lag already documented in `rolling_test.md`.

**Group B (regime already flagged high stress, P(stress) > 95%)**: 03-12,
03-17, 03-26 — the model correctly identified acute stress **and still**
produced a range too narrow for the realized move.

### 4.1 A hypothesis for Group B — explicitly flagged as UNVERIFIED

One plausible explanation: the pre-2020 model's poorly-identified,
insufficiently heavy stress-regime tail (section 1.1, ν₂ imprecision)
under-estimates the true likelihood of extreme moves once in the stress
regime — because 2010-2019 simply didn't contain enough genuinely extreme
events for the model to have learned a heavier tail. **This has not been
tested or verified in any way** — no counterfactual model with a
constrained or manually widened ν₂ was fit and compared. It is recorded
here as a plausible, motivated hypothesis consistent with the available
evidence, not as an established mechanism. Confirming it would require,
at minimum, comparing forecast accuracy under an alternative
specification with a fixed, heavier ν₂ — not undertaken in this project.

## 5. Beyond Close: intraday High/Low reveal a much larger gap

Real OHLC data (Pound Sterling Live — FRED's `DEXUSEU` has no intraday
High/Low) was obtained to check the forecast bands against the full daily
range, not just the Close.

```
Breaches on Close:              7 / 84  (8.3%)
Days with High > upper bound:  12 / 84  (14.3%)
Days with Low  < lower bound:   7 / 84  (8.3%)
UNIQUE days touching outside the band (Close OR High OR Low): 19 / 84 (22.6%)
```

**Nearly one day in four touched outside the 95% band at some point
intraday — roughly 2.7x the Close-based breach rate.** This is a
substantially larger gap than what the September test's smaller sample
suggested, and reinforces the point already established in
`price_range.md` (section 7.2) and `rolling_test.md` (section 3.1): the
model is built for and should only be judged on close-to-close moves;
intraday reality is considerably more volatile than a Close-only
coverage check would suggest.

Most of the additional High/Low-only breaches cluster tightly around the
known crisis dates (02-28, 03-05, 03-09, 03-13, 03-16, 03-23) — days where
the Close came back inside the band by end of session, but the price
touched outside it during the day. This paints a more complete picture of
an already-elevated-risk period than the Close-only view alone.

**A data-source caveat worth naming precisely**: 2020-03-19 — the single
most extreme day in the window (PSL Low = 1.0653, the crisis trough) —
shows a Low breach but *not* a Close breach, implying FRED's own value for
that date differed enough from PSL's Close (1.0656) to remain inside the
band. This is consistent with, and possibly amplified during, the known
FRED/PSL discrepancy already documented (`price_range.md`, section 7.1) —
cross-source noise may matter more on the most volatile days, another
reason the Close-based (single-source, FRED-only) coverage number in
section 3 is the more trustworthy of the two views for judging the model
itself.

## 6. Economic interpretation

- **A treasury relying on this model through the crisis would have been
  "surprised" close-to-close about 1 day in 12** (7/84), close to but
  somewhat above the 1-in-20 the model promises — a modest, not dramatic,
  gap. But if that same treasury were managing intraday risk (e.g.
  stop-losses, margin calls triggered by any touch, not just the day's
  final print), **they would have been surprised roughly 1 day in 4**
  (19/84) — a materially different risk picture depending on which
  question is actually being asked of the model.
- **The model's regime signal was informative but not sufficient on its
  own during the most extreme days.** Group B shows that even "the model
  correctly says we're in a 98%-certain stress regime" did not guarantee
  the band was wide enough on the single worst days (mid-to-late March) —
  a limit worth knowing before treating "P(stress) is high" as a
  complete risk signal by itself.
- **The single most useful practical takeaway**: this model — like any
  model built purely from a decade of comparatively calm history — likely
  under-estimates just how extreme a genuinely unprecedented crisis can
  get, even once it correctly recognizes a crisis is underway. This is a
  humility point about tail risk more than a flaw specific to this
  implementation.

## 7. Visualization

An initial ribbon chart (`covid_ribbon_chart.py`, a plain price line with
shaded bands) was built first, then **superseded** by
`covid_candlestick_chart.py` once real OHLC data was obtained — the
candlestick version shows genuine daily direction and range (green/red
bodies, high-low wicks) against the same confidence bands, strictly more
informative with no loss of information. The ribbon script and its output
are retired; only the candlestick version is kept as part of the project.

Chart: `docs/covid_candlestick_chart.png`.

## 8. Files produced at this stage

- `src/ms_garch_pre2020.R` — re-estimation on pre-2020 data only
- `src/covid_robustness_test.R` — 84-day rolling forecast with frozen
  pre-2020 parameters, empirical coverage and binomial test
- `src/covid_candlestick_chart.py` — merges forecast results with real
  OHLC (Pound Sterling Live), full comparison table, candlestick + band
  chart
- `data/processed/ms_garch_par_pre2020.rds`
- `data/processed/covid_robustness_result.csv`, `covid_robustness_fan_data.csv`
- `data/raw/eurusd_ohlc_2020_covid.csv` — OHLC reference data (external
  source, used for comparison/visualization only, not for forecasting)
- `data/processed/covid_full_comparison_table.csv` — the full 84-row
  table: forecast range vs. actual Close (FRED) and OHLC context (PSL)
- `docs/covid_candlestick_chart.png`

## 9. What remains open

- The ν₂ hypothesis (section 4.1) — not tested.
- The full-scale backtest across the entire 2010-2026 sample (not just
  one crisis window) — still the next planned major stage,
  per `methodology.md`.
