# Magnitude Regression — Does the Volatility Signal Explain |r(t+1)|?

*Companion document to `methodology.md`, `docs/GARCH_1_1.md`,
`docs/regression_baseline.md`, and `docs/control_regression.md`. This is
the most detailed log in the project so far, deliberately — the
distinction it documents (direction vs. magnitude predictability, and
"statistically real" vs. "mechanically expected") is easy to blur, and
was worked through carefully rather than assumed.*

## 1. Objective and why this test differs from the previous two

The baseline and control regressions (`regression_baseline.md`,
`control_regression.md`) tested whether the volatility shock explains next-day
return **direction** — r(t+1), a signed quantity. Both returned a robust
null result.

This stage tests a different, and theoretically more natural, target for a
volatility model: next-day return **magnitude** — |r(t+1)|, the size of the
move regardless of sign.

**Important distinction to hold onto throughout this document**: |r(t+1)|
carries **no directional information**. Whether the actual return is
+0.8% or -0.8%, |r(t+1)| = 0.8% in both cases. A model that explains
|r(t+1)| well is **not** a trading signal telling you to go long or short —
it is a signal about how large a move to expect, in either direction. This
is exactly the "price range" framing from the project's opening question
(methodology.md, section 2): not a point forecast, an interval that widens
or narrows with the volatility regime.

## 2. Why a significant result here would not be a new discovery

This point was raised and clarified before running any code, and is kept
here in full because it shapes how the results below should — and should
not — be interpreted.

The GARCH model is defined by construction as:

```
r(t+1) = mu + sigma(t+1) * z(t+1)          (z(t+1) ~ i.i.d., mean 0, var 1)
sigma^2(t) = omega + alpha*eps^2(t-1) + beta*sigma^2(t-1)
```

Taking absolute values: |r(t+1)| ≈ sigma(t+1) * |z(t+1)|. And sigma(t+1) is
**itself built from sigma(t)** by the GARCH recursion — with beta ≈ 0.961
(highly persistent, confirmed in `GARCH_1_1.md`). So asking "does sigma(t)
explain |r(t+1)|?" is close to asking "did the GARCH do what it was
calibrated to do?" — a question already answered affirmatively by the
diagnostics in `GARCH_1_1.md` (Ljung-Box on squared standardized residuals,
not significant → the model captures the magnitude dynamics well).

**Consequence for interpretation, decided in advance**: a significant
result here should be documented as a **consistency check confirming the
GARCH's own mechanics**, not as a new empirical discovery about FX
behavior — unlike the direction test, where the null result was itself the
finding (consistent with, and adding a data point to, the weak-form
market efficiency literature).

**The mirror-image expectation, also decided in advance**: a *null* result
here would be the surprising outcome, and would point to a likely
specification problem (see section 3) rather than a genuine "magnitude is
also unpredictable" finding — the opposite logic from the direction test.

## 3. Two specifications, run side by side

### 3.1 The dilution concern

Throughout this project, ΔY(t) = ln(sigma(t)/sigma(t-1)) — the log-change
in conditional volatility — has been the standard "shock" variable used
for the level-shift signal (methodology.md, section 4.3). But sigma(t) is
highly persistent (autocorrelated by construction). Taking its
log-difference could dilute a relationship that is strong and obvious at
the **level**, since a day-to-day change captures much less information
than the level itself when the underlying series barely moves day to day
relative to its own scale.

To disentangle "the magnitude link is genuinely weak" from "the log-change
transformation dilutes an otherwise strong level relationship," both are
tested:

- **Spec A**: |r(t+1)| = a + b1·ΔY(t) + b2·|r(t)| + u(t)
- **Spec B**: |r(t+1)| = a + b1·sigma(t) (level) + b2·|r(t)| + u(t)

### 3.2 Control variable also changes form: |r(t)|, not r(t)

In the direction regressions, r(t) tested momentum/mean-reversion (does
yesterday's *signed* return predict tomorrow's *signed* return?). That is
not the relevant question for magnitude. What matters here is whether
yesterday's move **size** predicts tomorrow's move size — itself another
facet of volatility clustering. The control was therefore switched to
|r(t)|, the absolute value, decided as **mandatory** (not optional) for
this stage, given the change in what is being explained.

## 4. Results

Sample size: 4,173 observations (same alignment as the original baseline).

### 4.1 Spec A — ΔY(t)

```
R-squared: 0.013          F-statistic: 22.04   (p = 3.01e-10, model jointly significant)
AIC: 3026.94   BIC: 3045.95

               coef      std err     z        P>|z|
const         0.3386      0.009    39.499     0.000
delta_y_t    -0.0871      0.159    -0.549     0.583   <- NOT significant
abs_r_t       0.1148      0.017     6.562     0.000   <- significant
```

The model is jointly significant, but **only via |r(t)|**, not via ΔY(t).
delta_y_t itself carries no detectable explanatory power here.

### 4.2 Spec B — σ(t) level

```
R-squared: 0.090          F-statistic: 174.1   (p = 2.52e-73)
AIC: 2687.29   BIC: 2706.30

               coef      std err     z        P>|z|
const         0.0171      0.018     0.946     0.344
sigma_t       0.7029      0.040    17.364     0.000   <- strongly significant
abs_r_t       0.0269      0.016     1.638     0.101   <- NOT significant here
```

sigma_t is highly significant. Once it is in the model, |r(t)| loses its
significance — consistent with sigma_t already absorbing the persistence
information that |r(t)| was proxying for on its own in Spec A.

### 4.3 Comparison

| | Spec A (ΔY(t)) | Spec B (σ(t) level) |
|---|---|---|
| R² | 0.013 | **0.090** |
| AIC | 3026.94 | **2687.29** |
| BIC | 3045.95 | **2706.30** |
| Shock variable significant? | No (p = 0.583) | **Yes (p < 0.001)** |

**Conclusion on the dilution question**: confirmed. Spec B dominates Spec A
on every criterion (R², AIC, BIC). The log-change transformation used
throughout the rest of the project meaningfully weakens the signal here —
the level of conditional volatility, not its day-to-day variation, is what
carries the explanatory power for next-day return magnitude.

## 5. What an R² of 0.09 means economically — a worked example

|r(t+1)| carries no directional information (see section 1) — this
regression is never a "bet up or down" model. What Spec B gives is a
context-dependent estimate of expected move **size**.

Using the fitted Spec B coefficients (const = 0.0171, sigma_t coefficient
= 0.7029):

- **σ(t) ≈ 0.25** (this corresponds to roughly the **0.1st percentile** of
  the observed σ(t) distribution — essentially the practical floor of the
  sample, not merely "relatively low"):
  predicted |r(t+1)| ≈ 0.0171 + 0.7029 × 0.25 ≈ **0.19%**
- **σ(t) ≈ 0.60** (this corresponds to roughly the **71.6th percentile**
  — barely above the median, not a turbulent or post-shock extreme as the
  original framing implied):
  predicted |r(t+1)| ≈ 0.0171 + 0.7029 × 0.60 ≈ **0.44%**

**Correction to the original framing**: these two values are not
symmetric, representative "calm vs. turbulent" points — one sits at the
extreme floor of the distribution, the other barely above its center.
Labeling 0.60 as "turbulent" or "shortly after a shock" overstated how
unusual that level actually is. The qualitative point survives (a higher
σ(t) does imply a wider expected move), but the "roughly twice as large"
comparison above should be read as floor-vs-median, not calm-vs-crisis. A
properly matched pair — e.g. the 10th and 90th percentiles of σ(t) — would
better illustrate a genuine calm-vs-turbulent contrast; producing that
pair requires re-reading the percentiles directly from
`data/processed/eurusd_garch_shocks.csv`, not done here.

In plain terms: even comparing the practical floor of volatility to a
fairly ordinary, near-median level, the model's expected move size roughly
doubles — with zero information on which direction that move will take.
This is directly usable for the project's objective (b) — a
volatility-adjusted price range / risk-sizing signal — even though it says
nothing about direction.

Is R² = 0.09 "a lot"? Only relative to how difficult FX prediction
generally is — the direction regressions returned R² ≈ 0.000-0.001, so 0.09
represents a real, usable step up in explanatory power in that context.
In absolute terms, 91% of the variance in move size remains unexplained;
this is a modest but genuine signal, not a breakthrough.

## 6. Did we detect predictive power? Yes — but for a narrower claim than "prediction"

This question was raised directly during the project discussion and is
worth stating explicitly and precisely, because it is easy to conflate the
two null/non-null results into a single verdict.

| | Direction — r(t+1) | Magnitude — \|r(t+1)\| |
|---|---|---|
| Predictive power detected? | No (robust null, sections in `regression_baseline.md` / `control_regression.md`) | **Yes** (R² = 0.090, p < 0.001) |
| Usable as a directional bet (long/short)? | No — confirmed unusable | No — magnitude never carries direction |
| Usable as a volatility-adjusted price range? | — | **Yes** — this is precisely that signal |
| A scientifically surprising finding? | Somewhat — a cleanly documented, robust null is itself informative | No — closely expected from the GARCH's own construction (section 2) |

Both things are true at once, without contradiction: the magnitude result
is a **real, statistically robust, operationally usable** finding, and at
the same time **not a novel scientific discovery**, since it follows
closely from how GARCH itself is built. Neither framing cancels the other.

## 7. Files produced at this stage

- `src/magnitude_regression.py` — dataset construction
  (`build_magnitude_dataset`), generic HAC-robust OLS runner (`run_ols`),
  Spec A and Spec B estimation and comparison
- `data/processed/magnitude_regression_dataset.csv`

## 8. What remains open

- Whether this magnitude relationship is stable across sub-periods (ties
  into the GARCH stability check already flagged as a limitation in
  `GARCH_1_1.md` and queued in `methodology.md`, section 7)
- How to translate this into an explicit, documented price-range formula
  (objective (b), the project's original ambition for a min/max fourchette
  rather than a point forecast) — not yet formalized as a standalone
  deliverable
- Regime detection (normal / bubble / panic), the project's final queued
  step per `methodology.md`, section 7 — a related but distinct use of the
  volatility signal, not addressed by this regression
