# Markov-Switching GARCH (K=2)

*Companion document to `methodology.md`, `docs/GARCH_1_1.md`,
`docs/garch_stability.md`, and `docs/regime_hmm.md`. This document covers
the project's final planned model: a Markov-Switching GARCH that
re-estimates ω, α, β separately per regime, addressing the temporal
instability of the single-regime GARCH documented in `garch_stability.md`
more directly than the HMM-on-top-of-a-fixed-GARCH approach in
`regime_hmm.md`.*

## 1. Why R, not Python — a documented, deliberate exception

Every other stage of this project was implemented in Python (`arch` for
GARCH, `hmmlearn` for the HMM). Markov-Switching GARCH is different: no
comparably mature Python package exists. The standard reference
implementation is the R package **MSGARCH** (Ardia, Bluteau, Boudt,
Catania, Trottier, 2019, *Journal of Statistical Software*), built in
C++/Rcpp.

This is not merely a tooling gap. True MS-GARCH estimation faces a genuine theoretical difficulty, documented since Hamilton & Susmel (1994) and Haas, Mittnik & Paolella (2004a): the conditional variance in a given regime depends, in principle, on the **entire history of regime paths** since the start of the series(because σ²(t) depends on σ²(t−1), which itself depended on whichever regime was active at t−1, and so on) — making the exact likelihood computationally intractable beyond a handful of observations. 
Practical implementations, including MSGARCH, rely on an approximation (Haas, Mittnik & Paolella (2004a)
"collapsing" procedure) to make estimation feasible at all. Even the
reference tool is working with an approximation, not an exact model.

Given this, and that the person running this project has R available,
this stage was run as a **single, deliberate, documented exception** to
the project's otherwise all-Python pipeline: an R script (`ms_garch.R`)
run directly (not via `rpy2`, to avoid Python-R bridging overhead for a
one-off analysis), producing CSV outputs reloaded into the Python-based
project for any further work.

## 2. Choice of K=2, not K=3

The HMM in `regime_hmm.md` used 3 states (low/normal/high volatility).
This stage deliberately uses **K=2**, not 3, for a stated reason, not
arbitrarily: MS-GARCH estimation is substantially harder numerically than
fitting a Gaussian HMM on an already-computed scalar series (σ(t)) — it
must jointly estimate ω, α, β **per regime**, plus the transition matrix,
under the path-dependency approximation described above. Each additional
regime multiplies this difficulty. The FX/equity MS-GARCH literature
(e.g. Klaassen, 2002; Marcucci, 2005) commonly starts with 2 regimes
before considering more. This is a genuine methodological difference from
the HMM, not an inconsistency — the two tools face different numerical
constraints.

## 3. Specification and errors encountered

### 3.1 Model specification

2 regimes, each a GARCH(1,1) ("sGARCH") with Student's t innovations
("std") — matching the single-regime specification already validated in
`GARCH_1_1.md`.

### 3.2 First error: conflicting specification arguments

```
Error in CreateSpec(...): you can only use the variable K if you specified
one regime in variance.spec and distribution.spec
```

The first version of the script passed both a length-2 vector in
`variance.spec`/`distribution.spec` AND `K = 2` in `switch.spec` — two
alternative ways of specifying the number of regimes that `CreateSpec()`
does not allow combined. **Fix**: specify a single regime
(`model = c("sGARCH")`, `distribution = c("std")`) and let `K = 2` expand
it automatically.

### 3.3 Second error: row-count mismatch when saving regime probabilities

```
Error: arguments imply differing number of rows: 4175, 4176
```

`State()`'s `SmoothProb` output has **T+1** rows, not T, confirmed via the
package documentation: row 1 represents the pre-sample prior (t=0, before
any observation is seen), and rows 2 to T+1 correspond to the actual T
observed trading days. `FiltProb`, by contrast, has exactly T rows. This
was not guessed — the discrepancy was diagnosed by printing the object's
structure (`str()`) before trusting any extraction, and confirmed against
the official package documentation before applying the fix. **Fix**:
drop the first row of `SmoothProb` (index 1, the t=0 prior), not the last,
when aligning with the project's T=4175 dates.

## 4. Results

### 4.1 Fitted parameters

```
             Estimate   Std.Error    t value      Pr(>|t|)
alpha0_1   0.0001241    0.0002112    0.587        0.278   (omega, regime 1)
alpha1_1   0.0106220    0.0077169    1.376        0.084   (alpha, regime 1)
beta_1     0.9864591    0.0013367  737.970        <1e-16  (beta, regime 1)
nu_1       7.0711       0.9083       7.785        <1e-14  (regime 1)
alpha0_2   0.0057432    0.0039894    1.440        0.075   (omega, regime 2)
alpha1_2   0.0090000    0.0132647    0.678        0.249   (alpha, regime 2)
beta_2     0.9802132    0.0083909  116.818        <1e-16  (beta, regime 2)
nu_2      22.0046      16.8510       1.306        0.096   (regime 2, imprecise)
P_1_1      0.99753      0.00311    320.741        <1e-16  (stay in regime 1)
P_2_1      0.00627      0.00130      4.809        <1e-6   (regime 2 -> regime 1)

LL: -2806.64   AIC: 5633.27   BIC: 5696.64
Stable probabilities: Regime 1 = 71.7%, Regime 2 = 28.3%
```

### 4.2 Which regime is "high volatility"?

Long-run (unconditional) variance per regime, ω/(1−α−β):

| Regime | α+β | Half-life (within-regime GARCH persistence) | Long-run σ |
|---|---|---|---|
| 1 | 0.9971 | 237.1 days | 0.206 |
| 2 | 0.9892 | 63.9 days | 0.730 |

**Regime 2 is the high-volatility regime** (long-run σ more than 3.5x
regime 1's), occurring 28.3% of the time — broadly consistent in order of
magnitude with the HMM's "high volatility" state frequency (32.9%) in
`regime_hmm.md`, a rough but reassuring cross-check between the two
independent methods.

### 4.3 A counter-intuitive but economically sensible finding

The high-volatility regime has **lower** GARCH persistence (α+β = 0.989,
63.9-day half-life) than the low-volatility regime (α+β = 0.997, 237.1-day
half-life). In plain terms: **acute stress fades faster than calm
periods last**. This makes economic sense — a crisis shock (e.g. a central
bank surprise, a liquidity panic) is intense but tends to resolve within a
few months, whereas a calm regime, once established, can persist for the
better part of a year before the next disruption.

**Important distinction, easy to conflate**: this within-regime half-life
(how fast GARCH shocks decay *inside* a regime) is a different concept
from the Markov chain's own regime duration (how long the market *stays*
in a given regime before switching). Using 1/(1−P), the Markov-implied
expected regime durations are:

- Regime 1 (low vol): 1/(1−0.99753) ≈ **404 days**
- Regime 2 (high vol): 1/(1−0.99373) ≈ **160 days**

Both regime *durations* are longer than their respective *within-regime
half-lives* — expected, since a regime can persist long after most of a
given shock's direct effect has already decayed within it.

### 4.4 Regime 2's tail parameter (ν₂ = 22) is imprecisely estimated

ν₂ = 22.0 (p = 0.096, not significant at 5%) is far higher than regime 1's
ν₁ = 7.07 (highly significant) — implying near-Gaussian tails in the
high-volatility regime, versus fat tails in the low-volatility regime.
This is plausible (the regime split may itself be absorbing some of the
extreme events that drove the single-regime model's fat tails, similar to
the mechanism discussed for the HMM's Gaussian emissions in
`regime_hmm.md` section 5) but the large standard error (16.85) means this
specific estimate should not be treated as precise — likely a consequence
of Regime 2 containing a smaller number of observations (~28% of 4,175 ≈
1,183 days) than Regime 1, reducing the precision with which a shape
parameter like ν can be pinned down.

## 5. Comparison with the single-regime GARCH (`GARCH_1_1.md`)

| | Single-regime (Student's t) | MS-GARCH (K=2) |
|---|---|---|
| Log-likelihood | -2818.39 | -2806.64 (+11.75) |
| AIC | 5646.78 | **5633.27** (-13.51, favors MS-GARCH) |
| BIC | 5678.46 | 5696.64 (**+18.18, favors single-regime**) |

**AIC and BIC disagree** — a common and expected outcome when comparing a
regime-switching model to its single-regime counterpart: AIC penalizes
extra parameters less severely than BIC, and MS-GARCH adds 6 parameters
over the single-regime model (10 vs. 4). This is reported plainly as a
genuine ambiguity, not resolved in favor of either model — the honest
conclusion is that **the added complexity of MS-GARCH buys a real but
modest improvement in fit, at a parameter cost that BIC judges as not
worthwhile, while AIC judges as worthwhile**. Neither criterion is
"more correct" in general; this is a known, unresolved tension in model
selection between AIC (better for prediction-oriented use) and BIC (better
for parsimony/true-model-identification-oriented use).

## 6. Case study: does the model detect the COVID-19 shock? (March 2020)

This check was run specifically because a first look at regime
classifications by year (using the Viterbi path, the single most likely
regime per day) showed 2020 spending only 36 out of 249 trading days
(≈14%) in the high-volatility regime — surprisingly low compared to
2010-2012 (Eurozone debt crisis years, 39-100% high-vol days) and 2022
(81% high-vol days). This was investigated rather than assumed to be
either a genuine economic finding or a model flaw.

### 6.1 What the smoothed probabilities actually show

Examining the smoothed probability of the high-volatility regime day by
day around the shock:

| Date | P(high-vol regime) |
|---|---|
| 2020-02-18 | 9.2% |
| 2020-02-25 | 56.8% |
| 2020-02-26 | 91.5% |
| 2020-02-28 | 99.4% |
| 2020-03-11 | **99.998%** |
| 2020-03-19 | 98.4% |
| 2020-04-01 | 77.6% |
| 2020-04-17 | 25.4% |
| 2020-04-30 | 14.9% |

**The model did detect the shock clearly and quickly** — the probability
rises from 9% to over 99% in about three weeks (Feb 18 – Mar 11), exactly
tracking the real-world COVID market panic, then decays back down over
the following six weeks.

### 6.2 Why the annual Viterbi count was misleading

The Viterbi path only records which regime has the *higher* probability
on a given day (a binary >50% cutoff), collapsing a smooth, informative
probability trajectory into a coarse yes/no label. The elevated-probability
window here (roughly Feb 26 – Apr 13, about 40 trading days above 50%) is
of a similar order to the 36-day count found — the annual tally was not
wrong, but it **discards the shape of the transition**: a genuinely fast,
extreme spike (9% → 99.998% in three weeks) looks statistically identical
in a simple day-count to a slower, weaker one that happens to cross 50%
for a similar number of days. **Lesson for interpretation, documented
here rather than left implicit**: comparing regimes by day-count per year
is too coarse a measure to judge relative shock intensity; the smoothed
probability trajectory (peak level, speed of transition) is the
economically meaningful signal, and the Viterbi/day-count view should be
treated as a simplification, not a substitute for it.

## 7. Economic interpretation — what this means for someone watching the market

Bringing sections 4-6 together into plain economic terms:

- EUR/USD alternates between two structurally different volatility
  worlds: a **calm regime** (σ ≈ 0.21, occurring ~72% of the time,
  persisting on average over a year once entered) and a **stress regime**
  (σ ≈ 0.73 — more than 3.5x as volatile — occurring ~28% of the time,
  persisting on average about 5-6 months).
- Within a stress regime, the intensity of shocks fades **faster**
  (half-life ~64 days) than within a calm regime shocks fade
  (~237 days) — stress is sharp but comparatively short-lived at the
  shock level, even though the *regime itself* (the Markov state) can
  still take months to fully resolve.
- The model responds to a real, sudden crisis (COVID, March 2020) within
  about three weeks, moving from near-certainty of "calm" to
  near-certainty of "stress" — a genuinely fast, usable early-warning
  signal, not merely a slow-moving average.
- Compared to a single, undifferentiated GARCH (`GARCH_1_1.md`), this
  model offers a materially better description of how volatility actually
  evolves (matching the instability finding in `garch_stability.md`): it
  explicitly answers "which of two regimes are we in", rather than
  averaging both regimes' dynamics into one fixed set of parameters — at
  the acknowledged cost of a heavier, harder-to-estimate model whose
  benefit is judged worthwhile by one standard criterion (AIC) and not
  worthwhile by another (BIC).

## 8. Known limitations

- MS-GARCH estimation relies on an approximation to the true (intractable)
  likelihood (section 1) — not exact, even in the reference implementation.
- ν₂ (regime 2's tail parameter) is imprecisely estimated (section 4.4);
  should not be over-interpreted on its own.
- AIC and BIC disagree on whether the added complexity is justified
  (section 5) — this project does not adjudicate between the two criteria,
  reporting the disagreement instead of picking a side to force a clean
  narrative.
- K=2 was not compared against K=3 at this stage (see section 2's
  rationale for starting at 2); a natural extension, not yet undertaken.
- This stage depends on R and the MSGARCH package — a deliberate,
  documented exception to the rest of the project's Python pipeline
  (section 1), which means it cannot be re-run purely from the Python
  codebase without R installed alongside it.

## 9. Files produced at this stage

- `src/ms_garch.R` — model specification, ML fitting, per-regime parameter
  extraction, transition matrix, and smoothed regime probability export
- `data/processed/ms_garch_transition_matrix.csv`
- `data/processed/ms_garch_regime_probs.csv` — per-day smoothed
  probabilities for both regimes, aligned with EUR/USD trading dates

