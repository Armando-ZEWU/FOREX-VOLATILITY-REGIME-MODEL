# Price Range — The Project's Operational Deliverable (Objective b)

*Companion document to `methodology.md` (objective (b), stated at the
project's very start), `docs/ms_garch.md`, and `docs/magnitude_regression.md`.
This document covers the final stage: converting the MS-GARCH(K=2) model
into an actual EUR/USD price range, the concrete "fourchette" the project
set out to build from its opening question.*

## 1. Objective

Produce a real, computed [P_min, P_max] price range for EUR/USD, using the
fitted MS-GARCH(K=2) model (`docs/ms_garch.md`) — not the illustrative
made-up numbers used earlier in the project to explain the *concept* of a
regime-aware range (`magnitude_regression.md`, section 5; `regime_hmm.md`,
section 6.4), but an actual value computed from the fitted model and the
real, current data.

## 2. Method

### 2.1 Why Risk(), not predict()'s simulated draws

The original plan was to simulate draws from the model's full predictive
distribution (`predict(..., do.return.draw=TRUE)`) and take empirical
quantiles. In practice, this version of `MSGARCH`'s `predict()` method for
an `MSGARCH_SPEC` object returned only a scalar volatility forecast
(`$vol`), with no `$draw` element in the output despite the argument being
passed — discovered by inspecting the object's structure (`str()`) rather
than assuming the documented behavior held exactly as expected.

**Fix**: `Risk()`, the package's purpose-built function for Value-at-Risk
and Expected-Shortfall, computes quantiles of the full predictive density
directly (numerically, on a grid — see section 4.2), without relying on a
`$draw` field that turned out not to be populated here.

### 2.2 A convention trap in Risk()'s `alpha` argument

`Risk()`'s `alpha` argument specifies **left-tail (Value-at-Risk) levels**,
not a two-sided confidence level. Passing `alpha = 0.05` alone would
return a one-sided 5% VaR (a single bound), not a 95% interval. The
correct call for a two-sided 95% interval is `alpha = c(0.025, 0.975)`,
giving both the lower and upper bound directly. This was identified before
running the code (not discovered by a wrong first result) and a sanity
check (lower bound must be less than upper bound) was added defensively in
`ms_garch_forecast.R` in case the convention were still misread.

### 2.3 A prior, unrelated fix: the dead C++ pointer problem

Before reaching this stage, an earlier attempt to persist the fitted MS-GARCH
object via `saveRDS(fit, ...)` and reload it in a separate script failed
with `NULL value passed as symbol address`. Root cause: `MSGARCH` is
implemented in C++ via Rcpp; the fitted object's `spec` component wraps a
compiled C++ module through an external pointer, which does not survive
serialization to disk across R sessions — `saveRDS()` preserves the R-level
wrapper, not the underlying C++ memory it references. **Fix**: persist only
the plain-numeric components (`fit$par`, `fit$loglik`,
`fit$Inference$MatCoef`), and in the forecasting script, recreate a fresh
`MSGARCH_SPEC` via `CreateSpec()` (a new, valid pointer) and pass the saved
`par` vector explicitly to the SPEC-dispatched methods of `State()`,
`predict()`, and `Risk()`. This is documented in full in `ms_garch.R` and
`ms_garch_forecast.R`'s header comments, since it is a genuine, non-obvious
R/Rcpp limitation, not a coding mistake to gloss over.

A related naming trap, worth restating here since it affects every call in
this pipeline: `State()` and `Risk()` take an argument named `data`;
`predict()` takes `newdata`. Not interchangeable.

### 2.4 Confidence level and regime-weighting choice

- **95% confidence level**, as decided earlier in the project (a standard
  choice; narrower levels like 42% were considered and rejected as
  producing an interval that would be wrong more than half the time,
  unsuitable for a risk-management-oriented deliverable — see
  `methodology.md` discussion).
- The interval uses the model's **full predictive distribution**,
  weighting both regimes by their current predicted probability (99.4%
  low-volatility, 0.6% high-volatility as of the last observation) —
  **not** an artificial "assume we are certainly in regime k" forecast.
  This is the operationally correct choice: the model genuinely does not
  know with certainty which regime tomorrow will be in, only a
  probability: pretending certainty would misrepresent the model's own
  honestly-carried uncertainty.

### 2.5 Other decisions made in this stage, previously undocumented

Flagged and corrected after an explicit audit of every choice made,
following a direct request to leave nothing out:

- **`last_price` is exported from R, not re-read separately in Python.**
  The forecast script (`ms_garch_forecast.R`) reads the raw price file
  itself and includes the matching price directly in the CSV it writes,
  rather than letting `price_range.py` re-open `eurusd_daily.csv`
  independently. Reason: if the two files were ever regenerated at
  different times (e.g. new data pulled between running the R and Python
  scripts), a separately-read price could silently belong to a different
  date than the forecast. A `stop()` check in R enforces that the price
  found matches the forecast's date exactly, failing loudly rather than
  silently using a mismatched value.
- **`do.es = FALSE` in the `Risk()` call.** Only the Value-at-Risk
  quantiles were needed for the price range; Expected Shortfall (the
  average loss beyond the VaR threshold) was not requested, since it
  answers a different question (tail severity, not a two-sided range) not
  part of this deliverable's scope.
- **`set.seed(42)` before calling `Risk()`.** Kept as a precaution in case
  `Risk()`'s computation involves simulation. In this pipeline it has no
  observable effect: the single-level call (section 3) and the multi-level
  call used for the fan chart (section 8), made later in the same script
  without re-seeding, return identical 95% bounds to every printed digit,
  and the bounds lie on a regular numerical grid (section 4.2). The seed is
  therefore not what makes the results reproducible here.
- **An explicit sanity check (`q_low >= q_high` triggers a warning).**
  Added defensively after the `alpha` convention trap (section 2.2) was
  identified, specifically to catch a repeat of that kind of mistake
  automatically rather than relying on manually re-checking the numbers
  every time the script runs.

## 3. Results

As of 2026-09-11 (EUR/USD = 1.1604):

```
Current regime probabilities: low-vol = 99.4%, high-vol = 0.6%
Model-implied volatility forecast (regime-weighted): 0.3055

95% price range: [1.1533, 1.1675]
Width: 0.0142 (1.22% of current price)
```

### 3.1 Internal consistency check

The interval corresponds to roughly ±2.0 times the forecast volatility
(-2.011σ / +1.984σ). This was checked against the theoretical quantile of
a standardized Student's t distribution with ν ≈ 7.07 (regime 1's tail
parameter, which dominates the mixture given its 99.4% weight): -1.998.
The close match confirms `Risk()` is genuinely using the model's Student's
t predictive distribution, not silently falling back to a Normal
approximation — a real verification, not an assumption taken on faith.

At the 95% level this check has limited power to tell a Student's t from a
Normal: the two quantiles differ by only 2% (1.998σ against 1.960σ). The
80% level of the fan chart (section 8) discriminates better: the mixture's
80% bounds are at −1.212σ and +1.185σ, i.e. about 1.20σ on average, against
1.197σ for a standardized Student's t (ν ≈ 7.07) and 1.282σ for a Normal.

## 4. Rigorous result vs. genuine regime-conditional forecast

An earlier version of this document compared the operational range to an
*approximation* of what each regime would imply (using each regime's
long-run volatility level and the mixture's quantile multiplier, not a
true one-step-ahead forecast). This has since been replaced: `docs/ms_garch.md`
section 1 was corrected to recognize that `MSGARCH`'s Markov-switching
option implements Haas, Mittnik & Paolella (2004a), not Gray (1996) —
meaning each regime's own conditional variance recursion has **no**
path-dependency problem and can be computed directly:

σₖ²(t) = ωₖ + αₖ·r(t−1)² + βₖ·σₖ²(t−1)

run independently for each regime k over the same observed return series
(`ms_garch_forecast.R`, section 6). This gives a genuine, exact
one-step-ahead forecast per regime — not an approximation.

### 4.1 Validation of the manual recursion

Before trusting this recursion, it was cross-checked against the
already-validated `Risk()` mixture result: the probability-weighted
average of the two regimes' forecast variances,
√(w₁σ₁²(t+1) + w₂σ₂²(t+1)), gives **0.3055** — matching `Risk()`'s
reported mixture volatility forecast (**0.3055**) exactly. This
independent match confirms the manual recursion is correct, rather than
relying on the formula being merely "plausible."

### 4.2 Genuine regime-conditional 95% ranges

As of 2026-09-11 (EUR/USD = 1.1604):

| | Volatility forecast σₖ(t+1) | 95% range | Width |
|---|---|---|---|
| Regime 1 (calm) | 0.3033 | [1.1534, 1.1675] | 1.21% |
| Regime 2 (stress) | 0.5769 | [1.1472, 1.1737] | 2.28% |
| **Mixture (operational)** | 0.3055 | **[1.1533, 1.1675]** | **1.22%** |

The stress-regime range is genuinely (not approximately) **1.88x wider**
than the calm-regime range — a direct consequence of regime 2's own
one-step-ahead volatility being nearly double regime 1's (0.577 vs 0.303,
a ratio of 1.90). The tail shape plays only a small role, and in the
opposite direction: regime 2's tail is *lighter* (ν₂ ≈ 22, closer to
Normal than expected, per `ms_garch.md` section 4.4) than regime 1's
(ν₁ ≈ 7), which reduces the ratio very slightly at the 95% level (1.88x
against a volatility ratio of 1.90).

**Note on the mixture's small asymmetry**: `Risk()`'s reported 95% interval
(-0.6143 / +0.6061) is very slightly asymmetric, even though the model has
no mean term (`MSGARCH` assumes zero mean throughout — no `mu` parameter
is estimated) and each individual regime's Student's t distribution is
exactly symmetric about zero. A mixture of two zero-centered symmetric
distributions is itself theoretically symmetric, and its exact 95%
quantiles, computed from the published parameters and the current regime
weights, are ±0.611. The reported bounds deviate from that value by less
than 1% (≈1.3% between the two bounds), and the deviation is systematic
rather than random: at all four confidence levels of the fan chart
(section 8) the midpoint of the lower and upper bounds is the same,
−0.0041 (in % of log-return), and every bound reported by `Risk()`, across
all levels and across the forecasts of `rolling_test.md`, lies on a
regular grid of step ≈0.0068 percentage points of return (about 0.56% of
the 95% interval's width). The asymmetry is therefore a grid effect of
`Risk()`'s numerical computation — not Monte Carlo noise, and not a
property of the model. It is immaterial for the price range (about 0.00005
in price).

### 4.3 Why this matters, beyond just being "more correct"

This is no longer a cosmetic upgrade over the earlier approximation: the
true regime-conditional ranges are computed with the same rigor as the
operational mixture range (section 3), using each regime's own fitted
parameters and its own tail shape — not borrowed multipliers or long-run
levels. This makes the regime comparison itself a legitimate, quotable
result (e.g. in a report or README), not merely an illustrative aside.

## 5. What "next trading day" actually means — a clarification that avoids a false failure

This was raised directly during the project discussion and is recorded
here because it materially affects how the range should be read.

`nahead = 1` means one step ahead **in the trading-day series used to fit
the model**, not literally "24 hours from now" or "tomorrow" in the
calendar sense. The last observation used was **Friday, 2026-09-11**; FX
reference series like FRED's `DEXUSEU` have no observation on weekends.
The range in section 3 is therefore a forecast for the **next available
trading-day observation** in the series — in this case, **Monday,
2026-09-14** — not Saturday.

**A further, more substantive caveat**: the real FX market trades
continuously from Sunday evening to Friday evening (New York time), unlike
the once-daily `DEXUSEU` reference rate (a noon New York rate) the model
was calibrated on. A full
weekend of news (central bank commentary, geopolitical events) can occur
between the Friday close and the Monday reopen that the model has **never
observed as a distinct event** — it was calibrated purely on day-to-day
changes of that reference rate, with no explicit "weekend gap" component. Practically: a Monday's
actual move could fall outside the 95% range more often than an
"average" weekday would, purely because weekends can carry more
unobserved information than a single weekday gap. This is a known
limitation of daily-close GARCH-family models applied to FX, not a flaw
specific to this implementation — but it should be stated explicitly
rather than left for a reader to discover by watching the model "fail" on
a Monday that was, in fact, behaving exactly as a model blind to weekend
news would be expected to.

## 6. Economic interpretation — what this range means for someone watching the market

- **A 1.22%-wide range on a single day is a real, actionable number, not
  an abstraction.** For a business converting a EUR 1,000,000 invoice into
  USD, the range [1.1533, 1.1675] implies the dollar proceeds could
  plausibly land anywhere between about $1,153,300 and $1,167,500 — a
  swing of over $14,000 on a single day's exchange-rate uncertainty alone,
  before any other business risk. This is the kind of number a treasury or
  finance function would use to size a hedge, not just an academic
  quantity.
- **The range's width is not fixed — it breathes with the regime,** which
  is the entire operational point of this project. On this date, the
  model assigns 99.4% probability to the calm regime, so the operational
  range is close to its calm-regime width. Using the exact regime-conditional
  ranges from section 4.2, the same EUR 1,000,000 conversion illustrates the
  difference directly:
  - **If calm (certain)**: [1.1534, 1.1675] → proceeds between
    $1,153,400 and $1,167,500 — a $14,100 spread, almost identical to the
    operational range, because the model is currently near-certain the
    market is calm.
  - **If stress (certain)**: [1.1472, 1.1737] → proceeds between
    $1,147,200 and $1,173,700 — a **$26,500 spread**, nearly double.
    A treasury relying on a single, regime-blind volatility estimate
    calibrated during calm periods would be under-hedged by roughly this
    difference the moment the market actually shifts into stress — exactly
    when the hedge matters most.
- **What the range does NOT tell you**: nothing about direction. A 95%
  range of [1.1533, 1.1675] is symmetric information about *how far*
  EUR/USD might move, not *which way* — consistent with the project's
  earlier, robust finding that direction is not predictable at this
  horizon (`regression_baseline.md`, `control_regression.md`). Anyone
  reading this range as "the model expects EUR/USD to end up somewhere in
  here, probably in the middle" is over-reading it: the model has no
  opinion on where within the range the price will land, only that 95% of
  the time, it expects the actual move to fall inside it. This holds in
  both regimes: a wider stress-regime range does not mean the model
  expects a crash any more than a rally — only a larger move in either
  direction.

## 7. Ex-post comparison to actual market data (2026-09-14)

This check was run specifically because a forecast is only as credible as
its willingness to be checked against reality — not to claim a rigorous
validation from a single observation (see the explicit caveat below).

### 7.1 What actually happened

Independent source (Pound Sterling Live daily EUR/USD history), for
Monday 2026-09-14 (the next trading day after the 2026-09-11 forecast):

| | Value |
|---|---|
| Open | 1.1597 |
| Close | 1.1549 |
| High | 1.1601 |
| Low | 1.1523 |

Forecast range: **[1.1533, 1.1675]**.

### 7.2 Result

Open, Close, and High all fall inside the forecast range. The intraday
**Low (1.1523) falls just outside the lower bound**, by 0.0010 (≈0.086% of
the reference price — about ten pips).

**The most relevant comparison is to the Close (1.1549), not the intraday
Low.** The GARCH model was calibrated on day-to-day log returns of the
daily FRED reference rate (`features.py`, `GARCH_1_1.md`) — it was never
built to predict intraday extremes (the High-Low range within a single
day), only the size of the day-to-day move. Judged against that quantity,
the Close falls comfortably inside the range: consistent with the model,
though only indicatively (see the source caveat below). The Low breaching
the band is a data point about a different question (intraday range) that
this model does not address — worth noting, not a failure of what was
actually forecast.

**Source caveat**: this project's own pipeline recorded the 2026-09-11
reference price as 1.1604 (FRED's `DEXUSEU`), while this independent source
reports a Close of 1.1599 for the same day — a ~0.04% difference. The two
are not the same quantity: `DEXUSEU` is the Federal Reserve's noon buying
rate in New York (H.10 release), not an end-of-day close, so the model
forecasts the next noon reference rate while Pound Sterling Live reports
the end-of-day close. The gap is small on a calm day but can be much
larger in volatile ones (on average 0.22% between 24 February and 30 April
2020, up to 1.14%; see `covid_robustness_test.md`, section 5), so this
comparison is indicative, not exact.

### 7.3 Critical caveat: this is one observation, not a validation

**A single day proves essentially nothing about model calibration.** A
correctly calibrated 95% interval is *expected* to be breached on
roughly 1 day in 20 — a single in-range (or even a single out-of-range)
result carries no statistical weight on its own. This comparison is
recorded as an honest, concrete illustration of how the range performed
once, not evidence that the model is well- or poorly-calibrated. A real
calibration check would require accumulating many such observations over
time (e.g., tracking the actual breach rate over dozens or hundreds of
trading days and comparing it to the nominal 5%) — not attempted here.

## 8. Fan chart: multiple confidence bands

Extending the single 95% range to a Bank-of-England-style fan chart —
several nested confidence bands computed in one `Risk()` call across the
full alpha vector, converted to price bands and plotted in `fan_chart.py`.

**Levels revised after an explicit reservation**: an initial proposal of
5%, 15%, 20%, 30%, 60%, 80%, 95% was raised as producing a near-invisible
5% band and two nearly indistinguishable 15%/20% bands. Revised to four
well-separated levels — **20%, 50%, 80%, 95%** — each visually distinct on
the resulting chart, consistent with conventional central-bank fan-chart
spacing.

### Results

As of 2026-09-11 (EUR/USD = 1.1604), all three panels (operational mixture,
calm regime certain, stress regime certain):

| Confidence level | Mixture width | Calm width | Stress width | Stress/Calm ratio |
|---|---|---|---|---|
| 20% | 0.136% | 0.135% | 0.282% | 2.09x |
| 50% | 0.366% | 0.365% | 0.754% | 2.07x |
| 80% | 0.732% | 0.726% | 1.454% | 2.00x |
| 95% | 1.220% | 1.212% | 2.282% | 1.88x |

The bands are properly nested at every level (20% ⊂ 50% ⊂ 80% ⊂ 95%) and
widen faster than linearly toward the tails in all three panels, as a
Normal distribution would also do. What distinguishes the model is the
degree: the 95% band is about 9.0 times as wide as the 20% band in the
mixture and calm panels (8.1 times in the stress panel), against 7.7 times
for a Normal distribution — the signature of the heavier tails of the
Student's t distribution underlying the model.

Chart saved to `docs/fan_chart.png`.

### Interpretation — the calm regime, and, importantly, the stress regime

**Calm regime**: nearly identical to the operational mixture at every
level (expected, since the mixture is 99.4% calm-weighted on this date) —
confirms the mixture range is, for all practical purposes, "the calm-regime
range" right now.

**Stress regime — the part of this chart that actually shows the model's
value**: at every confidence level, the stress-regime band is **roughly
twice as wide** as the calm-regime band — but that ratio is not constant,
and the way it changes is itself informative. It is **2.09x, 2.07x and
2.00x** at the 20%, 50% and 80% levels, i.e. about 5-10% *above* the ratio
of the two regimes' one-step volatility forecasts (0.577/0.303 ≈ 1.90),
and **1.88x** at the 95% level, essentially equal to it. If the two
regimes had the same distribution shape, the ratio would be constant and
equal to 1.90; the deviations measure the effect of the different shapes
documented in `ms_garch.md` (section 4.4). At a given variance, a
fat-tailed distribution puts more mass near the center, so the calm
regime's central band is narrower than a near-Normal one would be: at the
20% level the half-width is 0.223σ for the calm regime (ν₁ ≈ 7) against
0.245σ for the stress regime (ν₂ ≈ 22; a Normal gives 0.253σ). This
inflates the stress/calm ratio at the central levels. In the far tail the
two shapes give nearly the same multiple of σ (1.998σ against 1.977σ at
95%), and the ratio falls back to the volatility ratio. The *absolute* gap
between the two bands still grows with the confidence level.

**What this means for someone reading the chart, not just the numbers**:
the stress panel isn't simply "the calm panel stretched by a constant
factor" — it has a genuinely different shape, relatively narrower
at its most extreme edge than at its center, because the two regimes have
different distribution shapes. A viewer scanning only the width
at 95% would actually slightly *understate* how much riskier the central,
day-to-day experience of the stress regime is compared to calm (the 20%
and 50% ratios, ~2.1x, are larger than the headline 95% ratio, ~1.88x) —
worth knowing before using a single "times-two" rule of thumb to reason
about regime risk at every horizon.

## 9. Files produced at this stage

- `src/ms_garch_forecast.R` — one-step-ahead forecast for each regime
  (manual recursion, validated against `Risk()`), 95% range via `Risk()`,
  multi-level call for the fan chart, and regime-conditional quantiles
- `src/price_range.py` — `compute_price_range` (log-return interval to
  price conversion), main script producing the rigorous range and the
  labeled illustrative regime comparison
- `src/fan_chart.py` — multi-band price conversion and fan chart plotting
- `data/processed/price_range_output.csv` — the operational result
  (date, last price, confidence level, P_min, P_max, range width)
- `data/processed/ms_garch_price_range_inputs.csv` — return quantiles at
  the 95% level, forecast volatility and current regime probabilities
- `data/processed/ms_garch_fan_chart_inputs.csv` — return quantiles at 4
  confidence levels (20%, 50%, 80%, 95%)
- `data/processed/ms_garch_regime_conditional_forecast.csv` — the same 4
  levels for each regime taken as certain (calm / stress)
- `docs/fan_chart.png` — the rendered fan chart

## 10. Status of the project's objective (b)

With this stage, objective (b) — stated at the project's outset
(`methodology.md`, section 1) — is now concretely delivered: a real,
computed, regime-aware price range, grounded in a validated GARCH
specification (`GARCH_1_1.md`), an honestly-labeled regime-detection layer
(`regime_hmm.md`, `ms_garch.md`), and a documented, checked forecasting
method (this document) — rather than the illustrative example used earlier
in the project purely to explain the concept.
