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

**Plausible economic context, offered at the time — since contradicted**:
this document originally speculated that 2013-2016 was "a historically
calm period for EUR/USD," offered as an explanation for why ω was
difficult to pin down. **This speculation does not hold up against
evidence produced later in the project.** The MS-GARCH regime
classification (`ms_garch.md`), built after this document was first
written, gives a very different picture for the two full calendar years
falling within Period 2: **2014 spent 26.4% of trading days in the
high-volatility regime, and 2015 spent 68.1%** — the latter one of the
most stress-heavy years in the entire 2010-2026 sample, not a calm one.
Using this same period's own (numerically fragile) ω/(1−α−β) formula
gives an implied long-run daily volatility of order 6.5%, wildly above
every other period's 0.3-0.65% — not independent proof of anything, given
the same near-IGARCH instability already flagged above, but at minimum
inconsistent with a "calm period" story on its own terms.

**Corrected conclusion on Period 2's context**: the numerical fragility
diagnosis (ω poorly identified near the IGARCH boundary) still stands as
the direct statistical explanation. But the "calm period" narrative
offered to explain *why* this happened is not supported by later,
independent evidence from the same project and should not be repeated —
if anything, Period 2 contains one of the more turbulent years (2015) in
the whole sample, which makes the ω identification failure more puzzling,
not less, and worth flagging as an open question rather than an explained
one.

**Conclusion on Period 2**: α and β themselves remain valid and
interpretable (in line with the other four periods); the derived half-life
figure specifically should be treated as not meaningful and must never be
quoted on its own (e.g. in the README or a written report) without this
explanation attached.

## 5. Overall stability conclusion — revised after a formal test

Excluding the Period 2 half-life artifact (while keeping its valid α, β
estimates):

| Period | α+β | Half-life reliable? |
|---|---|---|
| 1 | 0.9895 | Yes — 65.5 days |
| 2 | 0.999991 | No — ω not significant, numerically unstable ratio |
| 3 | 0.9979 | Yes — 335.1 days |
| 4 | 0.9912 | Yes — 78.5 days |
| 5 | 0.9902 | Yes — 70.5 days |

**Point estimates vary substantially across periods** — half-lives from
~65-80 days (Periods 1, 4, 5) to ~335 days (Period 3). Note that this
large half-life gap corresponds to a small absolute difference in α+β
itself (0.0067 to 0.0084) — the half-life formula, ln(0.5)/ln(α+β), is
highly non-linear near the α+β=1 boundary, so small differences in the
raw parameter translate into large differences in the derived half-life.
Both facts are true at once and neither cancels the other: the underlying
parameter differences are modest in absolute terms, and their practical
consequence (how long a shock takes to fade) is large.

### 5.1 Is this variation statistically established? A formal test says no, not at conventional significance

An earlier draft of this document concluded from the table above that
"the single full-sample GARCH(1,1) is not temporally stable." **This
overstated what the data support.** A likelihood-ratio test comparing the
5 independently-fit sub-period models (5 periods × 5 parameters each,
including the mean term μ — 25 parameters total) against the single
full-sample model (5 parameters) gives:

```
LR = 2 × [(-2806.77) − (-2818.39)] = 23.24
df = 25 − 5 = 20
p = 0.277

AIC: 5646.78 (single model) vs. 5663.53 (5 separate periods)
BIC: 5678.46 (single model) vs. 5821.95 (5 separate periods)
```

**At p = 0.277, the null hypothesis of a single, stable set of parameters
across all 5 periods cannot be rejected at any conventional significance
level.** Both AIC and BIC in fact prefer the single, stable model over
the 5 separate ones (lower is better on both criteria) — the extra
flexibility of period-specific parameters does not pay for its added
complexity by either measure.

**Corrected conclusion**: the point estimates in the table above do
genuinely differ across periods, but **this variation is not
statistically established** as real instability rather than sampling
noise around a single true parameter set. The honest summary is: *point
estimates vary across sub-periods; a formal likelihood-ratio test does not
establish that this variation reflects genuine parameter instability
rather than chance.* This is a materially weaker claim than "the model is
unstable," and the rest of this document (and any document that cites it)
should not overstate it.

## 6. Implication for the regime-detection model choice — softened accordingly

This result still informed the next stage of the project (regime
detection, per `methodology.md`), but the reasoning should be stated
carefully given section 5.1's correction: a simple HMM applied to σ(t)
generated by the single full-sample GARCH *might* inherit some
period-specific distortion, but this document's own formal test does not
establish that such distortion is statistically real. The case for
considering a **Markov-Switching GARCH** instead rests more defensibly on
AIC (5633.27 vs. 5646.78, favoring MS-GARCH — see `ms_garch.md`) than on
an appeal to "confirmed instability" from this document — and even there,
**BIC prefers the single-regime model** (5696.64 vs. 5678.46). The honest
framing is: MS-GARCH was pursued because it is the more theoretically
appropriate tool for regime-dependent dynamics and it wins on one
information criterion, not because this stability test proved the
single-regime model inadequate.

**This document does not make the final method choice** — that decision,
and its justification, is documented separately in the regime-detection
stage itself (`ms_garch.md`).

## 6.1 Economic interpretation

This document's revised conclusion (section 5.1) has a direct economic
reading, easy to miss in the statistical detail: **there is no solid
evidence that EUR/USD's volatility persistence behaves differently across
eras** — a shock in 2011 and a shock in 2023 fade at statistically
indistinguishable rates, as far as this test can tell. For someone using
the model operationally, this is reassuring in one specific sense: it
means the single, full-sample GARCH is not obviously the wrong tool
because "market behavior has fundamentally changed" — the more mundane
explanation (sampling variation in a genuinely noisy process) cannot be
ruled out, and Occam's razor favors it given the formal test's result.

At the same time, the corrected account of Period 2 (section 4) is a
useful caution against a different, common error: reaching for a
plausible-sounding economic narrative ("it was a calm period") to explain
an awkward statistical result, without checking that narrative against
independent evidence. The narrative felt right at the time; it turned out
to be wrong once the project had built better tools (MS-GARCH's regime
classification) to check it. The practical lesson for anyone extending
this work: a numerically fragile estimate (here, ω near zero) deserves a
flagged *statistical* explanation (the IGARCH-boundary fragility, which
holds up) rather than an *economic* one improvised to make the number feel
less surprising (the calm-period story, which does not hold up).

## 6.2 A reproducibility gap, noted rather than fixed retroactively

`garch_stability_comparison.csv` (produced by `garch_stability_test.py`)
stores only point estimates (ω, α, β, ν) per period — not their standard
errors or p-values. The p-values discussed in section 4 for Period 2 (e.g.
ω's p=0.519) came from an ad hoc interactive re-fit of that period alone,
run in the console rather than captured in the saved script output. A
reader trying to reproduce section 4's diagnosis purely from the CSV would
not be able to. This is flagged as a real gap rather than fixed
retroactively here — extending `summarize_garch_result()` to also export
standard errors and p-values for all 5 periods would be a natural,
low-cost improvement if this script is revisited.

## 7. Files produced at this stage

- `src/garch_stability_test.py` — equal-period splitting
  (`split_into_equal_periods`), per-period GARCH fitting and summary
  extraction (`summarize_garch_result`)
- `data/processed/garch_stability_comparison.csv`
