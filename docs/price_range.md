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
directly (via numerical integration/simulation internal to the package),
without relying on a `$draw` field that turned out not to be populated
here.

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

## 4. Rigorous result vs. illustrative comparison — a distinction that must not be blurred

`price_range.py` also prints two additional lines, explicitly labeled
"illustrative only", showing what the range would look like if each
regime were assumed with certainty:

```
Low-volatility regime (calm):    [1.1556, 1.1652] (width: 0.82%)
High-volatility regime (stress): [1.1435, 1.1773] (width: 2.92%)
```

**These two lines are an approximation, not a second rigorous forecast.**
A genuine regime-conditional forecast would require, for each regime k:
its own one-step-ahead conditional variance σₖ²(t+1) = ωₖ + αₖε²(t) +
βₖσₖ²(t) — which in turn requires σₖ²(t), the regime-specific collapsed
variance carried internally by the model's Gray (1996) approximation
(`docs/ms_garch.md`, section 1's path-dependency discussion) — and its own
regime-specific Student's t quantile (ν₁ = 7.07 vs. ν₂ = 22.0, which imply
different quantile multipliers, not just different volatility levels).

What was actually computed instead: each regime's **long-run** (unconditional)
volatility level (from `docs/ms_garch.md`, section 4.2), combined with the
**same** ±2.0 multiplier taken from the actual mixture forecast — not
each regime's own multiplier. This means:
- The relative sizing (stress regime roughly 2-3x wider than calm) is
  directionally correct and consistent with the regimes' long-run
  volatility ratio (0.730 / 0.206 ≈ 3.5x).
- The exact bounds are not precise: they mix a long-run (not one-step-ahead)
  volatility level with a multiplier that isn't specific to that regime's
  own tail shape.

**Why this distinction matters, stated plainly**: only the single
mixture-based range in section 3 is the project's actual operational
result. The regime-by-regime comparison exists solely to make the value of
regime-awareness visually concrete (showing that the range would be
noticeably different in a stress regime) — it must never be quoted as a
precise model output in a report or the README.

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
the once-daily `DEXUSEU` reference rate the model was calibrated on. A full
weekend of news (central bank commentary, geopolitical events) can occur
between the Friday close and the Monday reopen that the model has **never
observed as a distinct event** — it was calibrated purely on day-to-day
closes, with no explicit "weekend gap" component. Practically: a Monday's
actual move could fall outside the 95% range more often than an
"average" weekday would, purely because weekends can carry more
unobserved information than a single weekday gap. This is a known
limitation of daily-close GARCH-family models applied to FX, not a flaw
specific to this implementation — but it should be stated explicitly
rather than left for a reader to discover by watching the model "fail" on
a Monday that was, in fact, behaving exactly as a model blind to weekend
news would be expected to.

## 6. Files produced at this stage

- `src/price_range.py` — `compute_price_range` (log-return interval to
  price conversion), main script producing the rigorous range and the
  labeled illustrative regime comparison
- `data/processed/price_range_output.csv` — the operational result
  (date, last price, confidence level, P_min, P_max, range width)

## 7. Status of the project's objective (b)

With this stage, objective (b) — stated at the project's outset
(`methodology.md`, section 1) — is now concretely delivered: a real,
computed, regime-aware price range, grounded in a validated GARCH
specification (`GARCH_1_1.md`), an honestly-labeled regime-detection layer
(`regime_hmm.md`, `ms_garch.md`), and a documented, checked forecasting
method (this document) — rather than the illustrative example used earlier
in the project purely to explain the concept.
